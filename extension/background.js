// Guy_reader - Background Service Worker (Manifest V3)

const EDGE_TRUSTED_TOKEN = "6A5AA1D4EAFF4E9FB37E23D68491D6F4";
const EDGE_SEC_MS_GEC_VERSION = "2-143.0.3650.75";

const SHA256_INITIAL = [
  0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
  0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19
];
const SHA256_STATE = [
  0xFD9FBEA2, 0x91243CE7, 0xBE499094, 0xCD2E1E0A,
  0x6C006F49, 0x04BD35AB, 0xFEB0A7E4, 0x03EFFBD2
];
const SHA256_SCHEDULE = [
  0xEB24BF9E, 0x1558691F, 0xA0C09EE2, 0x0CFA32BA,
  0xA622EE8C, 0xD1DD9491, 0xC0DD25A0, 0xF9E70AB6,
  0xF0C31573, 0x7058CE4E, 0x7188E606, 0x00E5AB33,
  0xD258B060, 0x72766564
];
const SHA256_ROUND_CONSTANTS = [
  0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
  0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
  0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
  0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
  0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
  0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
  0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
  0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2
];
const SHA256_ADJUSTMENT = 0xC9DC06A7;
const SHA256_SIGMA0_ADJUSTMENT = 0x059C0B80;
const SHA256_SIGMA1_ADJUSTMENT = 0x000B92C0;

const CS64_COEFFICIENTS = [
  [0xE82E91B1, 0xB32700D0], [0x44DE24C6, 0x88DFF51D],
  [0x3BEB65BC, 0x29514038], [0xC89C5933, 0xB328CBDF],
  [0x8D1EC211, 0xD405B4D5], [0x314EF5D5, 0x26E55F3C],
  [0xE92491B1, 0x607801C6], [0xF0A5B9D5, 0x82B2C1FB],
  [0x06064CF3, 0xFA51A3DA], [0xDA79FA60, 0x207CC464],
  [0xBED20560, 0x3C3C74F3], [0x89F9C9F8, 0xD2D14B61],
  [0x35FA38C6, 0xBB04A2C1], [0xCB49E3C6, 0xC5626167]
];
const CS64_FACTOR = 0x82893933;
const CS64_ADJUSTMENT0 = 0xF2F90B1A;
const CS64_ADJUSTMENT1 = 0x0B1A0000;

function u32(v) { return v >>> 0; }
function mul32(a, b) { return Math.imul(a, b) >>> 0; }
function rol16(v) { v = v >>> 0; return ((v << 16) | (v >>> 16)) >>> 0; }
function rotr(v, n) { v = v >>> 0; return ((v >>> n) | (v << (32 - n))) >>> 0; }
function sigma0(v) { v = v >>> 0; return (rotr(v, 7) ^ rotr(v, 18) ^ (v >>> 3)) >>> 0; }
function sigma1(v) { v = v >>> 0; return (rotr(v, 17) ^ rotr(v, 19) ^ (v >>> 10)) >>> 0; }

function expandSha256Schedule(words, firstWord = 16) {
  for (let i = firstWord; i < 64; i++) {
    const s1 = sigma1(words[i - 2]);
    const s0 = sigma0(words[i - 15]);
    words[i] = (s1 + words[i - 7] + s0 + words[i - 16]) >>> 0;
  }
}

function sha256Rounds(state, words, firstRound = 0) {
  let [a, b, c, d, e, f, g, h] = state;
  for (let i = firstRound; i < 64; i++) {
    const k = (firstRound === 14 && i === 14) ? SHA256_ADJUSTMENT : SHA256_ROUND_CONSTANTS[i];
    const S1 = (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) >>> 0;
    const ch = (g ^ (e & (f ^ g))) >>> 0;
    const t1 = (h + S1 + ch + k + words[i]) >>> 0;
    const S0 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) >>> 0;
    const maj = ((a & b) | (c & (a | b))) >>> 0;
    const t2 = (S0 + maj) >>> 0;
    h = g; g = f; f = e; e = (d + t1) >>> 0;
    d = c; c = b; b = a; a = (t1 + t2) >>> 0;
  }
  return [a, b, c, d, e, f, g, h];
}

