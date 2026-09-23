#!/usr/bin/env python3
"""
Pocket TTS - Visual PDF Reader with Dynamic Word-by-Word Follow-Along Highlighter & Speed Controls.
Preserves authentic PDF page formatting, columns, images, and fonts with PDF.js while streaming Pocket TTS.
"""

import argparse
import io
import json
import os
import urllib.parse
import wave
from http.server import HTTPServer, SimpleHTTPRequestHandler

import numpy as np

try:
    from pocket_tts_onnx import PocketTTS
except ImportError:
    print("pocket-tts-onnx not found! Please run:")
    print("  pip install pocket-tts-onnx")
    import sys
    sys.exit(1)

HTML_PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Pocket TTS - Visual PDF Reader</title>

<!-- PDF.js library & official TextLayer stylesheet -->
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf_viewer.min.css">
<script src="https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js"></script>

<style>
  :root {
    --bg-main: #0b0f19;
    --bg-header: #111827;
    --bg-panel: #1f2937;
    --text-primary: #f9fafb;
    --text-muted: #9ca3af;
    --accent: #38bdf8;
    --accent-hover: #0284c7;
    --border-color: #374151;
  }

  * { box-sizing: border-box; margin: 0; padding: 0; }

  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    background: var(--bg-main);
    color: var(--text-primary);
    display: flex;
    flex-direction: column;
    height: 100vh;
    overflow: hidden;
  }

  /* Ultra-Compact Top Toolbar (Maximizes Screen Space) */
  header {
    background: var(--bg-header);
    border-bottom: 1px solid var(--border-color);
    padding: 0.35rem 0.85rem;
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 0.5rem;
    z-index: 100;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.35);
  }

  .brand {
    display: flex;
    align-items: center;
    gap: 0.4rem;
    font-weight: 700;
    font-size: 0.95rem;
    color: var(--accent);
    user-select: none;
  }

  .controls-group {
    display: flex;
    align-items: center;
    gap: 0.45rem;
    flex-wrap: wrap;
  }

  button, select, input[type="file"] {
    background: #374151;
    color: var(--text-primary);
    border: 1px solid #4b5563;
    padding: 0.25rem 0.55rem;
    border-radius: 5px;
    font-size: 0.78rem;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.15s ease;
    display: inline-flex;
    align-items: center;
    gap: 0.3rem;
  }

  button:hover { background: #4b5563; }
  button.primary {
    background: #0284c7;
    border-color: #0284c7;
    color: #fff;
    font-weight: 600;
  }
  button.primary:hover { background: #0369a1; }
  button.danger { background: #dc2626; border-color: #dc2626; }
  button.danger:hover { background: #b91c1c; }

  /* Speed Slider Section (Compact) */
  .speed-control {
    display: flex;
    align-items: center;
    gap: 0.4rem;
    background: #1f2937;
    padding: 0.2rem 0.5rem;
    border-radius: 6px;
    border: 1px solid var(--border-color);
  }

  .speed-control label {
    font-size: 0.72rem;
    color: var(--text-muted);
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .speed-slider {
    -webkit-appearance: none;
    appearance: none;
    width: 70px;
    height: 4px;
    background: #4b5563;
    border-radius: 3px;
    outline: none;
    cursor: pointer;
  }

  .speed-slider::-webkit-slider-thumb {
    -webkit-appearance: none;
    appearance: none;
    width: 12px;
    height: 12px;
    border-radius: 50%;
    background: var(--accent);
    cursor: pointer;
    box-shadow: 0 0 4px rgba(56, 189, 248, 0.8);
    transition: transform 0.1s;
  }

  .speed-slider::-webkit-slider-thumb:hover {
    transform: scale(1.2);
  }

  .speed-badge {
    font-size: 0.78rem;
    font-weight: 700;
    color: #38bdf8;
    min-width: 32px;
    text-align: right;
    font-variant-numeric: tabular-nums;
  }

  .speed-presets {
    display: flex;
    gap: 0.15rem;
  }

  .preset-btn {
    padding: 0.12rem 0.35rem;
    font-size: 0.7rem;
    background: #374151;
    border: 1px solid #4b5563;
    border-radius: 3px;
  }
  .preset-btn.active {
    background: #0284c7;
    border-color: #38bdf8;
    color: #fff;
  }

  /* Auto-Follow Toggle */
  .follow-toggle-btn {
    background: #1f2937;
    border-color: var(--border-color);
    font-size: 0.75rem;
    padding: 0.22rem 0.5rem;
  }
  .follow-toggle-btn.active {
    background: #065f46;
    border-color: #10b981;
    color: #a7f3d0;
  }

  /* Zoom Control Section (Compact) */
  .zoom-control {
    display: flex;
    align-items: center;
    gap: 0.25rem;
    background: #1f2937;
    padding: 0.2rem 0.4rem;
    border-radius: 6px;
    border: 1px solid var(--border-color);
  }

  /* Main Document Viewer (Maximum Screen Space) */
  #viewerContainer {
    flex: 1;
    overflow-y: auto;
    overflow-x: auto;
    padding: 1rem 0.5rem 2rem;
    display: flex;
    flex-direction: column;
    align-items: center;
    background: #1e2433;
    position: relative;
    scroll-behavior: smooth;
  }

  /* Floating "Resume Follow" Button */
  #floatingFollowBtn {
    position: fixed;
    bottom: 1.5rem;
    left: 50%;
    transform: translateX(-50%);
    background: #0284c7;
    color: #ffffff;
    border: 2px solid #38bdf8;
    border-radius: 30px;
    padding: 0.5rem 1.2rem;
    font-size: 0.85rem;
    font-weight: 600;
    box-shadow: 0 6px 18px rgba(0, 0, 0, 0.5), 0 0 12px rgba(56, 189, 248, 0.6);
    z-index: 95;
    cursor: pointer;
    display: none;
    align-items: center;
    gap: 0.4rem;
    animation: pulseGlow 2s infinite;
  }

  #floatingFollowBtn:hover {
    background: #0369a1;
    transform: translateX(-50%) scale(1.05);
  }

  @keyframes pulseGlow {
    0%, 100% { box-shadow: 0 6px 18px rgba(0, 0, 0, 0.5), 0 0 8px rgba(56, 189, 248, 0.5); }
    50% { box-shadow: 0 6px 22px rgba(0, 0, 0, 0.6), 0 0 15px rgba(56, 189, 248, 0.9); }
  }

  /* Drop Zone */
  .dropzone {
    border: 2px dashed #4b5563;
    border-radius: 12px;
    padding: 3rem 2.5rem;
    text-align: center;
    background: var(--bg-header);
    cursor: pointer;
    transition: all 0.2s ease;
    margin: auto 0;
    max-width: 540px;
    width: 100%;
    box-shadow: 0 8px 30px rgba(0, 0, 0, 0.4);
  }
  .dropzone:hover, .dropzone.dragover {
    border-color: var(--accent);
    background: #1e293b;
    transform: translateY(-2px);
  }

  /* PDF Pages Wrapper with Smooth GPU Zoom Scaling */
  #pdfPagesWrapper {
    display: flex;
    flex-direction: column;
    align-items: center;
    transform-origin: top center;
    transition: transform 0.15s ease-out;
  }

  /* PDF Page Container */
  .pdf-page-container {
    position: relative;
    margin-bottom: 1.5rem;
    background: #ffffff;
    box-shadow: 0 8px 25px rgba(0, 0, 0, 0.6);
    border-radius: 4px;
    overflow: hidden;
  }

  .pdf-page-container canvas {
    display: block;
  }

  /* PDF.js Text Layer */
  .textLayer {
    position: absolute;
    left: 0;
    top: 0;
    right: 0;
    bottom: 0;
    overflow: hidden;
    line-height: 1.0;
    text-size-adjust: none;
    -webkit-text-size-adjust: none;
    transform-origin: 0 0;
    z-index: 2;
    opacity: 1.0;
  }

  .textLayer span {
    color: transparent !important;
    position: absolute;
    white-space: pre;
    cursor: pointer;
    transform-origin: 0% 0%;
  }

  /* Word Element Styling */
  .tts-word {
    display: inline !important;
    position: relative !important;
    color: transparent !important;
    cursor: pointer !important;
    border-radius: 2px !important;
    padding: 1px 0 !important;
    margin: 0 !important;
    mix-blend-mode: multiply !important;
    transition: background-color 0.05s ease !important;
    user-select: text !important;
  }

  .tts-word:hover {
    background-color: rgba(186, 230, 253, 0.5) !important;
    border-radius: 2px !important;
  }

  /* 1. BRIGHTEST HIGHLIGHT: Current Word (Translucent Golden-Yellow - Never Obscures Black Ink) */
  .tts-word.tts-current {
    background-color: rgba(254, 224, 0, 0.55) !important;
    border-bottom: 2.5px solid #d97706 !important;
    border-radius: 2px !important;
    box-shadow: 0 0 6px rgba(245, 158, 11, 0.4) !important;
    z-index: 10 !important;
  }

  /* 2. PAST CONTEXT HIGHLIGHT: 5 Words Before (Gentle Warm Marker) */
  .tts-word.tts-past-context {
    background-color: rgba(254, 240, 138, 0.32) !important;
    border-bottom: 1.5px solid rgba(217, 119, 6, 0.35) !important;
    border-radius: 2px !important;
  }

  /* 3. FUTURE CONTEXT HIGHLIGHT: 2 Words After (Gentle Sky Tint) */
  .tts-word.tts-future-context {
    background-color: rgba(186, 230, 253, 0.28) !important;
    border-bottom: 1.5px dashed rgba(56, 189, 248, 0.45) !important;
    border-radius: 2px !important;
  }
</style>
</head>
<body>

<header>
  <div class="brand">
    <span>🎙️</span>
    <span>Pocket TTS</span>
    <span id="pageIndicator" style="font-size:0.75rem; color:var(--text-muted); font-weight:normal; margin-left:0.4rem;"></span>
  </div>

  <div class="controls-group">
    <input type="file" id="pdfFileInput" accept=".pdf" style="display:none;" />
    <button onclick="document.getElementById('pdfFileInput').click()">📁 Open PDF</button>

    <label for="voiceSelect" style="color:var(--text-muted); font-size:0.75rem; margin-left:0.2rem;">Voice:</label>
    <select id="voiceSelect" style="padding:0.2rem 0.45rem; font-size:0.75rem;"></select>

    <!-- Speed Slider Component -->
    <div class="speed-control" title="Adjust playback speed (0.5x - 3.0x in 0.1x steps)">
      <label for="speedSlider">Speed</label>
      <input type="range" id="speedSlider" class="speed-slider" min="0.5" max="3.0" step="0.1" value="1.0" oninput="onSpeedChange(this.value)" />
      <span id="speedDisplay" class="speed-badge">1.0x</span>
      <div class="speed-presets">
        <button class="preset-btn active" onclick="setSpeedPreset(1.0)">1x</button>
        <button class="preset-btn" onclick="setSpeedPreset(1.2)">1.2x</button>
        <button class="preset-btn" onclick="setSpeedPreset(1.5)">1.5x</button>
        <button class="preset-btn" onclick="setSpeedPreset(2.0)">2x</button>
      </div>
    </div>

    <!-- Playback Controls -->
    <button id="playBtn" class="primary" onclick="togglePlay()">▶ Play</button>
    <button id="stopBtn" class="danger" onclick="stopPlay()">⏹ Stop</button>
    
    <!-- Auto-Follow Toggle -->
    <button id="headerFollowBtn" class="follow-toggle-btn active" onclick="toggleAutoFollow()" title="Toggle Auto-Follow Reading View">🎯 Follow</button>

    <!-- Instant GPU Zoom Controls (Never resets or stops reading) -->
    <div class="zoom-control">
      <button onclick="changeZoom(-0.1)" title="Zoom Out" style="padding:0.18rem 0.45rem; font-size:0.75rem;">🔍 -</button>
      <span id="zoomLevel" style="font-size: 0.75rem; color: var(--text-muted); min-width: 36px; text-align: center;">100%</span>
      <button onclick="changeZoom(0.1)" title="Zoom In" style="padding:0.18rem 0.45rem; font-size:0.75rem;">🔍 +</button>
      <button onclick="resetZoom()" title="Reset Zoom" style="padding:0.18rem 0.35rem; font-size:0.7rem;">Reset</button>
    </div>
  </div>
</header>

<div id="viewerContainer">
  <div id="dropzone" class="dropzone" onclick="document.getElementById('pdfFileInput').click()">
    <div style="font-size: 3rem; margin-bottom: 0.5rem;">📄</div>
    <h3 style="font-size: 1.15rem; margin-bottom: 0.35rem;">Choose or Drop a PDF File</h3>
    <p style="color: var(--text-muted); font-size: 0.85rem; margin-bottom: 1rem;">
      Full visual layout, images, equations, columns, and fonts are 100% preserved.
    </p>
    <button class="primary" style="margin: 0 auto; padding: 0.5rem 1.25rem;">Select PDF Document</button>
  </div>

  <div id="pdfPagesWrapper" style="display: none;"></div>
</div>

<!-- Floating Follow Button when user manually scrolled away -->
<button id="floatingFollowBtn" onclick="enableAutoFollowAndScroll()">
  <span>🎯</span>
  <span>Return to Reading View</span>
</button>

<audio id="audioPlayer" style="display:none;"></audio>

<script>
// Configure PDF.js Worker
pdfjsLib.GlobalWorkerOptions.workerSrc = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';

let pdfDoc = null;
let currentPdfData = null;
let baseScale = 1.35; // Render scale for crisp high-DPI canvas
let zoomFactor = 1.0; // Current zoom scale (1.0 = 100%)
let allWords = []; // List of all { globalWordId, pageNum, text, el, sentenceId, wordIndexInSentence }
let allSentences = []; // List of { id, pageNum, text, words: [wordObj], wordTimings: [] }
let currentSentenceIdx = -1;
let currentWordIdxInSentence = -1;
let isPlaying = false;
let currentSpeed = 1.0;
let animFrameId = null;

// Auto-follow scrolling state
let isAutoFollow = true;
let isProgrammaticScroll = false;

const audioPlayer = document.getElementById('audioPlayer');
const viewerContainer = document.getElementById('viewerContainer');
const floatingFollowBtn = document.getElementById('floatingFollowBtn');
const headerFollowBtn = document.getElementById('headerFollowBtn');
const pageIndicator = document.getElementById('pageIndicator');

// Detect user manual scroll to pause auto-follow without stopping audio
viewerContainer.addEventListener('wheel', () => {
  if (isAutoFollow && isPlaying) {
    setAutoFollow(false);
  }
}, { passive: true });

viewerContainer.addEventListener('touchmove', () => {
  if (isAutoFollow && isPlaying) {
    setAutoFollow(false);
  }
}, { passive: true });

function setAutoFollow(val) {
  isAutoFollow = val;
  if (isAutoFollow) {
    headerFollowBtn.classList.add('active');
    headerFollowBtn.innerText = '🎯 Follow: ON';
    floatingFollowBtn.style.display = 'none';
  } else {
    headerFollowBtn.classList.remove('active');
    headerFollowBtn.innerText = '🎯 Follow: OFF';
    if (isPlaying) {
      floatingFollowBtn.style.display = 'flex';
    }
  }
}

function toggleAutoFollow() {
  setAutoFollow(!isAutoFollow);
  if (isAutoFollow && isPlaying) {
    scrollCurrentWordIntoView();
  }
}

function enableAutoFollowAndScroll() {
  setAutoFollow(true);
  scrollCurrentWordIntoView();
}

function scrollCurrentWordIntoView() {
  if (currentSentenceIdx >= 0 && currentSentenceIdx < allSentences.length) {
    const s = allSentences[currentSentenceIdx];
    const w = s.words[Math.max(0, currentWordIdxInSentence)];
    if (w && w.el) {
      isProgrammaticScroll = true;
      w.el.scrollIntoView({ behavior: 'smooth', block: 'center', inline: 'nearest' });
      setTimeout(() => { isProgrammaticScroll = false; }, 400);
    }
  }
}

// Populate voices from backend
fetch('/api/voices')
  .then(r => r.json())
  .then(voices => {
    const sel = document.getElementById('voiceSelect');
    sel.innerHTML = '';
    voices.forEach(v => {
      const opt = document.createElement('option');
      opt.value = v;
      opt.textContent = v;
      sel.appendChild(opt);
    });
  });

// Setup File Handlers
document.getElementById('pdfFileInput').addEventListener('change', e => {
  if (e.target.files.length) loadPdfFile(e.target.files[0]);
});

const dropzone = document.getElementById('dropzone');
['dragenter', 'dragover'].forEach(name => {
  dropzone.addEventListener(name, e => { e.preventDefault(); dropzone.classList.add('dragover'); });
});
['dragleave', 'drop'].forEach(name => {
  dropzone.addEventListener(name, e => { e.preventDefault(); dropzone.classList.remove('dragover'); });
});
dropzone.addEventListener('drop', e => {
  if (e.dataTransfer.files.length) loadPdfFile(e.dataTransfer.files[0]);
});

function loadPdfFile(file) {
  const reader = new FileReader();
  reader.onload = async function() {
    currentPdfData = new Uint8Array(this.result);
    await renderFullDocument();
  };
  reader.readAsArrayBuffer(file);
}

// Render Document with PDF.js preserving exact paper layout & images
async function renderFullDocument() {
  if (!currentPdfData) return;
  
  document.getElementById('dropzone').style.display = 'none';
  const wrapper = document.getElementById('pdfPagesWrapper');
  wrapper.style.display = 'flex';
  wrapper.innerHTML = '';
  allWords = [];
  allSentences = [];
  currentSentenceIdx = -1;
  stopPlay();

  pdfDoc = await pdfjsLib.getDocument({ data: currentPdfData }).promise;
  const numPages = pdfDoc.numPages;

  for (let pageNum = 1; pageNum <= numPages; pageNum++) {
    await renderPage(pageNum, wrapper);
  }

  if (pageIndicator) {
    pageIndicator.innerText = `(${numPages} pages, ${allSentences.length} sentences)`;
  }
}

async function renderPage(pageNum, container) {
  const page = await pdfDoc.getPage(pageNum);
  const viewport = page.getViewport({ scale: baseScale });

  const pageBox = document.createElement('div');
  pageBox.className = 'pdf-page-container';
  pageBox.style.width = `${viewport.width}px`;
  pageBox.style.height = `${viewport.height}px`;
  pageBox.id = `page-container-${pageNum}`;

  // Canvas for exact original page rendering (images, vector graphics, fonts, formulas)
  const canvas = document.createElement('canvas');
  const context = canvas.getContext('2d');
  
  // High-DPI crisp rendering
  const outputScale = window.devicePixelRatio || 1;
  canvas.width = Math.floor(viewport.width * outputScale);
  canvas.height = Math.floor(viewport.height * outputScale);
  canvas.style.width = `${viewport.width}px`;
  canvas.style.height = `${viewport.height}px`;

  const transform = outputScale !== 1 ? [outputScale, 0, 0, outputScale, 0, 0] : null;
  await page.render({ canvasContext: context, transform: transform, viewport: viewport }).promise;
  pageBox.appendChild(canvas);

  // Text layer for interactive follow-along highlight and click-to-play
  const textLayerDiv = document.createElement('div');
  textLayerDiv.className = 'textLayer';
  textLayerDiv.style.width = `${viewport.width}px`;
  textLayerDiv.style.height = `${viewport.height}px`;
  textLayerDiv.style.setProperty('--scale-factor', baseScale);
  pageBox.appendChild(textLayerDiv);

  const textContent = await page.getTextContent();
  const textLayer = pdfjsLib.renderTextLayer({
    textContentSource: textContent,
    container: textLayerDiv,
    viewport: viewport,
    textDivs: []
  });
  await textLayer.promise;

  // Process text spans into word-level interactive elements
  processPageWords(pageNum, textLayerDiv);

  // Allow clicking anywhere on textLayer with nearest-word fallback
  setupPageClickFallback(textLayerDiv);

  container.appendChild(pageBox);
}

// Convert all text spans into fine-grained word spans
function processPageWords(pageNum, textLayerDiv) {
  const spanNodes = Array.from(textLayerDiv.querySelectorAll('span'));
  const pageWordElements = [];

  spanNodes.forEach(span => {
    if (span.children.length > 0) return;
    const fullText = span.textContent;
    if (!fullText || !fullText.trim()) return;

    // Split text into words and whitespace
    const tokens = fullText.split(/(\s+)/);
    span.innerHTML = '';

    tokens.forEach(tok => {
      if (tok.trim().length > 0) {
        const wSpan = document.createElement('span');
        wSpan.className = 'tts-word';
        wSpan.textContent = tok;
        span.appendChild(wSpan);
        pageWordElements.push({ pageNum: pageNum, text: tok, el: wSpan });
      } else {
        span.appendChild(document.createTextNode(tok));
      }
    });
  });

  // Group words into sentences
  let currentSentenceWords = [];
  let currentSentenceText = "";

  pageWordElements.forEach(wObj => {
    const globalId = allWords.length;
    wObj.globalWordId = globalId;
    allWords.push(wObj);

    currentSentenceWords.push(wObj);
    currentSentenceText += (currentSentenceText ? " " : "") + wObj.text;

    // Detect sentence and clause boundaries to keep chunks under model limits
    const trimmed = wObj.text.trim();
    const isPunctuationEnd = /[.!?:]["']?$/.test(trimmed) && currentSentenceWords.length >= 3;
    const isClauseBreak = (currentSentenceWords.length >= 22 && /[,;—–]/.test(trimmed));
    const isMaxLength = currentSentenceWords.length >= 32;

    if (isPunctuationEnd || isClauseBreak || isMaxLength) {
      registerSentence(pageNum, currentSentenceText.trim(), currentSentenceWords);
      currentSentenceWords = [];
      currentSentenceText = "";
    }
  });

  // Any remaining words on page
  if (currentSentenceWords.length > 0) {
    registerSentence(pageNum, currentSentenceText.trim(), currentSentenceWords);
  }
}

function registerSentence(pageNum, text, wordsList) {
  if (!wordsList.length) return;
  const sentenceId = allSentences.length;

  const sentenceObj = {
    id: sentenceId,
    pageNum: pageNum,
    text: text,
    words: wordsList,
    wordTimings: []
  };

  wordsList.forEach((wObj, idxInSent) => {
    wObj.sentenceId = sentenceId;
    wObj.wordIndexInSentence = idxInSent;

    // Word click handler: Jump directly to this exact word
    wObj.el.onclick = (e) => {
      e.stopPropagation();
      jumpToWord(wObj);
    };
  });

  allSentences.push(sentenceObj);
}

// Fallback click handler for clicking near words or selecting text
function setupPageClickFallback(textLayerDiv) {
  textLayerDiv.addEventListener('click', (e) => {
    if (e.target.classList.contains('tts-word')) return;
    
    let targetWord = null;
    if (document.caretRangeFromPoint) {
      const range = document.caretRangeFromPoint(e.clientX, e.clientY);
      if (range && range.startContainer) {
        const parentSpan = range.startContainer.parentElement;
        targetWord = parentSpan ? parentSpan.closest('.tts-word') : null;
      }
    }

    if (!targetWord) {
      let minDist = 999999;
      const words = textLayerDiv.querySelectorAll('.tts-word');
      words.forEach(w => {
        const rect = w.getBoundingClientRect();
        const dist = Math.hypot(rect.left + rect.width/2 - e.clientX, rect.top + rect.height/2 - e.clientY);
        if (dist < minDist && dist < 120) {
          minDist = dist;
          targetWord = w;
        }
      });
    }

    if (targetWord) {
      const foundWordObj = allWords.find(w => w.el === targetWord);
      if (foundWordObj) jumpToWord(foundWordObj);
    }
  });
}

// Seamless GPU Zoom Handling (No DOM rebuild, no audio interruption)
function changeZoom(delta) {
  zoomFactor = Math.min(Math.max(0.5, zoomFactor + delta), 2.5);
  applyZoom();
}

function resetZoom() {
  zoomFactor = 1.0;
  applyZoom();
}

function applyZoom() {
  const wrapper = document.getElementById('pdfPagesWrapper');
  wrapper.style.transform = `scale(${zoomFactor})`;
  document.getElementById('zoomLevel').innerText = `${Math.round(zoomFactor * 100)}%`;
}

// Speed Control Handling (Instant & Accessible)
function onSpeedChange(val) {
  currentSpeed = parseFloat(val);
  document.getElementById('speedDisplay').innerText = `${currentSpeed.toFixed(1)}x`;
  audioPlayer.playbackRate = currentSpeed;
  updatePresetButtons();
}

function setSpeedPreset(val) {
  document.getElementById('speedSlider').value = val;
  onSpeedChange(val);
}

function updatePresetButtons() {
  document.querySelectorAll('.preset-btn').forEach(btn => {
    const pVal = parseFloat(btn.innerText);
    if (Math.abs(pVal - currentSpeed) < 0.05) btn.classList.add('active');
    else btn.classList.remove('active');
  });
}

// Jump directly to a specific word / sentence
function jumpToWord(wordObj) {
  cancelAnimationFrame(animFrameId);
  audioPlayer.pause();
  clearAllHighlights();

  currentSentenceIdx = wordObj.sentenceId;
  const startWordIdx = wordObj.wordIndexInSentence;
  currentWordIdxInSentence = startWordIdx;
  
  // Start reading phrase from clicked word onwards
  if (startWordIdx > 0 && startWordIdx < allSentences[currentSentenceIdx].words.length) {
    playCustomSentence(currentSentenceIdx, startWordIdx);
  } else {
    playSentence(currentSentenceIdx);
  }
}

function togglePlay() {
  if (isPlaying) {
    audioPlayer.pause();
    isPlaying = false;
    cancelAnimationFrame(animFrameId);
    document.getElementById('playBtn').innerText = '▶ Resume';
  } else {
    if (currentSentenceIdx < 0 || currentSentenceIdx >= allSentences.length) {
      currentSentenceIdx = 0;
      currentWordIdxInSentence = 0;
    }
    isPlaying = true;
    document.getElementById('playBtn').innerText = '⏸ Pause';
    playSentence(currentSentenceIdx);
  }
}

function stopPlay() {
  audioPlayer.pause();
  isPlaying = false;
  cancelAnimationFrame(animFrameId);
  clearAllHighlights();
  floatingFollowBtn.style.display = 'none';
  document.getElementById('playBtn').innerText = '▶ Play';
}

function clearAllHighlights() {
  allWords.forEach(w => {
    w.el.classList.remove('tts-current', 'tts-past-context', 'tts-future-context');
  });
}

// Pre-cached audio Blobs for zero-latency gapless transitions
let audioBlobCache = {};

async function getAudioBlobUrl(url) {
  if (audioBlobCache[url]) {
    return audioBlobCache[url];
  }
  try {
    const res = await fetch(url);
    const blob = await res.blob();
    const blobUrl = URL.createObjectURL(blob);
    audioBlobCache[url] = blobUrl;
    return blobUrl;
  } catch (e) {
    return url; // fallback to direct URL
  }
}

async function playSentence(sentenceIdx) {
  if (!isPlaying) return;
  if (sentenceIdx >= allSentences.length) {
    stopPlay();
    return;
  }

  // Freeze / stop previous animation loop immediately to prevent jumping back to start
  cancelAnimationFrame(animFrameId);

  currentSentenceIdx = sentenceIdx;
  currentWordIdxInSentence = 0;
  const sentence = allSentences[currentSentenceIdx];
  const voice = document.getElementById('voiceSelect').value;

  if (pageIndicator) {
    pageIndicator.innerText = `(Page ${sentence.pageNum} | ${currentSentenceIdx + 1}/${allSentences.length})`;
  }

  // Immediately highlight the first word of the incoming sentence
  applyWordHighlightWindow(sentence, 0);

  const url = `/api/tts?voice=${encodeURIComponent(voice)}&text=${encodeURIComponent(sentence.text)}`;
  const audioSrc = await getAudioBlobUrl(url);
  if (!isPlaying || currentSentenceIdx !== sentenceIdx) return;

  audioPlayer.src = audioSrc;
  audioPlayer.playbackRate = currentSpeed;

  audioPlayer.onloadedmetadata = () => {
    calculateWordTimings(sentence, audioPlayer.duration, 0);
    audioPlayer.play().catch(e => console.error("Playback error:", e));
    startWordTrackingLoop(sentence, 0);
  };

  prefetchSentence(currentSentenceIdx + 1, voice);
}

async function playCustomSentence(sentenceIdx, startWordIdx) {
  cancelAnimationFrame(animFrameId);

  currentSentenceIdx = sentenceIdx;
  currentWordIdxInSentence = startWordIdx;
  const sentence = allSentences[currentSentenceIdx];
  const wordsToSpeak = sentence.words.slice(startWordIdx);
  const textToSpeak = wordsToSpeak.map(w => w.text).join(" ");
  const voice = document.getElementById('voiceSelect').value;

  isPlaying = true;
  document.getElementById('playBtn').innerText = '⏸ Pause';

  if (pageIndicator) {
    pageIndicator.innerText = `(Page ${sentence.pageNum} | ${currentSentenceIdx + 1}/${allSentences.length})`;
  }

  // Immediately highlight the clicked starting word
  applyWordHighlightWindow(sentence, startWordIdx);

  const url = `/api/tts?voice=${encodeURIComponent(voice)}&text=${encodeURIComponent(textToSpeak)}`;
  const audioSrc = await getAudioBlobUrl(url);
  if (!isPlaying || currentSentenceIdx !== sentenceIdx) return;

  audioPlayer.src = audioSrc;
  audioPlayer.playbackRate = currentSpeed;

  audioPlayer.onloadedmetadata = () => {
    calculateWordTimings(sentence, audioPlayer.duration, startWordIdx);
    audioPlayer.play().catch(e => console.error("Playback error:", e));
    startWordTrackingLoop(sentence, startWordIdx);
  };
}

// Calculate proportional time segments for each word based on character length + punctuation
function calculateWordTimings(sentence, duration, startOffset) {
  const activeWords = sentence.words.slice(startOffset);
  let totalWeight = 0;

  const weights = activeWords.map(w => {
    let weight = Math.max(1, w.text.length);
    if (/[.!?:;,]/.test(w.text)) weight += 2.5; // slight pause on punctuation
    totalWeight += weight;
    return weight;
  });

  let accumTime = 0;
  sentence.wordTimings = activeWords.map((w, i) => {
    const wordDur = (weights[i] / totalWeight) * duration;
    const start = accumTime;
    accumTime += wordDur;
    return {
      wordObj: w,
      idxInSentence: startOffset + i,
      start: start,
      end: accumTime
    };
  });
}

// Real-Time Frame Loop
function startWordTrackingLoop(sentence, startOffset) {
  cancelAnimationFrame(animFrameId);

  function update() {
    if (!isPlaying) return;

    const curTime = audioPlayer.currentTime;
    const timings = sentence.wordTimings;

    if (timings && timings.length) {
      let activeTiming = timings.find(t => curTime >= t.start && curTime < t.end);
      if (!activeTiming && curTime >= timings[timings.length - 1].start) {
        activeTiming = timings[timings.length - 1];
      }

      if (activeTiming) {
        const activeWordIdx = activeTiming.idxInSentence;
        currentWordIdxInSentence = activeWordIdx;
        applyWordHighlightWindow(sentence, activeWordIdx);
      }
    }

    animFrameId = requestAnimationFrame(update);
  }

  animFrameId = requestAnimationFrame(update);
}

// Highlights: Strictly only the current word being read
function applyWordHighlightWindow(sentence, activeWordIdx) {
  clearAllHighlights();

  const words = sentence.words;
  const activeWord = words[activeWordIdx];

  // Current Word Highlight (Bright Golden Highlighter)
  if (activeWord && activeWord.el) {
    activeWord.el.classList.add('tts-current');
    
    // Auto-follow view scroll if enabled
    if (isAutoFollow) {
      isProgrammaticScroll = true;
      activeWord.el.scrollIntoView({ behavior: 'smooth', block: 'center', inline: 'nearest' });
      setTimeout(() => { isProgrammaticScroll = false; }, 300);
    }
  }
}

function prefetchSentence(nextIdx, voice) {
  if (nextIdx >= allSentences.length) return;
  const next = allSentences[nextIdx];
  const url = `/api/tts?voice=${encodeURIComponent(voice)}&text=${encodeURIComponent(next.text)}`;
  getAudioBlobUrl(url); // Fetch and store in Blob memory ahead of time
}

audioPlayer.onended = () => {
  if (isPlaying) {
    cancelAnimationFrame(animFrameId);
    currentSentenceIdx++;
    playSentence(currentSentenceIdx);
  }
};

// Keyboard Shortcuts
document.addEventListener('keydown', e => {
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT') return;
  if (e.code === 'Space') {
    e.preventDefault();
    togglePlay();
  } else if (e.key === 'ArrowRight') {
    if (currentSentenceIdx < allSentences.length - 1) playSentence(currentSentenceIdx + 1);
  } else if (e.key === 'ArrowLeft') {
    if (currentSentenceIdx > 0) playSentence(currentSentenceIdx - 1);
  } else if (e.key === ']') {
    setSpeedPreset(Math.min(3.0, currentSpeed + 0.1));
  } else if (e.key === '[') {
    setSpeedPreset(Math.max(0.5, currentSpeed - 0.1));
  } else if (e.key.toLowerCase() === 'f') {
    toggleAutoFollow();
  }
});
</script>
</body>
</html>
"""

class PocketTTSHandler(SimpleHTTPRequestHandler):
    tts_instance: PocketTTS = None
    voice_list: list[str] = []
    audio_cache: dict[str, bytes] = {}

    def do_HEAD(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path in ("/", "/index.html"):
            html_bytes = HTML_PAGE.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(html_bytes)))
            self.end_headers()
            return
        self.send_response(404)
        self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        
        if parsed.path in ("/", "/index.html"):
            html_bytes = HTML_PAGE.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(html_bytes)))
            self.end_headers()
            self.wfile.write(html_bytes)
            return

        if parsed.path == "/api/voices":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(self.voice_list).encode("utf-8"))
            return

        if parsed.path == "/api/tts":
            query = urllib.parse.parse_qs(parsed.query)
            text = query.get("text", [""])[0]
            voice = query.get("voice", ["alba"])[0]
            
            if not text:
                self.send_response(400)
                self.end_headers()
                return

            cache_key = f"{voice}:{text}"
            if cache_key in self.audio_cache:
                wav_data = self.audio_cache[cache_key]
            else:
                try:
                    samples, sample_rate = self.tts_instance.create(text, voice=voice)
                    samples_int16 = (np.clip(samples, -1.0, 1.0) * 32767).astype(np.int16)
                    
                    wav_buffer = io.BytesIO()
                    with wave.open(wav_buffer, "wb") as wf:
                        wf.setnchannels(1)
                        wf.setsampwidth(2)
                        wf.setframerate(sample_rate)
                        wf.writeframes(samples_int16.tobytes())
                    
                    wav_data = wav_buffer.getvalue()
                    if len(self.audio_cache) < 250:
                        self.audio_cache[cache_key] = wav_data
                except Exception as e:
                    self.send_response(500)
                    self.end_headers()
                    self.wfile.write(str(e).encode("utf-8"))
                    return

            self.send_response(200)
            self.send_header("Content-Type", "audio/wav")
            self.send_header("Content-Length", str(len(wav_data)))
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(wav_data)
            return

        self.send_response(404)
        self.end_headers()

def main():
    parser = argparse.ArgumentParser(description="Start Pocket TTS Visual PDF Reader.")
    parser.add_argument("--model", default="pocket-tts-english.onnx", help="Path to ONNX model")
    parser.add_argument("--port", type=int, default=8000, help="Port to listen on (default: 8000)")
    args = parser.parse_args()

    if not os.path.exists(args.model):
        print(f"Model file '{args.model}' not found!")
        import sys
        sys.exit(1)

    print(f"Loading Pocket TTS model '{args.model}'...")
    tts = PocketTTS(args.model)
    voices = tts.voices()
    voice_names = list(voices.keys()) if isinstance(voices, dict) else (voices if isinstance(voices, list) else ["alba"])
    print(f"Loaded successfully! Available voices: {voice_names}")

    PocketTTSHandler.tts_instance = tts
    PocketTTSHandler.voice_list = voice_names

    server = HTTPServer(("127.0.0.1", args.port), PocketTTSHandler)
    print("\n" + "="*65)
    print(f"🚀 Pocket TTS Visual PDF Reader is running at: http://127.0.0.1:{args.port}")
    print("Open the link in your browser to view and read any PDF paper!")
    print("="*65 + "\n")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server.")

if __name__ == "__main__":
    main()
