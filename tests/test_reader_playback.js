// Execute the shipped UI through its public bridge and DOM events.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function reader(options = {}) {
  const elements = new Map(), requests = [], plays = [], revoked = [], messages = [];
  function element() {
    const el = {style: {}, value: '', textContent: '', children: [], listeners: {},
      classList: {add(){}, remove(){}, toggle(){}},
      addEventListener(name, fn) { this.listeners[name] = fn; },
      appendChild(child) { this.children.push(child); },
      querySelectorAll() { return this.children; }, querySelector(){return null;},
      scrollIntoView(){}, focus(){}, select(){},
      click() { this.listeners.click?.({target:this,stopPropagation(){}}); }};
    Object.defineProperty(el, 'innerHTML', {get(){return this.textContent;}, set(v){this.children=[];this.textContent=v;}});
    return el;
  }
  const document = {body:element(), createElement:element,
    getElementById(id) { if (!elements.has(id)) elements.set(id, element()); return elements.get(id); },
    querySelector(){return null;}};
  const audios = [];
  class Audio {
    constructor() {this.src='';this.paused=true; audios.push(this);}
    play() {this.paused=false;plays.push(this.src);this.onplay?.();return Promise.resolve();}
    pause() {this.paused=true;}
    load() {}
    removeAttribute(k) {if(k==='src')this.src='';}
  }
  const speechSynthesis = {cancel(){},getVoices(){return[];}};
  const window = {addEventListener(){},removeEventListener(){},speechSynthesis,
    webkit:{messageHandlers:{app:{postMessage(m){messages.push(m);}},speech:{postMessage(m){messages.push(m);}}}}};
  const storage = new Map(Object.entries(options.storage || {}));
  if (options.sync !== undefined) storage.set('guy_reader_sync', String(options.sync === true));
  const localStorage = {
    getItem(k) { return storage.has(k) ? storage.get(k) : null; },
    setItem(k, v) { storage.set(k, String(v)); }
  };
  const context = {window, document, Audio, console, AbortController, SpeechSynthesisUtterance: function(text){this.text=text;},
    localStorage, setTimeout(){}, clearTimeout(){},
    URL:{createObjectURL(blob){return 'blob:'+blob.text;},revokeObjectURL(url){revoked.push(url);}},
    fetch(url, options) {return new Promise(resolve => requests.push({body:JSON.parse(options.body),options,
      resolve(){resolve({ok:true,blob:async()=>({text:JSON.parse(options.body).text})});}}));}};
  vm.runInNewContext(fs.readFileSync('src/ui/app.js','utf8'), context);
  return {app:window.guyReaderApp, elements, requests, plays, revoked, messages, audios, storage,
    settle:()=>new Promise(resolve=>setImmediate(resolve))};
}

test('replacing text rejects a late synthesis response from the old passage', async()=>{
  const r=reader();
  r.app.receiveText('Old passage.');
  r.app.receiveText('New passage.');
  r.requests[1].resolve(); await r.settle();
  r.requests[0].resolve(); await r.settle();
  assert.deepEqual(r.plays,['blob:New passage.']);
});

test('replacing playing audio detaches completion and releases its URL', async()=>{
  const r=reader(); r.app.receiveText('Old passage. Another old sentence.');
  r.requests[0].resolve(); await r.settle();
  const old=r.audios.at(-1), lateEnd=old.onended;
  r.app.receiveText('New passage. New ending.');
  assert.equal(old.paused,true); assert.equal(old.src,''); assert.equal(old.onended,null);
  assert.ok(r.revoked.includes('blob:Old passage.'));
  const count=r.requests.length; lateEnd();
  assert.equal(r.requests.length,count);
  r.requests[1].resolve(); await r.settle(); // late old prebuffer
  r.requests[2].resolve(); await r.settle();
  r.audios.at(-1).onended(); await r.settle();
  assert.equal(r.requests.at(-1).body.text,'New ending.');
});

