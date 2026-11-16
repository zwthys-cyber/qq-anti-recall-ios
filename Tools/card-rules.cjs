const {chromium}=require('playwright-core');
const SITE='https://qqqzz.cc';
const clean=s=>s.replace(/[0-9]{5,}/g,'[number]').slice(0,600);
(async()=>{
 const b=await chromium.launch({headless:true});
 try{
 const c=await b.newContext({serviceWorkers:'block'});
 await c.route('**/*',async r=>{
  if(new URL(r.request().url()).pathname.replace(/\/+$/,'')==='/api/add')return r.abort();
  return r.continue();
 });
 const p=await c.newPage(),assets=new Set(),pending=[];
 p.on('response',r=>{
  const u=new URL(r.url());if(u.origin!==SITE)return;
  if(u.pathname.endsWith('.js'))assets.add(u.origin+u.pathname);
  if(!u.pathname.startsWith('/api/'))return;
  pending.push((async()=>{try{
   const j=await r.json(),fields=[];
   function walk(v,path='',depth=0){
    if(!v||typeof v!=='object'||depth>3)return;
    for(const [k,x] of Object.entries(v).slice(0,120)){
     if(/token|cookie|secret|password|customer|qq|uin|user|session/i.test(k))continue;
     const key=path+k;
     if(/limit|quota|stock|free|day|num|count|interval|cooldown|reset|price/i.test(k)&&['number','boolean'].includes(typeof x))
      fields.push({key,value:x});
     if(x&&typeof x==='object'&&!Array.isArray(x))walk(x,key+'.',depth+1);
    }
   }walk(j);
   if(u.pathname==='/api/getGoodsById'){
    for(const k of ['sale_restriction','buy_rate','note','docs','metadata']){
 const v=j.data?.[k];
 if(['sale_restriction','buy_rate'].includes(k))console.log('PUBLIC_RESTRICTION '+JSON.stringify({key:k,value:v}));
 else if(typeof v==='string')console.log('PUBLIC_DESCRIPTION '+JSON.stringify({key:k,value:clean(v)}));
 else if(v&&typeof v==='object')console.log('PUBLIC_METADATA '+JSON.stringify({key:k,value:Object.fromEntries(Object.entries(v).filter(([name])=>['允许重复下单','数量选择','最大下单','最小下单','默认数量'].includes(name)))}));
 }
 console.log('PRODUCT_CONFIG_KEYS '+JSON.stringify(Object.fromEntries(Object.entries(j.data||{}).map(([k,v])=>[k,typeof v]))));
    for(const [k,v] of Object.entries(j.data||{}))if(/free|limit|quota|day|reset|restrict|stock|num/i.test(k)&&typeof v==='string')console.log('PRODUCT_RULE_VALUE '+JSON.stringify({key:k,value:clean(v)}));
   }
   console.log('PUBLIC_API '+JSON.stringify({path:u.pathname,http:r.status(),keys:Object.keys(j).slice(0,30),fields}));
  }catch{}})());
 });
 await p.goto(SITE+'/',{waitUntil:'domcontentloaded',timeout:60000});
 await p.waitForTimeout(12000);
 await p.goto(SITE+'/#/order-confirm/83',{waitUntil:'domcontentloaded',timeout:45000});
 await p.locator('input[placeholder="请输入QQ号码"]').waitFor({timeout:35000});
 await p.waitForTimeout(5000);
 const body=await p.locator('body').innerText();
 console.log('PUBLIC_RULES '+JSON.stringify(body.split('\n').filter(x=>/每天|每日|名额|次数|限领|限购|限额|重置|库存|领取规则/.test(x)).map(clean).slice(0,30)));
 const links=await p.locator('a').evaluateAll(xs=>xs.map(a=>({text:a.textContent,href:a.getAttribute('href')})));
 console.log('RULE_LINKS '+JSON.stringify(links.filter(x=>/规则|说明|帮助/.test(x.text||'')).map(x=>({text:clean(x.text||''),href:(x.href||'').split('?')[0]})).slice(0,10)));
 for(const url of [...assets].filter(u=>new URL(u).pathname.startsWith('/static/')).slice(0,40)){
  const r=await c.request.get(url,{timeout:20000});const source=await r.text();
  if(/OrderConfirmView-/.test(url))console.log('CONFIRM_IMPORTS '+JSON.stringify(source.slice(0,3500)));
  const patterns=/\/api\/add|\/api\/PreviewPrice|检查免费商品|名额不足|free_limit|ip_limit|limit_type/g;
  const hits=[...source.matchAll(patterns)].slice(0,12);
  if(hits.length)console.log('CLAIM_FLOW_SOURCE '+JSON.stringify({path:new URL(url).pathname,samples:hits.map(m=>source.slice(Math.max(0,m.index-1400),m.index+2000))}));
 }
 await Promise.allSettled(pending);
 console.log('RULE_INSPECTION_COMPLETE no_order_submitted');
 }finally{await b.close();}
})().catch(()=>{console.log('RULE_INSPECTION_FAILED');process.exitCode=1;});
