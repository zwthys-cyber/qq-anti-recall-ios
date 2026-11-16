const {chromium}=require('playwright-core');
const fs=require('fs');
const SITE='https://qqqzz.cc';
const qq=(process.env.QQ_CARD_CLAIM_TARGET||'').trim();
const submit=false;
const eligibility=process.env.CLAIM_MODE==='eligibility';
const out={mode:eligibility?'eligibility':'inspect',submitted:false,order_accepted:false,arrival_verified:false};
const emit=()=>console.log('CLAIM_RESULT '+JSON.stringify(out));
const clean=s=>String(s||'').replace(/[0-9]{5,}/g,'[redacted]').slice(0,300);
(async()=>{
 let browser;
 try{
  if(eligibility && !/^[1-9][0-9]{4,11}$/.test(qq))throw new Error('missing_target_secret');
  if(submit && process.env.GITHUB_RUN_ATTEMPT!=='1')throw new Error('rerun_submission_disabled');
  browser=await chromium.launch({headless:true});
  const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true});
  let permitted=false,posts=0;
  await context.route('**/*',async route=>{
   const req=route.request(),url=new URL(req.url());
   if(url.pathname==='/api/add'){
    if(!submit||!permitted||posts>0||url.origin!==SITE){await route.abort();return;}
    permitted=false; posts++;out.submitted=true;
   }
   await route.continue();
  });
  const page=await context.newPage();
  await page.goto(SITE+'/',{waitUntil:'domcontentloaded',timeout:60000});
  await page.waitForTimeout(12000);
  if(new URL(page.url()).origin!==SITE)throw new Error('unexpected_site_redirect');
  await page.goto(SITE+'/#/order-confirm/83',{waitUntil:'domcontentloaded',timeout:45000});
  const field=page.locator('input[placeholder="请输入QQ号码"]').first();
  await field.waitFor({state:'visible',timeout:35000});
  const body=await page.locator('body').innerText();
  out.product_100=/100/.test(body)&&/名片赞/.test(body);
  out.free_button=await page.getByRole('button',{name:'免费领取',exact:true}).count()>0;
  out.page_excerpt=clean(body.slice(0,1800));
  if(!out.product_100||!out.free_button)throw new Error('product_not_confirmed');
  if(!eligibility){out.status='public_product_ready';emit();return;}
  delete out.page_excerpt;
  const previewPromise=page.waitForResponse(r=>new URL(r.url()).origin===SITE&&new URL(r.url()).pathname==='/api/PreviewPrice'&&(r.request().postData()||'').includes(qq),{timeout:60000});
  await field.fill(qq);await field.blur();
  const previewResp=await previewPromise;const preview=await previewResp.json();
  const d=preview.data;
  out.preview_http=previewResp.status();out.preview_code=preview.code;
  if(!previewResp.ok()||preview.code!==200||!d||d.is_free!==true||d.final_price==null||Number(d.final_price)!==0){
   out.message=clean(preview.msg);throw new Error('free_price_not_confirmed');
  }
  out.status='free_preview_available_not_order_guaranteed';emit();return;
 }catch(e){
  out.status=out.submitted?'submission_outcome_unknown_do_not_retry':'stopped_without_order';
  out.error=clean(e.message);emit();process.exitCode=1;
 }finally{if(browser)await browser.close();}
})();