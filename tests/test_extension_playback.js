const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
function extension(options = {}) {
  const nodes=new Map(), requests=[], plays=[], audios=[], highlights=new Map(), utterances=[], events={};
  const element=()=>({style:{},classList:{add(){},remove(){}},listeners:{},innerText:'',offsetWidth:100,
    appendChild(){},closest(){return null;},scrollIntoView(){},querySelector(){return null;},querySelectorAll(){return[];},
    addEventListener(k,f){this.listeners[k]=f;}});
  const paragraph=element();paragraph.innerText=options.text || 'First sentence. שלום עולם.';
  const textNode={nodeType:3,parentElement:paragraph,parentNode:{replaceChild(){}},get nodeValue(){return paragraph.innerText;},get textContent(){return paragraph.innerText;}};
  paragraph.nodeType=1;paragraph.tagName='P';paragraph.childNodes=[textNode];
  paragraph.contains=n=>n===textNode||n===paragraph;
  const makeBlock=(text, tag='P', cls='')=>{const block=element();block.nodeType=1;block.tagName=tag;block.innerText=text;
    block.className=cls;block.matches=sel=>sel.split(',').some(s=>{s=s.trim();return(s.startsWith('.')&&cls.includes(s.slice(1)))||s.toUpperCase()===tag;});
    const node={nodeType:3,parentElement:block,get textContent(){return block.innerText;}};block.childNodes=[node];block.contains=n=>n===node||n===block;return block;};
  let xBlocks;
  if(options.xArticle) {
    xBlocks=[
      makeBlock('How to become disgustingly self-disciplined','H1','longform-header-one'),
      makeBlock('Become so disgusted with where you are, you have no option but to win.','DIV','longform-unstyled'),
      makeBlock('You are not disciplined because you do not view it as discipline.','DIV','longform-unstyled'),
      makeBlock('The pain of staying the same must exceed the pain of change.','BLOCKQUOTE','longform-blockquote'),
      makeBlock('The Launch Phase: fuel for escape velocity.','SECTION','longform-unstyled')
    ];
  } else if(options.x) {
    xBlocks=['Article','Conversation','Become so disgusted with where you are, you have no option but to win.','Rockets use most of their mass as fuel during launch.'].map(t=>makeBlock(t,'P'));
  } else {
    xBlocks=null;
  }
  let showMoreClicked=false;
  const showMoreBtn=options.xTruncated ? {
    nodeType:1,tagName:'BUTTON',innerText:'Show more',offsetWidth:50,offsetParent:{},disabled:false,
    listeners:{},addEventListener(k,f){this.listeners[k]=f;},
    click(){showMoreClicked=true;if(xTweetText){xTweetText.innerText+=' The Launch Phase: fuel for escape velocity.';xTweetText.childNodes[0].textContent=xTweetText.innerText;}},
    closest(){return null;}
  } : null;
  const xTweetText=options.xTruncated ? makeBlock('Become so disgusted with where you are, you have no option but to win. Make it so easy succeed you would look stupid if you fail.','DIV') : null;
  const xTweetArticle=options.xTruncated ? element() : null;
  if(xTweetArticle){
    xTweetArticle.nodeType=1;xTweetArticle.tagName='ARTICLE';xTweetArticle.offsetWidth=500;
    xTweetArticle.querySelectorAll=sel=>{
      if(sel.includes('show-more')) return showMoreClicked?[]:[showMoreBtn];
      if(sel.includes('tweetText')) return [xTweetText];
      return [];
    };
  }
  const xRoot=(options.x || options.xArticle) ? element() : null;
  if(xRoot){xRoot.nodeType=1;xRoot.tagName='ARTICLE';xRoot.innerText=xBlocks.map(b=>b.innerText).join(' ');xRoot.offsetWidth=500;
    xRoot.querySelectorAll=()=>xBlocks;xRoot.contains=n=>xBlocks.some(b=>b.contains(n));}
  const body=element();body.querySelectorAll=()=>[paragraph];
  const overlayParas=[];
  let cleanOverlay=null;
  body.appendChild=child=>{
    if(child?.id==='guy-reader-clean-overlay'){
      cleanOverlay=child;
      child.querySelectorAll=sel=>{
        if(sel.includes('para')) return overlayParas;
        return [];
      };
    }
  };
  const alerts=[];
  const document={body,addEventListener(k,f){events[k]=f;},createElement:(tag)=>{
    const el=element();el.tagName=tag.toUpperCase();
    return el;
  },createDocumentFragment:element,createTextNode:t=>({textContent:t}),
    querySelector(sel){
      if(options.xTruncated && sel.includes('tweet')) return xTweetArticle;
      if((options.x || options.xArticle) && sel.includes('twitterArticleReadView')) return xRoot;
      if(sel.includes('clean-overlay')) return cleanOverlay;
      return null;
    },
    querySelectorAll(sel){
      if(options.xTruncated && (sel.includes('tweet-text-show-more') || sel.includes('show-more'))) return showMoreClicked?[]:[showMoreBtn];
      if(options.xTruncated && sel.includes('tweet')) return [xTweetArticle];
      if((options.x || options.xArticle) && sel.includes('twitterArticleReadView')) return [xRoot];
      if(sel.includes('clean-overlay')) return cleanOverlay ? [cleanOverlay] : [];
      return [];
    },
    createTreeWalker(){let done=false;return{nextNode(){if(done)return null;done=true;return textNode;}};},
    caretPositionFromPoint(){return{offsetNode:textNode,offset:options.clickOffset || 0};},
    createRange(){return{a:0,b:0,setStart(n,o){this.a=o;},setEnd(n,o){this.b=o;},toString(){return paragraph.innerText.slice(this.a,this.b);},getClientRects(){return[];}};},
    getElementById(id){if(!nodes.has(id))nodes.set(id,element());return nodes.get(id);}};
  class Audio {constructor(url){this.src=url;this.paused=true;audios.push(this);}play(){plays.push(this.src);this.paused=false;this.onplay?.();return Promise.resolve();}pause(){this.paused=true;}load(){}removeAttribute(){this.src='';}}
  let receive;
  const window={location:{hostname:(options.x||options.xArticle||options.xTruncated)?'x.com':'example.com'},getSelection(){return{rangeCount:0,isCollapsed:true,toString(){return '';}};},speechSynthesis:{cancel(){},getVoices(){return[{name:'Carmit',lang:'he-IL'}];},speak(u){utterances.push(u);},pause(){},resume(){}}};
  const chrome={storage:{local:{get(defaults,cb){cb({guy_reader_sync:options.sync === true,guy_reader_voice:options.voice || 'af_sarah'});},set(){}}},runtime:{onMessage:{addListener(f){receive=f;}},sendMessage(msg,callback){
    if(msg.action==='reader-state'||msg.action==='reader-focus'){callback?.({success:true});return;}
    if(msg.action==='check-engine-health')callback({available:options.local !== false});
    else if(options.failEdge && msg.action==='synthesize-edge-tts')callback({success:false,error:'offline'});
    else requests.push({msg,resolve(){callback({success:true,audioDataUrl:'data:'+msg.text});}});
  }}};
  vm.runInNewContext(fs.readFileSync('extension/content.js','utf8'),{window,document,chrome,Audio,console,NodeFilter:{SHOW_TEXT:4},CSS:{highlights},Highlight:class {constructor(range){this.range=range;}},SpeechSynthesisUtterance:class {constructor(text){this.text=text;}},setInterval(){},clearInterval(){},URL:{revokeObjectURL(){}},alert(msg){alerts.push(msg);}});
  return{requests,plays,audios,nodes,paragraph,highlights,utterances,events,textNode,alerts,getShowMoreClicked:()=>showMoreClicked,send(action){receive({action},{},()=>{});},settle:()=>new Promise(r=>setImmediate(r))};
}
test('extension remains paused when pending local synthesis finishes',async()=>{
 const r=extension();r.send('read-from-start');r.send('toggle-read');r.requests[0].resolve();await r.settle();
 assert.equal(r.plays.length,0);
 r.send('toggle-read');await r.settle();assert.equal(r.plays.length,1);
});
test('extension applies speed once and routes each sentence language',async()=>{
 const r=extension();r.send('read-from-start');r.requests[0].resolve();await r.settle();
 r.audios.at(-1).onended();await r.settle();
 assert.equal(r.requests[1].msg.voice,'edge-he-avri');
});

