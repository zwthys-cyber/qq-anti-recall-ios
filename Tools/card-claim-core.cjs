'use strict';
const VERSION='1.2.0';
const SITE='https://qqqzz.cc';
const modes=new Set(['inspect','eligibility','submit-once']);
function targetMatches(raw,target){
 try {
  const walk=v=>v===target||(Array.isArray(v)?v.some(walk):v&&typeof v==='object'?Object.values(v).some(walk):false);
  return walk(JSON.parse(raw||''));
 }catch{try{return [...new URLSearchParams(raw||'').values()].includes(target);}catch{return false;}}
}
function classify(stage,http,data){
 const msg=typeof data?.msg==='string'?data.msg:'';
 if(http===429||/名额不足|额度|上限|次数限制/.test(msg))return 'quota_exhausted';
 if(/已.*(领取|下单|购买)/.test(msg))return 'already_claimed';
 if(/验证码|验证/.test(msg)||data?.code===2)return 'verification_required';
 if(/登录/.test(msg)||data?.code===4)return 'login_required';
 if(http<200||http>=300)return 'http_error';
 if(!data||typeof data!=='object'||Array.isArray(data))return 'unrecognized_response';
 if(data.code!==200)return 'provider_rejected';
 if(stage==='preview'){
  const d=data.data,p=d?.final_price;
  if(d?.is_free===true&&(typeof p==='number'||typeof p==='string')&&String(p).trim()!==''&&Number.isFinite(Number(p))&&Number(p)===0)
   return 'free_preview_available';
  return 'free_price_not_confirmed';
 }
 return 'order_accepted';
}
function guard(mode,env){
 if(!modes.has(mode))throw Error('invalid_mode');
 if(mode!=='inspect'&&!/^[1-9][0-9]{4,11}$/.test(env.QQ_CARD_CLAIM_TARGET||''))throw Error('missing_target_secret');
 if(mode==='submit-once'){
  if(env.CLAIM_ALLOW_SUBMIT!=='true')throw Error('submission_disabled');
  if(env.GITHUB_EVENT_NAME!=='workflow_dispatch')throw Error('manual_dispatch_required');
  if(env.GITHUB_RUN_ATTEMPT!=='1')throw Error('rerun_submission_disabled');
 }
}
function gate(mode,target){
 let armed=false,used=false;
 return {
  arm(status){armed=mode==='submit-once'&&status==='free_preview_available'&&!used;},
  allow(url,method,body){
   if(used||!armed||mode!=='submit-once'||url!==SITE+'/api/add'||method!=='POST'||!targetMatches(body,target))return false;
   used=true;armed=false;return true;
  },
  get used(){return used;}
 };
}
module.exports={VERSION,SITE,classify,guard,gate,targetMatches};