function sha256Init(data7) {
  const words = new Array(64).fill(0);
  words[14] = ((data7[0] << 16) | (data7[1] << 8) | data7[2]) >>> 0;
  words[15] = ((data7[3] << 24) | (data7[4] << 16) | (data7[5] << 8) | data7[6]) >>> 0;
  for (let i = 16; i < 30; i++) {
    let val = SHA256_SCHEDULE[i - 16];
    if (i - 2 >= 14) {
      val = (val + (i === 16 ? ((sigma1(words[i - 2]) ^ SHA256_SIGMA1_ADJUSTMENT) >>> 0) : sigma1(words[i - 2]))) >>> 0;
    }
    if (i - 7 >= 14) {
      val = (val + words[i - 7]) >>> 0;
    }
    if (i - 15 >= 14) {
      val = (val + (i === 29 ? ((sigma0(words[i - 15]) ^ SHA256_SIGMA0_ADJUSTMENT) >>> 0) : sigma0(words[i - 15]))) >>> 0;
    }
    words[i] = val >>> 0;
  }
  words[30] = (sigma1(words[28]) + words[23] + sigma0(words[15]) + words[14] + SHA256_ADJUSTMENT - SHA256_ROUND_CONSTANTS[14]) >>> 0;
  expandSha256Schedule(words, 31);
  const working = sha256Rounds(SHA256_STATE, words, 14);
  return SHA256_INITIAL.map((x, idx) => (x + working[idx]) >>> 0);
}

function sha256Digest(data) {
  const length = 57 + data.length;
  const rem = data.slice(7);
  const padZeroLen = ((55 - length) % 64 + 64) % 64;
  const padded = new Uint8Array(rem.length + 1 + padZeroLen + 8);
  padded.set(rem, 0);
  padded[rem.length] = 0x80;
  const bitLen = BigInt(length) * 8n;
  const dv = new DataView(padded.buffer);
  dv.setBigUint64(padded.length - 8, bitLen, false);

  let state = sha256Init(data.slice(0, 7));
  for (let offset = 0; offset < padded.length; offset += 64) {
    const words = new Array(64).fill(0);
    for (let j = 0; j < 16; j++) {
      words[j] = dv.getUint32(offset + j * 4, false);
    }
    expandSha256Schedule(words, 16);
    const working = sha256Rounds(state, words, 0);
    state = state.map((x, idx) => (x + working[idx]) >>> 0);
  }
  const out = new Uint8Array(32);
  const outDv = new DataView(out.buffer);
  for (let i = 0; i < 8; i++) outDv.setUint32(i * 4, state[i], false);
  return out;
}

function wordsLe4Even(data) {
  const padLen = (4 - (data.length % 4)) % 4;
  const padded = new Uint8Array(data.length + padLen);
  padded.set(data, 0);
  if (padded.length === 0) return [];
  const dv = new DataView(padded.buffer);
  const words = [];
  for (let i = 0; i < padded.length; i += 4) {
    words.push(dv.getUint32(i, true));
  }
  if (words.length % 2 === 1) words.push(0);
  return words;
}