test('extension replaces audio and rejects late responses after new text',async()=>{
 const r=extension();r.send('read-from-start');
 r.paragraph.innerText='Replacement sentence.';r.send('read-from-start');
 r.requests[1].resolve();await r.settle();r.requests[0].resolve();await r.settle();
 assert.deepEqual(r.plays,['data:Replacement sentence.']);
 const old=r.audios.at(-1),ended=old.onended;r.send('stop');
 assert.equal(old.src,'');assert.equal(old.onended,null);
 ended();assert.equal(r.requests.length,2);
});

test('extension never substitutes Carmit or Hila when selected Avri is offline',async()=>{
 let listener;const calls=[];
 class Socket {
   static OPEN=1;static CONNECTING=0;
   constructor(url){if(url.startsWith('wss:'))queueMicrotask(()=>this.onerror?.(new Error('offline')));}
   close(){}send(){}
 }
 const context={WebSocket:Socket,console,TextEncoder,AbortSignal,crypto:require('node:crypto').webcrypto,
   Uint8Array,DataView,ArrayBuffer,btoa,queueMicrotask,setTimeout(){return 1;},clearTimeout(){},
   chrome:{commands:{onCommand:{addListener(){}}},runtime:{onMessage:{addListener(f){listener=f;}}}},
   fetch:async(url,options)=>{calls.push(JSON.parse(options.body));return{ok:true,arrayBuffer:async()=>Uint8Array.from([82,73,70,70,1,2,3]).buffer};}};
 vm.runInNewContext(fs.readFileSync('extension/background.js','utf8'),context);
 const response=await new Promise(resolve=>listener({action:'synthesize-edge-tts',text:'שלום עולם',voice:'edge-he-avri',rate:1},{},resolve));
 assert.equal(response.success,false);assert.equal(calls.length,0);
});


