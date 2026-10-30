import test from 'node:test';
import assert from 'node:assert/strict';
import { createHandler } from '../worker/handler.js';

// No real authentication or translation calls. Every upstream is injected here.
const origin = 'https://example.test';
const key = 'fixture-api-key-not-real';
const owner = 'fixture-developer-token-longer-than-24';
const env = { TRANSLATION_API_KEY:'fixture-shared-upstream-secret', LANGPACK_DEVELOPER_TOKEN:owner };
const credentials = {
  MyMemory:{apiKey:key},ZTAITrans:{apiKey:key,tenantId:'my-tenant'},DeepL:{apiKey:key,plan:'free'},Azure:{apiKey:key,region:'eastasia'},Google:{apiKey:key},
  Baidu:{appId:'2015063000000001',secretKey:key},Tencent:{secretId:'fixture-tencent-id',secretKey:key,region:'ap-guangzhou'},Alibaba:{accessKeyId:'fixture-alibaba-id',accessKeySecret:key}
};
const request = (provider, value=credentials[provider], extra={}, headers={}) => new Request(origin+'/api/translation/validate',{method:'POST',headers:{'Content-Type':'application/json',Origin:origin,...headers},body:JSON.stringify({provider,credentials:value,...extra})});
const response = (data,status=200,headers={}) => new Response(JSON.stringify(data),{status,headers});
function good(provider,init,url,text='Good') {
  if(provider==='DeepL')return {character_count:100,character_limit:100000};
  if(provider==='Google')return {data:{languages:[{language:'en'},{language:'zh-CN'}]}};
  if(provider==='MyMemory')return {responseStatus:200,quotaFinished:false,responseDetails:'',responseData:{translatedText:text}};
  if(provider==='ZTAITrans')return {model:'fast',targetLanguage:'English',items:[{id:'segment-1',originalText:'好',translatedText:text}]};
  if(provider==='Azure')return [{translations:[{to:'en',text}]}];
  if(provider==='Baidu')return {from:'zh',to:'en',trans_result:[{src:'好',dst:text}]};
  if(provider==='Tencent')return {Response:{Source:'zh',Target:'en',TargetText:text}};
  return {Code:200,Data:{Translated:text}};
}
async function result(r,provider,status,method) {
  assert.equal(r.status,200);assert.equal(r.headers.get('Cache-Control'),'no-store');
  const data=await r.json();assert.equal(data.provider,provider);assert.equal(data.status,status);assert.equal(data.method,method);
  assert.deepEqual(Object.keys(data).sort(),['billableCharacters','message','method','provider','status']);
  assert.equal(data.billableCharacters,method==='translation'?1:0);
  for(const secret of [key,owner,env.TRANSLATION_API_KEY])assert.ok(!JSON.stringify(data).includes(secret));
  return data;
}

