const {chromium}=require('playwright-core');
(async()=>{
 const q=(process.env.QQ_CARD_CLAIM_TARGET||'').trim();if(!/^[1-9][0-9]{4,11}$/.test(q))throw Error();
 const b=await chromium.launch({headless:true});
 try{
 const c=await b.newContext({serviceWorkers:'block'});
 await c.route('**/*',async r=>new URL(r.request().url()).pathname.replace(/\/+$/,'')==='/api/add'?r.abort():r.continue());
 const p=await c.newPage();
 await p.goto('https://qqqzz.cc/',{waitUntil:'domcontentloaded',timeout:60000});await p.waitForTimeout(12000);
 await p.goto('https://qqqzz.cc/#/orders',{waitUntil:'domcontentloaded',timeout:45000});
 const r=await c.request.post('https://qqqzz.cc/api/queryOrder',{data:{type:2,name:q,page:1,size:10},timeout:30000});
 const j=await r.json();const list=Array.isArray(j.data)?j.data:[];
 const mappingResponse=await c.request.get('https://qqqzz.cc/api/orderStatusCodes',{timeout:20000});
 const mapping=await mappingResponse.json();
 const safeLabels=new Set(['未处理','成功','失败','待处理','进行中','已完成','已退款','售后中','已收货','已超时','未支付']);
 const statuses=list.map(x=>{
  const v={};
  for(const k of ['code','is_received','status','state','status_text','state_text','is_complete','is_completed','complete','completed'])
   if(['number','boolean'].includes(typeof x[k])||(typeof x[k]==='string'&&/^(?:\d{1,3}|已完成|未完成|处理中|待处理|已取消|已退款|已付款|未付款)$/.test(x[k])))v[k]=x[k];
  const label=mapping.data?.list?.find(a=>Number(a.code)===Number(x.code))?.label;if(safeLabels.has(label))v.display_label=label;
  return v;
 });
 await p.waitForTimeout(1500);
 const text=await p.locator('body').innerText();
 const labels={};for(const k of ['已完成','处理中','待处理','已取消','已退款','待付款'])labels[k]=text.split(k).length-1;
 console.log('ORDER_LOOKUP '+JSON.stringify({http:r.status(),code:j.code,records:list.length,statuses,visible_status_label_counts:labels,submitted:false}));
 }finally{await b.close();}
})().catch(()=>{console.log('ORDER_LOOKUP_FAILED no_order_submitted');process.exitCode=1;});