test('second-sentence speech boundaries highlight the matching word, not the paragraph start',async()=>{
 const r=extension({local:false,text:'First short sentence. Second target sentence.'});r.send('read-from-start');
 r.utterances[0].onend();
 const u=r.utterances.at(-1);u.onboundary({name:'word',charIndex:7,charLength:6});
 assert.equal(r.highlights.get('guy-reader-word')?.range.toString(),'target');
});

test('neural reading requests the next sentence while current audio is playing',async()=>{
 const r=extension();r.send('read-from-start');r.requests[0].resolve();await r.settle();
 assert.equal(r.requests.length,2);
 assert.equal(r.requests[1].msg.text,'שלום עולם.');
});

test('clicking a later word starts at that word and retains subsequent text',async()=>{
 const r=extension({local:false,clickOffset:29,text:'First short sentence. Second target sentence.'});
 r.events.click({target:r.paragraph,clientX:1,clientY:1});
 // The browser caret adapter will map this point into the second sentence.
 r.send('read-from-selection');
 assert.equal(r.utterances[0].text,'target sentence.');
});

test('neural pause and resume preserves the clicked word offset',async()=>{
 const r=extension({sync:false,local:true,clickOffset:29,text:'First short sentence. Second target sentence.'});
 r.events.click({target:r.paragraph,clientX:1,clientY:1});r.send('read-from-selection');
 r.requests[0].resolve();await r.settle();
 const audio=r.audios.at(-1);audio.duration=10;audio.currentTime=0;
 r.send('pause');r.send('resume');
 assert.equal(r.highlights.get('guy-reader-word')?.range.toString(),'target');
});


test('synchronized reading speaks consecutive sentences together and maps boundaries across them',()=>{
 const r=extension({sync:true,text:'First short sentence. Second target sentence.'});r.send('read-from-start');
 assert.equal(r.utterances[0]?.text,'First short sentence. Second target sentence.');
 r.utterances[0].onboundary({name:'word',charIndex:29,charLength:6});
 assert.equal(r.highlights.get('guy-reader-word')?.range.toString(),'target');
 assert.equal(r.requests.length,0);
});

test('selected Avri bypasses synchronized system voices and local Carmit routing',()=>{
 const r=extension({sync:true,local:true,voice:'edge-he-avri',text:'שלום עולם. זהו משפט נוסף.'});
 r.send('read-from-start');
 assert.equal(r.utterances.length,0);
 assert.equal(r.requests[0].msg.action,'synthesize-edge-tts');
 assert.equal(r.requests[0].msg.voice,'edge-he-avri');
});

test('X extraction ignores Article and Conversation tabs and reads the post body',()=>{
 const r=extension({x:true,sync:true,local:false});r.send('read-from-start');
 assert.equal(r.utterances[0].text,'Become so disgusted with where you are, you have no option but to win. Rockets use most of their mass as fuel during launch.');
});

test('X longform article extracts Draft.js longform-unstyled and heading blocks without truncation',()=>{
 const r=extension({xArticle:true,sync:true,local:false});r.send('read-from-start');
 assert.ok(r.utterances[0].text.includes('How to become disgustingly self-disciplined'));
 assert.ok(r.utterances[0].text.includes('Become so disgusted with where you are'));
 assert.ok(r.utterances[0].text.includes('The Launch Phase: fuel for escape velocity.'));
});

test('X extraction auto-expands tweet-text-show-more-link before extracting body',()=>{
 const r=extension({xTruncated:true,sync:true,local:false});r.send('read-from-start');
 assert.equal(r.getShowMoreClicked(),true);
 assert.ok(r.utterances[0].text.includes('The Launch Phase: fuel for escape velocity.'));
});

test('offline Edge Avri never falls back to Web Speech Carmit',async()=>{
 const r=extension({sync:false,local:false,voice:'edge-he-avri',failEdge:true,text:'שלום עולם'});
 r.send('read-from-start');
 await r.settle();
 assert.equal(r.alerts.length,0,'Must not alert or halt playback with an error modal');
 assert.equal(r.utterances.length, 0, 'Must never fall back to Web Speech Carmit for Hebrew');
});

test('selected Shaul (he-roboshaul) routes to local engine and never Carmit', async () => {
 const r = extension({sync: false, local: true, voice: 'he-roboshaul', text: 'שלום עולם. בדיקה.'});
 r.send('read-from-start');
 await r.settle();
 assert.equal(r.utterances.length, 0, 'Must never use Web Speech Carmit');
 assert.equal(r.requests[0].msg.action, 'synthesize-local');
 assert.equal(r.requests[0].msg.voice, 'he-roboshaul');
});