test('save validation makes one fixed request per platform, preferring zero-character read-only checks',async()=>{
  for(const provider of Object.keys(credentials)) {
    let calls=0;
    const handle=createHandler({fetchImpl:async(endpoint,init)=>{
      calls++;const url=new URL(endpoint);assert.equal(url.protocol,'https:');assert.equal(init.redirect,'manual');
      assert.ok(!endpoint.includes(key));
      if(provider==='DeepL') {
        assert.equal(endpoint,'https://api-free.deepl.com/v2/usage');assert.equal(init.method,'GET');assert.equal(init.body,undefined);
        assert.equal(init.headers.Authorization,'DeepL-Auth-Key '+key);
      } else if(provider==='Google') {
        assert.equal(endpoint,'https://translation.googleapis.com/language/translate/v2/languages?model=nmt');assert.equal(init.method,'GET');assert.equal(init.body,undefined);assert.equal(init.headers['X-Goog-Api-Key'],key);
      } else if(provider==='MyMemory') {
        // The private TM key is only in this fixed server-side upstream query.
        assert.equal(url.host,'api.mymemory.translated.net');assert.equal(url.searchParams.get('q'),'好');assert.equal(url.searchParams.get('langpair'),'zh-CN|en');
      } else {
        const body=init.headers['Content-Type']==='application/x-www-form-urlencoded'?Object.fromEntries(new URLSearchParams(init.body)):JSON.parse(init.body);
        if(provider==='ZTAITrans'){assert.equal(body.items[0].content,'好');assert.equal(body.targetLanguage,'English');assert.equal(body.tenantId,'my-tenant');assert.equal(body.model,'fast');}
        if(provider==='Azure')assert.deepEqual(body,[{Text:'好'}]);
        if(provider==='Baidu'){assert.equal(body.q,'好');assert.equal(body.to,'en');}
        if(provider==='Tencent'){assert.equal(body.SourceText,'好');assert.equal(body.Source,'zh');assert.equal(body.Target,'en');}
        if(provider==='Alibaba'){assert.equal(body.SourceText,'好');assert.equal(body.TargetLanguage,'en');assert.equal(body.Scene,'general');}
      }
      return response(good(provider,init,url));
    }});
    // MyMemory's server-side private key URL is documented; never the browser URL.
    if(provider==='MyMemory') {
      const my=createHandler({fetchImpl:async(url,init)=>{calls++;assert.equal(new URL(url).searchParams.get('q'),'好');assert.equal(init.method,'GET');return response(good(provider));}});
      await result(await my(request(provider)),provider,'valid','translation');
    } else await result(await handle(request(provider)),provider,'valid',['DeepL','Google'].includes(provider)?'metadata':'translation');
    assert.equal(calls,1);
  }
});

test('DeepL explicit standard host, account and per-key limits never trigger a trial or automatic host switch',async()=>{
  for(const [usage,status] of [
    [{character_count:0,character_limit:1000},'valid'],
    [{character_count:1000,character_limit:1000},'limited'],
    [{character_count:1,character_limit:1000,api_key_character_count:20,api_key_character_limit:20},'limited'],
    [{character_count:1,character_limit:1000,api_key_character_count:1,api_key_character_limit:1000000000000},'valid'],
    [{character_count:'1',character_limit:1000},'unavailable'],
    [{character_count:1,character_limit:1000,api_key_character_limit:100},'unavailable']
  ]) {
    let calls=0;const handle=createHandler({fetchImpl:async(url)=>{calls++;assert.equal(url,'https://api.deepl.com/v2/usage');return response(usage);}});
    const data=await result(await handle(request('DeepL',{apiKey:key,plan:'pro'})),'DeepL',status,'metadata');assert.equal(calls,1);
    if(status==='valid')assert.match(data.message,/未试译/);
  }
});

test('anonymous MyMemory requires no call while developer mode validates the actual protected shared upstream',async()=>{
  const blocked=createHandler({fetchImpl:()=>assert.fail('must not consume any account')});
  await result(await blocked(request('MyMemory',{apiKey:''})),'MyMemory','valid','anonymous');
  assert.equal((await blocked(request('ZTAITrans',{developerToken:'wrong'}),env)).status,401);
  assert.equal((await blocked(request('ZTAITrans',{developerToken:owner}),{})).status,401);
  let calls=0;
  const handle=createHandler({fetchImpl:async(_,init)=>{calls++;assert.equal(init.headers['X-Api-Key'],env.TRANSLATION_API_KEY);assert.ok(!init.body.includes(owner));return response(good('ZTAITrans'));}});
  await result(await handle(request('ZTAITrans',{developerToken:owner}),env),'ZTAITrans','valid','translation');assert.equal(calls,1);
});