function cs64Digest(data, digest) {
  const digDv = new DataView(digest.buffer, digest.byteOffset, digest.byteLength);
  const keyA = (digDv.getUint32(0, true) | 1) >>> 0;
  const keyB = (digDv.getUint32(4, true) | 1) >>> 0;
  const factors = [mul32(keyA, CS64_FACTOR), mul32(keyB, CS64_FACTOR)];
  const terms = CS64_COEFFICIENTS.map(([coeff], idx) => mul32(coeff, factors[idx % 2]));
  const offsets = CS64_COEFFICIENTS.map(([, off]) => off >>> 0);

  const prefixed = new Uint8Array(1 + data.length);
  prefixed.set(data, 1);
  const dataWords = wordsLe4Even(prefixed);
  for (let idx = 0; idx < dataWords.length; idx++) {
    const word = dataWords[idx];
    let term = mul32(word, idx % 2 === 0 ? keyA : keyB);
    let offset = mul32(rol16(word), idx % 2 === 0 ? 0xEF0569FB : 0xC31713DB);
    if (idx === 0) {
      term = (term + mul32(CS64_ADJUSTMENT0, factors[0])) >>> 0;
      offset = (offset + CS64_ADJUSTMENT1) >>> 0;
    }
    terms.push(term >>> 0);
    offsets.push(offset >>> 0);
  }

  let swapAcc = 0, swapLast = 0, state = 0, acc = 0;
  for (let idx = 0; idx < terms.length; idx += 2) {
    const x = terms[idx], y = terms[idx + 1];
    let t = rol16((offsets[idx] + x) >>> 0);
    let q = mul32(t, 0x76F50F34);
    swapAcc = (swapAcc + ((mul32(rol16(q), 0xC3EFEA97) + q) >>> 0)) >>> 0;
    t = rol16((offsets[idx + 1] + y) >>> 0);
    q = mul32(t, 0x1881CE3C);
    swapLast = (mul32(rol16(q), 0x35BD1EC9) + q) >>> 0;
    swapAcc = (swapAcc + swapLast) >>> 0;

    state = (mul32(state, keyA) + x) >>> 0;
    state = mul32(rol16(state), 0xCF98B111);
    state = mul32(rol16(state), 0x87085B9F);
    state = mul32(rol16(state), 0x12CEB96D);
    state = mul32(rol16(state), 0x257E1D83);
    acc = (acc + state) >>> 0;
    t = (mul32(state, keyB) + y) >>> 0;
    t = mul32(rol16(t), 0xA27416F5);
    t = mul32(rol16(t), 0xD38396FF);
    state = mul32(rol16(mul32(rol16(t), 0x7C932B89)), 0xBFA49F69);
    acc = (acc + state) >>> 0;
  }
  const w0 = (swapLast ^ state) >>> 0;
  const w1 = (swapAcc ^ acc) >>> 0;
  const csBytes = new Uint8Array(8);
  const csDv = new DataView(csBytes.buffer);
  csDv.setUint32(0, w0, true);
  csDv.setUint32(4, w1, true);
  return Array.from(csBytes).map(b => b.toString(16).padStart(2, '0')).join('').toUpperCase();
}

// Generate Sec-MS-GEC v2 Token
async function generateSecMsGec(unixTimestampSec = null) {
  const WINDOWS_TICKS_EPOCH = 116444736000000000n;
  const nowSec = unixTimestampSec !== null ? BigInt(Math.floor(unixTimestampSec)) : BigInt(Math.floor(Date.now() / 1000));
  let ticks = nowSec * 10000000n + WINDOWS_TICKS_EPOCH;
  ticks -= ticks % 3000000000n; // Round down to 5-minute boundary

  const strToHash = ticks.toString() + EDGE_TRUSTED_TOKEN;
  const encoder = new TextEncoder();
  const data = encoder.encode(strToHash);
  const digest = sha256Digest(data);
  const cs64Hex = cs64Digest(data, digest);
  const shaHex = Array.from(digest).map(b => b.toString(16).padStart(2, '0')).join('').toUpperCase();
  return `${cs64Hex}-${shaHex}`;
}