test('sentence click cancels pending audio and plays the clicked sentence', async()=>{
  const r=reader();r.app.receiveText('First sentence. Second sentence.');
  r.elements.get('sentencesList').children[1].click();
  r.requests[1].resolve(); await r.settle();
  r.requests[0].resolve(); await r.settle();
  assert.deepEqual(r.plays,['blob:Second sentence.']);
});

test('pause while loading stays paused; resume works inside native webview',async()=>{
  const r=reader();r.app.receiveText('First sentence.');
  r.elements.get('btnPlayPause').click();
  r.requests[0].resolve(); await r.settle();
  assert.deepEqual(r.plays,[]);
  r.elements.get('btnPlayPause').click(); await r.settle();
  assert.deepEqual(r.plays,['blob:First sentence.']);
});

test('mixed passage routes each sentence to its language voice',async()=>{
  const r=reader();r.app.receiveText('English sentence. שלום עולם.');
  assert.equal(r.requests[0].body.voice,'af_sarah');
  r.requests[0].resolve();await r.settle();
  assert.equal(r.requests[1].body.voice,'edge-he-avri');
});

test('voice preview replaces speech and cannot advance the passage',async()=>{
  const r=reader();r.app.receiveText('Old passage. More text.');
  r.elements.get('settingsVoiceHe').value='edge-he-hila';
  r.elements.get('btnTestVoiceHe').click();
  r.requests[1].resolve(); await r.settle();
  r.requests[0].resolve(); await r.settle();
  assert.equal(r.plays.length,1);assert.match(r.plays[0],/שלום/);
  r.audios.at(-1).onended();
  assert.equal(r.requests.length,2);
  assert.equal(r.elements.get('previewStatus').textContent,'Ready');
});

test('changing voice rejects old buffers and requests the new voice',async()=>{
  const r=reader();r.app.receiveText('First sentence. Second sentence.');
  r.requests[0].resolve(); await r.settle();
  const select=r.elements.get('voiceSelect');select.value='am_adam';
  select.listeners.change({target:select});
  assert.equal(r.requests.at(-1).body.voice,'am_adam');
  r.requests[1].resolve(); await r.settle();
  r.requests[2].resolve(); await r.settle();
  assert.equal(r.plays.length,2);
  assert.equal(r.requests.at(-1).body.voice,'am_adam');
});

test('Hebrew local audio highlights its sentence on playback start',async()=>{
 const r=reader();r.app.receiveText('שלום עולם.');
 let active=false;
 r.elements.get('sentencesList').children[0].classList.add=(name)=>{if(name==='active')active=true;};
 r.requests[0].resolve();await r.settle();
 assert.equal(active,true);
});

test('paused audio failure does not start native fallback speech',async()=>{
 const r=reader();r.app.receiveText('שלום עולם.');r.requests[0].resolve();await r.settle();
 r.elements.get('btnPlayPause').click();
 const count=r.messages.length;r.audios.at(-1).onerror();
 assert.equal(r.messages.slice(count).some(m=>m.action==='speak'),false);
});

test('preview completes after a decoder error falls back to native speech',async()=>{
 const r=reader();r.elements.get('settingsVoiceHe').value='edge-he-hila';r.elements.get('btnTestVoiceHe').click();
 r.requests[0].resolve();await r.settle();r.audios.at(-1).onerror();
 const speech=r.messages.findLast(m=>m.action==='speakEdge'||m.action==='speak');assert.equal(speech.voice,'edge-he-hila');
 r.app.onSentenceComplete(speech.requestId);
 assert.equal(r.elements.get('previewStatus').textContent,'Ready');
});


