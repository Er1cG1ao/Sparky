// Native prototype: no Python, Chromium, native script-message handler, or remote code loader.
// DOM primitives in selectors.json are adapted from DouYinSparkFlow (MIT).
(() => {
  if (window.__sparkPrototype) return;
  const state = {profile: null, receipts: [], captureErrors: 0, requestSerial: 0, attempts: new Map(), editorSerial: 0, editorIDs: new WeakMap()};
  const clean = value => String(value ?? '').replace(/\u00a0/g, ' ').trim();
  // Draft.js can insert U+200B as an editor-edge placeholder. Keep meaningful
  // internal characters and whitespace; normalize only presentation boundaries.
  const messageText = value => String(value ?? '').replace(/\u00a0/g,' ').replace(/^[\s\u200B]+|[\s\u200B]+$/gu,'');
  const isSelf = url => /\/aweme\/v1\/web\/user\/profile\/self(?:\/|\?|$)/.test(String(url));
  const isSend = url => {
    try {const u = new URL(String(url),location.href);return u.hostname === 'imapi.douyin.com' && u.pathname === '/v1/message/send';}
    catch {return false;}
  };
  function fields(bytes) {
    let p=0;const out=[];
    function integer(){let n=0n,s=0n;for(let i=0;i<10;i++){if(p>=bytes.length)throw Error('truncated');let b=bytes[p++];n|=BigInt(b&127)<<s;if(!(b&128))return n;s+=7n;}throw Error('varint');}
    while(p<bytes.length){const key=Number(integer()),tag=key>>3,wire=key&7;let value;
      if(!tag)throw Error('invalid tag');
      if(wire===0)value=integer();
      else if(wire===2){let n=Number(integer());if(n<0||p+n>bytes.length)throw Error('length');value=bytes.slice(p,p+n);p+=n;}
      else if(wire===1||wire===5){p+=wire===1?8:4;if(p>bytes.length)throw Error('truncated');continue;}
      else throw Error('wire');out.push({tag,wire,value});}
    return out;
  }
  function decodeReceipt(bytes) {
    const fs=fields(bytes),pick=(items,n)=>items.find(f=>f.tag===n),text=b=>new TextDecoder().decode(b);
    const c=pick(fs,3),s=pick(fs,4),body=pick(fs,6);let messageID='';
    if(body?.wire===2){const inner=pick(fields(body.value),100);if(inner?.wire===2){const id=pick(fields(inner.value),1);if(id?.wire===0)messageID=id.value.toString();}}
    const code=c?.wire===0?Number(c.value):null,status=s?.wire===2?text(s.value):'';
    return {ok:code===0&&status.toLowerCase()==='ok',code,status,messageID};
  }
  function captureProfile(value) {
    const u=value?.user;
    if(!u||typeof u!=='object')return;
    state.profile={nickname:clean(u.nickname||u.other_nickname),douyinID:clean(u.unique_id||u.short_id),uid:clean(u.uid)};
  }
  async function capture(url,response,requestID,requestStarted) {
    try {
      if(isSelf(url))captureProfile(await response.clone().json());
      if(isSend(url)){const clone=response.clone();const bytes=new Uint8Array(await clone.arrayBuffer());state.receipts.push({...decodeReceipt(bytes),at:Date.now(),requestID,requestStarted});state.receipts=state.receipts.slice(-30);}
    } catch {state.captureErrors++;}
  }
  const nativeFetch=window.fetch;
  if(nativeFetch)window.fetch=function(...args){const result=Reflect.apply(nativeFetch,this,args);const url=args[0]?.url||args[0];const requestID=isSend(url)?++state.requestSerial:0,requestStarted=Date.now();result.then(r=>capture(url,r,requestID,requestStarted),()=>{});return result;};
  const proto=window.XMLHttpRequest?.prototype;
  if(proto){const open=proto.open,send=proto.send;const urls=new WeakMap();
    proto.open=function(method,url,...rest){urls.set(this,String(url));return Reflect.apply(open,this,[method,url,...rest]);};
    proto.send=function(...args){const sendURL=urls.get(this)||'',requestID=isSend(sendURL)?++state.requestSerial:0,requestStarted=Date.now();this.addEventListener('load',()=>{const url=urls.get(this)||'';try{
      if(isSelf(url))captureProfile(this.responseType==='json'?this.response:JSON.parse(this.responseText));
      if(isSend(url)){let b;if(this.responseType==='arraybuffer')b=Promise.resolve(new Uint8Array(this.response));else if(this.response instanceof Blob)b=this.response.arrayBuffer().then(x=>new Uint8Array(x));
        if(b)b.then(bytes=>{state.receipts.push({...decodeReceipt(bytes),at:Date.now(),requestID,requestStarted});state.receipts=state.receipts.slice(-30);}).catch(()=>state.captureErrors++);}
    }catch{state.captureErrors++;}},{once:true});return Reflect.apply(send,this,args);};
  }
  function convOf(el){for(const key of Object.keys(el)){if(key.startsWith('__reactProps$')&&el[key]?.conversation)return el[key].conversation;
    if(key.startsWith('__reactFiber$')){let f=el[key];for(let i=0;f&&i<35;i++,f=f.return){if(f.memoizedProps?.conversation)return f.memoizedProps.conversation;}}}return null;}
  function avatarOf(el,c){
    const image=el.querySelector('[class*="avatar"] img, img[class*="avatar"], img');
    const candidates=[image?.currentSrc,image?.getAttribute('src'),image?.getAttribute('data-src'),c?.avatarUrl,c?.avatar_url,c?.icon];
    for(const raw of candidates){if(typeof raw!=='string'||!raw)continue;try{const u=new URL(raw,location.href);if(u.protocol==='https:')return u.href;}catch{}}return null;
  }
  function rows(){return [...document.querySelectorAll('[data-e2e="conversation-item"]')].map((el,index)=>{
    const c=convOf(el);let group=false;try{group=Number(c?.type)===2||Number(c?.participantCount)>2;}catch{}
    const id=clean(c?.id||c?.conversationId),title=clean(el.querySelector('.conversationConversationItemtitle')?.textContent),avatarURL=avatarOf(el,c);
    // React mounts IDs before the participant profile has hydrated. Never
    // manufacture a display name: the native scanner must wait or retry.
    const titleReady=!!title&&title!==id;
    const profilePending=!titleReady||(/^[0-9]{6,}$/.test(title)&&!avatarURL)||el.getAttribute('aria-busy')==='true';
    return {id,title,titleReady,profilePending,group,index,avatarURL};});}
  function current(){const el=document.querySelector('.conversationConversationItemcurConversation');if(!el)return null;const c=convOf(el);return {id:clean(c?.id||c?.conversationId),title:clean(el.querySelector('.conversationConversationItemtitle')?.textContent)};}
  function editor(){return document.querySelector('[data-e2e="msg-input"] .public-DraftEditor-content, .DraftEditor-root [contenteditable="true"], [data-e2e="msg-input"] [contenteditable="true"]');}
  function status(){const login=!!document.querySelector('[data-e2e="login-container"]'),chat=!!document.querySelector('.conversationConversationListwrapper, [data-e2e="msg-input"]');
    return {loginVisible:login,chatReady:chat&&!login,profile:state.profile,current:current(),visibleCount:rows().length,receiptCount:state.receipts.length,captureErrors:state.captureErrors};}
  function select(id){const items=[...document.querySelectorAll('[data-e2e="conversation-item"]')];const el=items.find(e=>clean(convOf(e)?.id||convOf(e)?.conversationId)===id);if(!el)return false;
    for(const t of ['pointerdown','mousedown','pointerup','mouseup','click'])el.dispatchEvent(t.startsWith('pointer')?new PointerEvent(t,{bubbles:true,cancelable:true,view:window}):new MouseEvent(t,{bubbles:true,cancelable:true,view:window}));return true;}
  function scroll(reset=false){const el=document.querySelector('.conversationConversationListwrapper');if(!el)return {found:false};const before=el.scrollTop;
    el.scrollTo({top:reset?0:before+Math.max(1,el.clientHeight*.65),behavior:'instant'});el.dispatchEvent(new Event('scroll',{bubbles:true}));
    return {found:true,before,top:el.scrollTop,bottom:el.scrollTop+el.clientHeight>=el.scrollHeight-2};}
  function draftState(){const ed=editor();return {exists:!!ed,text:ed?.textContent||'',current:current()};}
  function inspectDraft(id,text){const ed=editor(),raw=ed?.textContent||'',actual=messageText(raw),expected=messageText(text),cur=current();
    if(ed&&!state.editorIDs.has(ed))state.editorIDs.set(ed,++state.editorSerial);
    const signature=JSON.stringify([cur?.id,state.editorIDs.get(ed),raw]);
    const a=Array.from(actual),b=Array.from(expected);let index=0;while(index<a.length&&index<b.length&&a[index]===b[index])index++;
    const code=c=>c===undefined?'END':'U+'+c.codePointAt(0).toString(16).toUpperCase().padStart(4,'0');
    return {signature,exists:!!ed,empty:actual==='',identityMatches:cur?.id===id,matches:!!ed&&cur?.id===id&&actual===expected,
      actualLength:a.length,expectedLength:b.length,rawLength:Array.from(raw).length,
      difference:actual===expected?'none':`index=${index}, webpage=${code(a[index])}, expected=${code(b[index])}`};}
  function sendButton(){
    for(const selector of ['.messageMsgInputpublishBtn.messageMsgInputpublishRedBtn','[data-e2e="msg-send"]','.messageMsgInputpublishBtn']){
      const el=[...document.querySelectorAll(selector)].find(e=>{const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>0&&r.height>0&&s.display!=='none'&&s.visibility!=='hidden';});
      if(el)return el;
    }return null;
  }
  function sendDiagnostic(){const btn=sendButton();return {found:!!btn,tag:btn?.tagName||'',classes:typeof btn?.className==='string'?btn.className:btn?.getAttribute('class')||'',disabled:!!btn&&(!!btn.disabled||btn.getAttribute('aria-disabled')==='true'),hasClickFunction:typeof btn?.click==='function'};}
  function send(id,text){const check=inspectDraft(id,text);if(!check.identityMatches)throw Error('会话已变化，拒绝发送');if(!check.matches)throw Error(`网页草稿与测试内容不一致：网页 ${check.actualLength} 字符、期望 ${check.expectedLength} 字符；${check.difference}。未点击发送。`);
    const btn=sendButton();
    if(!btn)throw Error('找不到可见发送按钮（已尝试就绪按钮、msg-send 和基础按钮选择器）');
    if(btn.disabled||btn.getAttribute('aria-disabled')==='true')throw Error('发送按钮处于禁用状态');
    // One mouse gesture, supporting SVG elements without HTMLElement.click().
    // Never follow it with another gesture or Enter if delivery is uncertain.
    const started=Date.now(),token=String(started)+'-'+Math.random().toString(36).slice(2),items=[...document.querySelectorAll('[data-e2e="msg-item-content"]')];
    state.attempts.set(token,{id,text,started,requestAfter:state.requestSerial,beforeNode:items.at(-1),beforeCount:items.length});
    if(state.attempts.size>100)state.attempts.delete(state.attempts.keys().next().value);
    for(const type of ['mousedown','mouseup','click'])btn.dispatchEvent(new MouseEvent(type,{bubbles:true,cancelable:true,view:window}));
    return {started,token,tag:btn.tagName};}
  function proof(id,text,ticket){const cur=current();if(cur?.id!==id)return {state:'changed'};
    const attempt=typeof ticket==='object'?state.attempts.get(ticket.token):null;
    const started=attempt?.started??ticket;
    const receipt=state.receipts.find(r=>r.at>=started&&(!attempt||(r.requestID>attempt.requestAfter&&r.requestStarted>=attempt.started)));
    if(receipt)return {state:receipt.ok?'ack':'rejected',receipt};
    const items=[...document.querySelectorAll('[data-e2e="msg-item-content"]')],last=items.at(-1);
    const fresh=attempt?items.length>attempt.beforeCount||last!==attempt.beforeNode:false;
    const domSeen=fresh&&!!last&&!!last.closest('.MessageBoxContentisFromMe')&&messageText(last.textContent)===messageText(text)&&messageText(editor()?.textContent)==='';
    return {state:'waiting',domSeen,editorEmpty:messageText(editor()?.textContent)===''};}
  Object.defineProperty(window,'__sparkPrototype',{value:Object.freeze({status,rows,current,select,scroll,draftState,inspectDraft,sendDiagnostic,send,proof,decodeReceipt}),configurable:false,writable:false});
})();