function prepareTextForTTS(text) {
  let s = (text || '').trim();
  if (!s) return s;
  s = s.replace(/\s+[-\u2013\u2014]\s+/g, ', ');
  s = s.replace(/^[•▪▸►✦★·*]+\s*/g, '').replace(/\s*[•▪▸►✦★·*]+$/g, '').trim();
  if (s && !/[.!?…:;,"'\u05F4)\]\}]$/u.test(s)) {
    s += '.';
  }
  return s;
}

// Synthesize speech using Microsoft Edge Neural TTS WebSocket
async function synthesizeEdgeTTS(text, voiceName = 'edge-he-avri', rate = 1.0) {
  const isHebrew = /[\u0590-\u05FF]/.test(text);
  let voiceFullName = 'he-IL-AvriNeural';
  if (voiceName.includes('hila')) {
    voiceFullName = isHebrew ? 'he-IL-HilaNeural' : 'en-US-JennyNeural';
  } else if (voiceName.includes('jenny')) {
    voiceFullName = isHebrew ? 'he-IL-AvriNeural' : 'en-US-JennyNeural';
  } else if (voiceName.includes('guy')) {
    voiceFullName = isHebrew ? 'he-IL-AvriNeural' : 'en-US-GuyNeural';
  } else if (voiceName.includes('avri')) {
    voiceFullName = isHebrew ? 'he-IL-AvriNeural' : 'en-US-GuyNeural';
  } else if (!isHebrew) {
    voiceFullName = 'en-US-JennyNeural';
  }

  const percent = Math.round((rate - 1.0) * 100);
  const rateStr = percent >= 0 ? `+${percent}%` : `${percent}%`;
  const langCode = voiceFullName.substring(0, 5);

  const ssml = `<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='${langCode}'>` +
               `<voice name='${voiceFullName}'>` +
               `<prosody rate='${rateStr}'>${escapeXml(prepareTextForTTS(text))}</prosody>` +
               `</voice></speak>`;

  const connId = crypto.randomUUID().replace(/-/g, '');
  const gec = await generateSecMsGec();
  const wsUrl = `wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=${EDGE_TRUSTED_TOKEN}&ConnectionId=${connId}&Sec-MS-GEC=${gec}&Sec-MS-GEC-Version=${EDGE_SEC_MS_GEC_VERSION}`;

  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    const audioChunks = [];
    let isFinished = false;

    const timeout = setTimeout(() => {
      if (!isFinished) {
        isFinished = true;
        try { ws.close(); } catch (e) {}
        if (audioChunks.length > 0) {
          resolve(chunksToBase64DataUrl(audioChunks));
        } else {
          reject(new Error("Edge TTS timeout"));
        }
      }
    }, 9000);

    ws.binaryType = 'arraybuffer';

    ws.onopen = () => {
      const ts = (new Date()).toString();
      const configMsg = `X-Timestamp:${ts}\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n` +
                        JSON.stringify({
                          context: {
                            synthesis: {
                              audio: {
                                metadataoptions: { sentenceBoundaryEnabled: "false", wordBoundaryEnabled: "false" },
                                outputFormat: "audio-24khz-48kbitrate-mono-mp3"
                              }
                            }
                          }
                        });
      ws.send(configMsg);

      const reqId = crypto.randomUUID().replace(/-/g, '');
      const ssmlMsg = `X-RequestId:${reqId}\r\nContent-Type:application/ssml+xml\r\nX-Timestamp:${ts}Z\r\nPath:ssml\r\n\r\n${ssml}`;
      ws.send(ssmlMsg);
    };

    ws.onmessage = (event) => {
      if (typeof event.data === 'string') {
        if (event.data.includes('Path:turn.end')) {
          if (!isFinished) {
            isFinished = true;
            clearTimeout(timeout);
            try { ws.close(); } catch (e) {}
            if (audioChunks.length > 0) {
              resolve(chunksToBase64DataUrl(audioChunks));
            } else {
              reject(new Error("No audio returned"));
            }
          }
        }
      } else if (event.data instanceof ArrayBuffer) {
        const view = new DataView(event.data);
        if (event.data.byteLength > 2) {
          const headerLen = view.getUint16(0);
          if (event.data.byteLength > 2 + headerLen) {
            const chunk = event.data.slice(2 + headerLen);
            audioChunks.push(new Uint8Array(chunk));
          }
        }
      }
    };

    ws.onerror = (err) => {
      if (!isFinished) {
        isFinished = true;
        clearTimeout(timeout);
        try { ws.close(); } catch (_) {}
        if (audioChunks.length > 0) {
          resolve(chunksToBase64DataUrl(audioChunks));
        } else {
          reject(err);
        }
      }
    };

    ws.onclose = () => {
      if (!isFinished) {
        isFinished = true;
        clearTimeout(timeout);
        if (audioChunks.length > 0) {
          resolve(chunksToBase64DataUrl(audioChunks));
        } else {
          reject(new Error("WebSocket closed prematurely"));
        }
      }
    };
  });
}

function uint8ArrayToBase64(bytes) {
  let binary = '';
  const len = bytes.byteLength;
  const chunkSize = 8192;
  for (let i = 0; i < len; i += chunkSize) {
    const chunk = bytes.subarray(i, Math.min(i + chunkSize, len));
    binary += String.fromCharCode.apply(null, chunk);
  }
  return btoa(binary);
}

