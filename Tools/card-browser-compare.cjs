'use strict';
const {chromium}=require('playwright-core');
const {classify,targetMatches}=require('./card-claim-core.cjs');
const SITE='https://qqqzz.cc';
const UA='Mozilla/5.0 (iPhone; CPU iPhone OS 16_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.4 Mobile/15E148 Safari/604.1';
(async()=>{
 const q=(process.env.QQ_CARD_CLAIM_TARGET||'').trim();
 if(!/^[1-9][0-9]{4,11}$/.test(q))throw Error();
 const b=await chromium.launch({headless:true});const results=[];
 try{
  for(const mode of ['chromium','reference_mobile_safari']){
   const out={mode,submitted:false,blocked_orders:0};let stage='startup';
   const c=await b.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true,serviceWorkers:'block',...(mode==='chromium'?{}:{userAgent:UA})});
   try{
    await c.route('**/*',async route=>{
     const req=route.request(),u=new URL(req.url());
     if(u.pathname.replace(/\/+$/,'')==='/api/add'){
      out.blocked_orders++;
      try{
       const j=JSON.parse(req.postData()||'{}');
       out.request_shape={field_count:Object.keys(j).length,free_type:j.type===3,free_pay:j.pay==='free',correct_product:j.pt===83,target_matches:targetMatches(req.postData(),q),has_quantity:Object.hasOwn(j,'num'),has_idempotency:Object.hasOwn(j,'idempotency_key')};
      }catch{out.request_parse_failed=true;}
      return route.abort();
     }
     return route.continue();
    });
    const p=await c.newPage();stage='home';
    await p.goto(SITE+'/',{waitUntil:'domcontentloaded',timeout:60000});await p.waitForTimeout(12000);
    stage='product';await p.goto(SITE+'/#/order-confirm/83',{waitUntil:'domcontentloaded',timeout:45000});
    const input=p.locator('input[placeholder="请输入QQ号码"]').first();await input.waitFor({timeout:35000});
    stage='preview';
    const waiting=p.waitForResponse(r=>r.url()===SITE+'/api/PreviewPrice'&&targetMatches(r.request().postData(),q),{timeout:60000}).catch(()=>null);
    await input.fill(q);await input.blur();const response=await waiting;
    if(!response){out.status='preview_timeout';continue;}
    const data=await response.json();
    out.preview_http=response.status();out.preview_code=Number.isInteger(data.code)?data.code:null;
    out.status=classify('preview',response.status(),data);
    if(out.status!=='free_preview_available')continue;
    stage='intercept_submit';
    const request=p.waitForRequest(r=>new URL(r.url()).pathname==='/api/add',{timeout:15000}).catch(()=>null);
    await p.getByRole('button',{name:'免费领取',exact:true}).click({timeout:15000});
    await request;await p.waitForTimeout(300);
   }catch{out.failure_stage=stage;out.status='inspection_failed';}
   finally{await c.close();results.push(out);console.log('UA_CHECK '+JSON.stringify(out));}
  }
  const valid=results.length===2&&results.every(x=>x.status==='free_preview_available'&&x.blocked_orders===1&&x.request_shape);
  console.log('UA_COMPARISON '+JSON.stringify({comparable:valid,same_request_shape:valid?JSON.stringify(results[0].request_shape)===JSON.stringify(results[1].request_shape):null,submitted:false,shared_runner_egress:true,separate_browser_sessions:true}));
 }finally{await b.close();}
})().catch(()=>{console.log('UA_CHECK_FAILED no_order_submitted');process.exitCode=1;});