test('synchronized desktop reading sends connected text and follows native word ranges',()=>{
 const r=reader({sync:true});r.app.receiveText('First sentence. Second target sentence.');
 const speech=r.messages.findLast(m=>m.action==='speak');
 assert.equal(speech?.text,'First sentence. Second target sentence.');
 r.app.onWordBoundary(speech.requestId,23,6);
 assert.match(r.elements.get('sentencesList').children[1].innerHTML,/<mark[^>]*>target<\/mark>/);
 r.elements.get('btnPlayPause').click();r.elements.get('btnPlayPause').click();
 assert.equal(r.messages.at(-1).action,'resume');
});

test('desktop word highlight moves cleanly and Stop removes the mark',()=>{
 const r=reader({sync:true});r.app.receiveText('First word. Second target word.');
 const speech=r.messages.findLast(m=>m.action==='speak');
 r.app.onWordBoundary(speech.requestId,0,5);
 r.app.onWordBoundary(speech.requestId,19,6);
 const items=r.elements.get('sentencesList').children;
 assert.doesNotMatch(items[0].innerHTML,/<mark/);
 assert.match(items[1].innerHTML,/<mark[^>]*>target<\/mark>/);
 r.elements.get('btnStop').click();
 assert.doesNotMatch(items[1].innerHTML,/<mark/);
});

test('desktop voice switching: changing to Adam synthesizes with Adam and never Evan', async () => {
  const r = reader();
  r.app.receiveText('Testing voice switching to Adam.');
  assert.equal(r.requests[0].body.voice, 'af_sarah');
  r.requests[0].resolve(); await r.settle();

  // Switch voice to am_adam
  const select = r.elements.get('voiceSelect');
  select.value = 'am_adam';
  select.listeners.change({ target: select });
  await r.settle();

  assert.equal(r.requests.at(-1).body.voice, 'am_adam');
  assert.equal(r.storage.get('guy_reader_voice_en'), 'am_adam');
  assert.equal(r.storage.get('guy_reader_voice'), 'am_adam');
  const evanCalls = r.messages.filter(m => m.action === 'speak' && m.voice === 'apple-evan');
  assert.equal(evanCalls.length, 0);
});

test('Hebrew playback never calls Carmit even if synthesis audio fails', async () => {
  const r = reader();
  r.app.receiveText('שלום עולם.');
  assert.equal(r.requests[0].body.voice, 'edge-he-avri');
  r.requests[0].resolve(); await r.settle();

  // Simulate audio failure
  r.audios.at(-1).onerror();
  await r.settle();

  // Must fall back to native Edge TTS, never Carmit!
  const carmitCalls = r.messages.filter(m => m.voice === 'apple-carmit');
  assert.equal(carmitCalls.length, 0);
  const edgeFallback = r.messages.findLast(m => m.action === 'speakEdge' || m.action === 'edgeTTS');
  assert.ok(edgeFallback, 'Fell back to native speakEdge');
  assert.equal(edgeFallback.voice, 'edge-he-avri');
});

test('Hebrew voice selection persists to guy_reader_voice_he in localStorage', async () => {
  const r = reader();
  r.app.receiveText('שלום עולם.');
  const select = r.elements.get('voiceSelect');
  select.value = 'edge-he-hila';
  select.listeners.change({ target: select });
  await r.settle();

  assert.equal(r.storage.get('guy_reader_voice_he'), 'edge-he-hila');
  assert.equal(r.storage.get('guy_reader_voice'), 'edge-he-hila');
});

test('selecting Shaul (he-roboshaul) synthesizes with he-roboshaul and persists to guy_reader_voice_he', async () => {
  const r = reader();
  r.app.receiveText('שלום עולם.');
  const select = r.elements.get('voiceSelect');
  select.value = 'he-roboshaul';
  select.listeners.change({ target: select });
  await r.settle();

  assert.equal(r.requests.at(-1).body.voice, 'he-roboshaul');
  assert.equal(r.storage.get('guy_reader_voice_he'), 'he-roboshaul');
  assert.equal(r.storage.get('guy_reader_voice'), 'he-roboshaul');
});