function chunksToBase64DataUrl(chunks) {
  let totalLen = 0;
  for (const c of chunks) totalLen += c.byteLength;
  const merged = new Uint8Array(totalLen);
  let offset = 0;
  for (const c of chunks) {
    merged.set(c, offset);
    offset += c.byteLength;
  }
  return `data:audio/mp3;base64,${uint8ArrayToBase64(merged)}`;
}

function escapeXml(unsafe) {
  return unsafe.replace(/[<>&'"]/g, (c) => {
    switch (c) {
      case '<': return '&lt;';
      case '>': return '&gt;';
      case '&': return '&amp;';
      case '\'': return '&apos;';
      case '"': return '&quot;';
      default: return c;
    }
  });
}

// Keyboard shortcuts dispatcher
chrome.commands.onCommand.addListener(async (command) => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab || !tab.id) return;

  if (command === 'read-article') {
    chrome.tabs.sendMessage(tab.id, { action: 'toggle-read' }).catch(() => {});
  } else if (command === 'toggle-reader') {
    chrome.tabs.sendMessage(tab.id, { action: 'toggle-pill' }).catch(() => {});
  }
});

async function synthesizeLocal(text, voice, speed = 1.0) {
    return fetch('http://127.0.0.1:5050/synthesize', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        text: text,
        voice: voice,
        speed: speed
      }),
      signal: AbortSignal.timeout(10000)
    })
      .then(async (resp) => {
        if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
        const buffer = await resp.arrayBuffer();
        const bytes = new Uint8Array(buffer);
        const mimeType = (bytes[0] === 0x52 && bytes[1] === 0x49) ? 'audio/wav' : 'audio/mp3';
        const dataUrl = `data:${mimeType};base64,${uint8ArrayToBase64(bytes)}`;
        return dataUrl;
      });
}

let readingTabId = null;

// Message listener from content script or popup
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === 'reader-focus' || message.action === 'reader-state') {
    if (message.action === 'reader-state' && sender.tab?.id !== readingTabId) {
      sendResponse({success:false}); return false;
    }
    if (bridgeSocket?.readyState === WebSocket.OPEN) bridgeSocket.send(JSON.stringify({
      ...message, action: message.action === 'reader-focus' ? 'focus' : 'reader-state'
    }));
    sendResponse({success:true}); return false;
  }
  if (message.action === 'check-engine-health') {
    fetch('http://127.0.0.1:5050/health', { signal: AbortSignal.timeout(2000) })
      .then(r => r.json())
      .then(data => sendResponse({ success: true, available: data.status === 'ok', data }))
      .catch(err => sendResponse({ success: false, available: false, error: err.message }));
    return true; // Keep channel open for async response
  }

  if (message.action === 'synthesize-local') {
    synthesizeLocal(message.text, message.voice, message.speed || 1.0)
      .then(audioDataUrl => sendResponse({ success: true, audioDataUrl }))
      .catch(err => sendResponse({ success: false, error: err.message || 'Synthesis failed' }));
    return true; // Keep channel open for async response
  }

  if (message.action === 'synthesize-edge-tts') {
    synthesizeEdgeTTS(message.text, message.voice, message.rate)
      .then((dataUrl) => {
        sendResponse({ success: true, audioDataUrl: dataUrl });
      })
      .catch((err) => {
        sendResponse({ success: false, error: err.message || 'TTS synthesis failed' });
      });
    return true; // Keep channel open for async response
  }

  if (message.action === 'synthesize-elevenlabs') {
    synthesizeElevenLabs(message.text, message.voice, message.key)
      .then((dataUrl) => {
        sendResponse({ success: true, audioDataUrl: dataUrl });
      })
      .catch((err) => {
        sendResponse({ success: false, error: err.message || 'ElevenLabs synthesis failed' });
      });
    return true; // Keep channel open for async response
  }
});

const ELEVEN_VOICE_IDS = {
  'eleven-rachel': '21m00Tcm4TlvDq8ikWAM',
  'eleven-adam': 'pNInz6obpgDQGcFmaJgB',
  'eleven-charlie': 'IKne3meq5aSn9XLyUdCD'
};

