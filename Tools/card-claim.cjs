'use strict';
const fs=require('node:fs');
const {VERSION,SITE,classify,guard,gate,targetMatches}=require('./card-claim-core.cjs');
async function run(){
 const mode=process.env.CLAIM_MODE||'inspect';
 const target=(process.env.QQ_CARD_CLAIM_TARGET||'').trim();
 const result={version:VERSION,mode,status:'not_started',submitted:false,order_accepted:false,arrival_verified:false};
 let browser,stage='startup';
 try{
  guard(mode,{...process.env,QQ_CARD_CLAIM_TARGET:target});
  const {chromium}=require('playwright-core');
  browser=await chromium.launch({headless:true});
  const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true,serviceWorkers:'block'});
  const lock=gate(mode,target);
  await context.route('**/*',async route=>{
   const req=route.request(),u=new URL(req.url());
   if(u.pathname.replace(/\/+$/,'')==='/api/add'){
    if(!lock.allow(req.url(),req.method(),req.postData()))return route.abort();
    result.submitted=true;
   }
   return route.continue();
  });
  const page=await context.newPage();
  stage='product';
  await page.goto(SITE+'/',{waitUntil:'domcontentloaded',timeout:60000});
  await page.waitForTimeout(12000);
  if(new URL(page.url()).origin!==SITE)throw Error('unexpected_site_redirect');
  await page.goto(SITE+'/#/order-confirm/83',{waitUntil:'domcontentloaded',timeout:45000});
  const field=page.locator('input[placeholder="请输入QQ号码"]').first();
  await field.waitFor({state:'visible',timeout:35000});
  const body=await page.locator('body').innerText();
  const button=page.getByRole('button',{name:'免费领取',exact:true});
  if(!body.includes('快刷名片赞100个')||await button.count()!==1)throw Error('product_not_confirmed');
  result.product_confirmed=true;
  if(mode==='inspect'){result.status='product_visible';return result;}
  stage='preview';
  const previewWait=page.waitForResponse(r=>r.url()===SITE+'/api/PreviewPrice'&&targetMatches(r.request().postData(),target),{timeout:60000}).catch(()=>null);
  await field.fill(target);await field.blur();
  const previewResponse=await previewWait;
  if(!previewResponse){result.status='preview_timeout_no_order';return result;}
  let preview;try{preview=await previewResponse.json();}catch{result.status='unrecognized_response';return result;}
  result.preview_http=previewResponse.status();
  result.preview_status=classify('preview',previewResponse.status(),preview);
  result.status=result.preview_status;
  if(result.preview_status!=='free_preview_available'||mode==='eligibility')return result;
  stage='submission';
  const receiptWait=page.waitForResponse(r=>r.url()===SITE+'/api/add'&&targetMatches(r.request().postData(),target),{timeout:65000}).catch(()=>null);
  lock.arm(result.preview_status);
  await button.click({timeout:15000});
  const receiptResponse=await receiptWait;
  if(!receiptResponse){result.status=result.submitted?'submission_unknown_do_not_retry':'submission_not_sent';return result;}
  result.receipt_http=receiptResponse.status();
  let receipt;try{receipt=await receiptResponse.json();}catch{result.status='submission_unknown_do_not_retry';return result;}
  result.status=classify('receipt',receiptResponse.status(),receipt);
  result.order_accepted=result.status==='order_accepted';
  return result;
 }catch{
  result.status=result.submitted?'submission_unknown_do_not_retry':'stopped_without_order';
  result.failure_stage=stage;return result;
 }finally{
  if(browser)await browser.close().catch(()=>{});
  result.finished_at=new Date().toISOString();
 }
}
if(require.main===module)run().then(result=>{
 // Only allowlisted counters and statuses are persisted. Never raw bodies, order identifiers or QQ numbers.
 fs.mkdirSync('results',{recursive:true});
 fs.writeFileSync('results/card-claim.json',JSON.stringify(result,null,2)+'\n');
 console.log('CLAIM_RESULT '+JSON.stringify(result));
 if(process.env.GITHUB_STEP_SUMMARY)fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY,
  '# Card claim '+result.version+'\n\nStatus: **'+result.status+'**\n\nOrder submitted: '+result.submitted+
  '\n\nOrder accepted: '+result.order_accepted+'\n\nArrival verified: false\n');
 if(!['product_visible','free_preview_available','order_accepted'].includes(result.status))process.exitCode=1;
});
module.exports={run};