test('auth, quota, rate and service diagnostics are sanitized without retries or fallback',async()=>{
  const cases=[
    ['DeepL',403,{message:key},'invalid'],['DeepL',456,{},'limited'],['DeepL',429,{},'limited'],
    ['Google',403,{error:{errors:[{reason:'keyInvalid'}],message:key}},'invalid'],
    ['Google',403,{error:{errors:[{reason:'dailyLimitExceeded'}]}},'limited'],
    ['Baidu',200,{error_code:'54001',error_msg:key},'invalid'],['Baidu',200,{error_code:'54004'},'limited'],['Baidu',200,{error_code:'58003'},'invalid'],
    ['Tencent',200,{Response:{Error:{Code:'FailedOperation.NoFreeAmount',Message:key}}},'limited'],
    ['Tencent',200,{Response:{Error:{Code:'ActionOffline'}}},'invalid'],
    ['Alibaba',200,{Code:10013,Message:key},'invalid'],['Alibaba',200,{Code:10002},'unavailable'],
    ['Azure',500,{error:{message:key}},'unavailable'],
    ['ZTAITrans',402,{code:'TRANSLATE_BUDGET_EXCEEDED',message:key},'limited'],['ZTAITrans',503,{code:'TRANSLATE_DISABLED'},'invalid']
  ];
  for(const [provider,http,payload,status] of cases){
    let calls=0;const handle=createHandler({fetchImpl:async()=>{calls++;return response(payload,http,{'Retry-After':'999'});}});
    await result(await handle(request(provider),env),provider,status,['DeepL','Google'].includes(provider)?'metadata':'translation');assert.equal(calls,1);
  }
});

test('probes cannot be caller-controlled or borrow environment credentials, and origin/body guards precede all calls',async()=>{
  const handle=createHandler({fetchImpl:()=>assert.fail('invalid request reached provider')});
  for(const extra of [{content:'paid user content'},{locale:'ja'},{endpoint:'https://evil.test'},{retry:true},{fallback:true}])assert.equal((await handle(request('Azure',credentials.Azure,extra),env)).status,400);
  for(const provider of Object.keys(credentials).filter(p=>p!=='MyMemory'))assert.equal((await handle(request(provider,{}),env)).status,400);
  assert.equal((await handle(request('MyMemory',{apiKey:'',endpoint:'https://evil.test'}),env)).status,400);
  assert.equal((await handle(request('Azure',credentials.Azure,{}, {Origin:'https://evil.test'}),env)).status,403);
  assert.equal((await handle(request('Azure',credentials.Azure,{}, {'Sec-Fetch-Site':'same-site'}),env)).status,403);
  assert.equal((await handle(request('Azure',{apiKey:'x'.repeat(20000)}),env)).status,413);
  assert.equal((await handle(new Request(origin+'/api/translation/validate'),env)).status,405);
});

test('malformed identity, credential echoes and redirects are inconclusive rather than falsely usable',async()=>{
  for(const provider of Object.keys(credentials)) {
    const handle=createHandler({fetchImpl:async()=>response(provider==='DeepL'?{character_count:key,character_limit:10000}:provider==='Google'?{data:{languages:[{language:key}]}}:good(provider,null,null,key))});
    await result(await handle(request(provider),env),provider,'unavailable',['DeepL','Google'].includes(provider)?'metadata':'translation');
    let calls=0;const redirect=createHandler({fetchImpl:async(_,init)=>{calls++;assert.equal(init.redirect,'manual');return new Response(null,{status:302,headers:{Location:'https://evil.test'}});}});
    const data=await(await redirect(request(provider),env)).json();assert.notEqual(data.status,'valid');assert.equal(calls,1);
  }
});

test('timeouts and caller cancellation stop a single probe and never retry',async()=>{
  let calls=0,signal;
  const timeout=createHandler({timeoutMs:2,fetchImpl:async(_,init)=>{calls++;signal=init.signal;return new Promise(()=>{});}});
  await result(await timeout(request('Azure')),'Azure','unavailable','translation');assert.equal(calls,1);assert.equal(signal.aborted,true);
  const controller=new AbortController();let start;const started=new Promise(resolve=>{start=resolve;});
  const cancel=createHandler({fetchImpl:async(_,init)=>{calls++;signal=init.signal;start();return new Promise(()=>{});}});
  const pending=cancel(new Request(request('Google'),{signal:controller.signal}));await started;controller.abort();
  await result(await pending,'Google','unavailable','metadata');assert.equal(calls,2);assert.equal(signal.aborted,true);
});
