// Guy_reader - Background Service Worker (Manifest V3)

const EDGE_TRUSTED_TOKEN = "6A5AA1D4EAFF4E9FB37E23D68491D6F4";
const EDGE_SEC_MS_GEC_VERSION = "1-143.0.3650.75";

// Generate Sec-MS-GEC Token using Web Crypto SHA-256
async function generateSecMsGec() {
  const WINDOWS_TICKS_EPOCH = 116444736000000000n;
  const nowMs = BigInt(Date.now());
  let ticks = nowMs * 10000n + WINDOWS_TICKS_EPOCH;
  ticks -= ticks % 3000000000n; // Round down to 5-minute boundary

  const strToHash = ticks.toString() + EDGE_TRUSTED_TOKEN;
  const encoder = new TextEncoder();
  const data = encoder.encode(strToHash);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('').toUpperCase();
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
               `<prosody rate='${rateStr}'>${escapeXml(text)}</prosody>` +
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

function chunksToBase64DataUrl(chunks) {
  let totalLen = 0;
  for (const c of chunks) totalLen += c.byteLength;
  const merged = new Uint8Array(totalLen);
  let offset = 0;
  for (const c of chunks) {
    merged.set(c, offset);
    offset += c.byteLength;
  }

  let binary = '';
  const len = merged.byteLength;
  for (let i = 0; i < len; i++) {
    binary += String.fromCharCode(merged[i]);
  }
  return `data:audio/mp3;base64,${btoa(binary)}`;
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
        let binary = '';
        for (let i = 0; i < bytes.byteLength; i++) {
          binary += String.fromCharCode(bytes[i]);
        }
        const mimeType = (bytes[0] === 0x52 && bytes[1] === 0x49) ? 'audio/wav' : 'audio/mp3';
        const dataUrl = `data:${mimeType};base64,${btoa(binary)}`;
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
});

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