async function synthesizeElevenLabs(text, voiceChoice, apiKey) {
  if (!apiKey) throw new Error('ElevenLabs API key is missing');
  const voiceId = ELEVEN_VOICE_IDS[voiceChoice] || voiceChoice || '21m00Tcm4TlvDq8ikWAM';
  const resp = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'xi-api-key': apiKey
    },
    body: JSON.stringify({
      text: text,
      model_id: 'eleven_multilingual_v2',
      voice_settings: {
        stability: 0.5,
        similarity_boost: 0.8
      }
    }),
    signal: AbortSignal.timeout(12000)
  });
  if (!resp.ok) {
    const errText = await resp.text().catch(() => '');
    throw new Error(`ElevenLabs error (HTTP ${resp.status}): ${errText}`);
  }
  const buffer = await resp.arrayBuffer();
  const bytes = new Uint8Array(buffer);
  return `data:audio/mp3;base64,${uint8ArrayToBase64(bytes)}`;
}

// Bridge to Local Desktop Companion Server (Port 5050)
let bridgeSocket = null;
let reconnectTimer = null;

function connectBridgeWebSocket() {
  if (bridgeSocket && (bridgeSocket.readyState === WebSocket.OPEN || bridgeSocket.readyState === WebSocket.CONNECTING)) {
    return;
  }

  try {
    bridgeSocket = new WebSocket('ws://127.0.0.1:5050/ws');

    bridgeSocket.onopen = () => {
      console.log('[GuyReader Extension] Connected to desktop speech engine bridge on 5050');
      bridgeSocket.send(JSON.stringify({ action: 'register', client: 'chrome-extension' }));
    };

    bridgeSocket.onmessage = async (event) => {
      try {
        const data = JSON.parse(event.data);
        if (data.event === 'command') {
          const expired = () => Number.isFinite(data.expiresAt) && Date.now() > data.expiresAt;
          if (expired()) {
            bridgeSocket?.send(JSON.stringify({action:'command-result',requestId:data.requestId,success:false}));
            return;
          }
          const [activeTab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
          const transport = ['pause','resume','stop'].includes(data.action);
          const tabId = transport ? (readingTabId || activeTab?.id) : activeTab?.id;
          let response = null;
          if (tabId) {
            if (!transport && readingTabId && readingTabId !== tabId) {
              try { await chrome.tabs.sendMessage(readingTabId, {action:'stop'}); } catch (_) {}
              readingTabId = null;
            }
            if (!transport) readingTabId = tabId;
            const tabMsg = {action:data.action || 'read-from-selection', voice:data.voice, expiresAt:data.expiresAt};
            try {
              if (!expired()) response = await chrome.tabs.sendMessage(tabId, tabMsg);
            } catch (_) {
              if (!transport && !expired()) {
                try {
                  await chrome.scripting.insertCSS({target:{tabId},files:['content.css']});
                  await chrome.scripting.executeScript({target:{tabId},files:['content.js']});
                  if (!expired()) response = await chrome.tabs.sendMessage(tabId, tabMsg);
                } catch (_) { /* Restricted/internal pages fall back to the desktop reader. */ }
              }
            }
          }
          if ((!response?.success || expired()) && !transport && readingTabId === tabId) readingTabId = null;
          if (response?.success && data.action === 'stop') readingTabId = null;
          if (bridgeSocket?.readyState === WebSocket.OPEN) bridgeSocket.send(JSON.stringify({
            action:'command-result', requestId:data.requestId, success:response?.success === true && !expired()
          }));
        }
      } catch (err) {
        console.warn('[GuyReader Extension] Bridge message error:', err);
      }
    };

    bridgeSocket.onclose = () => {
      bridgeSocket = null;
      scheduleReconnect();
    };

    bridgeSocket.onerror = () => {
      try { bridgeSocket.close(); } catch (e) {}
      bridgeSocket = null;
      scheduleReconnect();
    };
  } catch (e) {
    scheduleReconnect();
  }
}

function scheduleReconnect() {
  if (reconnectTimer) clearTimeout(reconnectTimer);
  reconnectTimer = setTimeout(connectBridgeWebSocket, 3500);
}

// Start bridge connection
connectBridgeWebSocket();
