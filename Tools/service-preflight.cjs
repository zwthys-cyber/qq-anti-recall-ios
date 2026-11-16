'use strict';
const fs=require('node:fs');
const {resolve4}=require('node:dns').promises;
const targets=[
 {project:'qqqzz-card-claim',host:'qqqzz.cc',paths:['/'],scheme:'https'},
 {project:'Qzan',host:'api.isw7.cn',paths:['/','/mpz.php'],scheme:'http'},
 {project:'GratisApi',host:'hlsq8.com.api.yilesup.net',paths:['/'],scheme:'http'}
];
(async()=>{
 const results=await Promise.all(targets.map(async t=>{
  const out={project:t.project,host:t.host,submitted:false,credentials_used:false,checks:[]};
  try{await resolve4(t.host);out.dns='resolved';}catch(e){out.dns=e.code||'failed';return out;}
  for(const path of t.paths){
   const check={path};
   try{
    const r=await fetch(t.scheme+'://'+t.host+path,{redirect:'manual',signal:AbortSignal.timeout(20000)});
    check.http=r.status;check.content_type=(r.headers.get('content-type')||'').split(';')[0];
    const location=r.headers.get('location');if(location){const u=new URL(location,t.scheme+'://'+t.host);check.redirect_host=u.hostname;check.redirect_path=u.pathname;}
    const reader=r.body?.getReader();let text='';
    if(reader){while(text.length<32768){const x=await reader.read();if(x.done)break;text+=new TextDecoder().decode(x.value);}await reader.cancel();}
    check.free_claim_wording=/免费领取|免费名片赞/.test(text);
    check.access_challenge=/meta[^>]*refresh|访问验证|正在验证/.test(text);
    check.requires_parameters=/参数|parameter|QQ号|QQ号码/.test(text);
    check.parked_or_expired=/域名出售|domain.{0,20}(sale|expired)|域名已过期/i.test(text);
   }catch(e){check.error=e.cause?.code||e.name||'request_failed';}
   out.checks.push(check);
  }
  return out;
 }));
 fs.mkdirSync('results',{recursive:true});fs.writeFileSync('results/service-preflight.json',JSON.stringify(results,null,2));
 for(const result of results)console.log('SERVICE_PREFLIGHT '+JSON.stringify(result));
})().catch(()=>{console.log('SERVICE_PREFLIGHT_FAILED');process.exitCode=1;});
