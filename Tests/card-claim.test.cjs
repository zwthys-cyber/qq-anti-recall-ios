'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {SITE,classify,guard,gate,targetMatches}=require('../Tools/card-claim-core.cjs');
test('preview success does not imply order eligibility or arrival',()=>{
 assert.equal(classify('preview',200,{code:200,data:{is_free:true,final_price:0}}),'free_preview_available');
 assert.equal(classify('receipt',200,{code:-1,msg:'检查免费商品失败: 本商品可购买或领取的名额不足，请稍后重试'}),'quota_exhausted');
});
test('price must explicitly be zero; missing, boolean and whitespace values fail closed',()=>{
 for(const p of [undefined,null,'', ' ',false,[],{},1,-1,'NaN','Infinity'])
  assert.equal(classify('preview',200,{code:200,data:{is_free:true,final_price:p}}),'free_price_not_confirmed');
 for(const p of [0,'0','0.00'])
  assert.equal(classify('preview',200,{code:200,data:{is_free:true,final_price:p}}),'free_preview_available');
});
test('HTTP failures never become accepted orders',()=>{
 assert.equal(classify('receipt',500,{code:200}),'http_error');
 assert.equal(classify('receipt',429,{code:200}),'quota_exhausted');
 assert.equal(classify('receipt',200,{code:200}),'order_accepted');
 assert.equal(classify('receipt',200,{code:-1,msg:'今日已领取'}),'already_claimed');
 assert.equal(classify('receipt',200,{code:2}),'verification_required');
 assert.equal(classify('receipt',200,{code:4}),'login_required');
 assert.equal(classify('receipt',200,null),'unrecognized_response');
});
test('order gate requires correct origin, POST, exact target and one permit',()=>{
 const g=gate('submit-once','123456');
 assert.equal(g.allow(SITE+'/api/add','POST','{"0":"123456"}'),false);
 g.arm('free_preview_available');
 assert.equal(g.allow('https://example.com/api/add','POST','{"0":"123456"}'),false);
 assert.equal(g.allow(SITE+'/api/add','GET','{"0":"123456"}'),false);
 assert.equal(g.allow(SITE+'/api/add','POST','{"0":"1234567"}'),false);
 assert.equal(g.allow(SITE+'/api/add','POST','{"0":"123456"}'),true);
 g.arm('free_preview_available');
 assert.equal(g.allow(SITE+'/api/add','POST','{"0":"123456"}'),false);
});
test('read-only modes block every order even when armed',()=>{
 for(const m of ['inspect','eligibility']){
  const g=gate(m,'123456');g.arm('free_preview_available');
  assert.equal(g.allow(SITE+'/api/add','POST','{"0":"123456"}'),false);
 }
});
test('no automatic submission, reruns or invalid target',()=>{
 const e={QQ_CARD_CLAIM_TARGET:'123456',CLAIM_ALLOW_SUBMIT:'true',GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_RUN_ATTEMPT:'1'};
 assert.doesNotThrow(()=>guard('submit-once',e));
 for(const delta of [{CLAIM_ALLOW_SUBMIT:'false'},{GITHUB_EVENT_NAME:'push'},{GITHUB_RUN_ATTEMPT:'2'},{QQ_CARD_CLAIM_TARGET:''}])
  assert.throws(()=>guard('submit-once',{...e,...delta}));
 assert.throws(()=>guard('other',e));
 assert.doesNotThrow(()=>guard('inspect',{}));
});
test('target matching does not accept substrings or malformed data',()=>{
 assert.equal(targetMatches('{"0":"123456"}','123456'),true);
 assert.equal(targetMatches('0=123456&pt=83','123456'),true);
 assert.equal(targetMatches('{"0":"1234567"}','123456'),false);
});
test('default command with invalid mode produces a redacted result without network',()=>{
 const {spawnSync}=require('node:child_process'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
 const cwd=fs.mkdtempSync(path.join(os.tmpdir(),'claim-test-'));
 try{
  const r=spawnSync(process.execPath,[path.resolve(__dirname,'../Tools/card-claim.cjs')],{cwd,encoding:'utf8',env:{...process.env,CLAIM_MODE:'invalid',QQ_CARD_CLAIM_TARGET:'123456789',GITHUB_STEP_SUMMARY:''}});
  assert.equal(r.status,1);
  const output=fs.readFileSync(path.join(cwd,'results/card-claim.json'),'utf8');
  assert.equal(output.includes('123456789'),false);
  assert.equal(r.stdout.includes('123456789'),false);
  const j=JSON.parse(output);assert.equal(j.submitted,false);assert.equal(j.arrival_verified,false);
  assert.equal(j.failure_stage,'startup');
 }finally{fs.rmSync(cwd,{recursive:true,force:true});}
});
