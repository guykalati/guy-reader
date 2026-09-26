// Guy_reader - High-Performance Minimalist TTS Engine & UI
(() => {
  'use strict';

  // State
  const state = {
    speed: parseFloat(localStorage.getItem('guy_reader_speed') || '1.0'),
    isPlaying: false,
    isPaused: false,
    text: '',
    sentences: [],
    currentIndex: -1,
    currentUtterance: null,
    audioElement: new Audio(),
    voiceEn: localStorage.getItem('guy_reader_voice_en') || 'af_sarah',
    voiceHe: localStorage.getItem('guy_reader_voice_he') || 'edge-he-avri',
    voice: localStorage.getItem('guy_reader_voice') || 'af_sarah',
    language: 'en',
    drawerOpen: false,
    prebufferCache: new Map(),
    synchronized: localStorage.getItem('guy_reader_sync') === 'true',
    connectedSegments: null,
    backend: null,
    browserActive: false,
    generation: 0,
    playbackId: 0,
    pendingIndex: -1,
    requests: new Set(),
    activeUrl: null,
    previewFinish: null,
    apiKeys: {
      eleven: localStorage.getItem('guy_reader_eleven_key') || localStorage.getItem('glaido_eleven_key') || '',
      google: localStorage.getItem('guy_reader_google_key') || localStorage.getItem('glaido_google_key') || ''
    }
  };

  // DOM Elements
  const dom = {
    container: document.getElementById('guyReaderContainer') || document.getElementById('glaidoContainer'),
    statusDot: document.getElementById('statusDot'),
    equalizer: document.getElementById('equalizer'),
    langTag: document.getElementById('langTag'),
    previewZone: document.getElementById('previewZone'),
    previewText: document.getElementById('previewText'),
    btnSpeedDown: document.getElementById('btnSpeedDown'),
    btnSpeedUp: document.getElementById('btnSpeedUp'),
    btnSpeedVal: document.getElementById('btnSpeedVal'),
    btnPlayPause: document.getElementById('btnPlayPause'),
    btnStop: document.getElementById('btnStop'),
    synchronizedMode: document.getElementById('synchronizedMode'),
    iconPlay: document.getElementById('iconPlay'),
    iconPause: document.getElementById('iconPause'),
    btnReadSelection: document.getElementById('btnReadSelection'),
    btnPillPaste: document.getElementById('btnPillPaste'),
    btnPillSettings: document.getElementById('btnPillSettings'),
    btnToggleDrawer: document.getElementById('btnToggleDrawer'),
    btnMinimize: document.getElementById('btnMinimize'),
    btnExit: document.getElementById('btnExit'),
    resizeHandleRight: document.getElementById('resizeHandleRight'),
    resizeHandleCorner: document.getElementById('resizeHandleCorner'),
    drawer: document.getElementById('drawer'),
    voiceSelect: document.getElementById('voiceSelect'),
    btnEditText: document.getElementById('btnEditText'),
    manualTextInput: document.getElementById('manualTextInput'),
    btnReadManualText: document.getElementById('btnReadManualText'),
    btnPasteText: document.getElementById('btnPasteText'),
    btnClearText: document.getElementById('btnClearText'),
    btnSettings: document.getElementById('btnSettings'),
    readerContent: document.getElementById('readerContent'),
    emptyState: document.getElementById('emptyState'),
    btnEmptyPaste: document.getElementById('btnEmptyPaste'),
    sentencesList: document.getElementById('sentencesList'),
    speedSlider: document.getElementById('speedSlider'),
    speedSliderVal: document.getElementById('speedSliderVal'),
    settingsModal: document.getElementById('settingsModal'),
    btnCloseSettings: document.getElementById('btnCloseSettings'),
    btnSaveSettings: document.getElementById('btnSaveSettings'),
    btnResetSettings: document.getElementById('btnResetSettings'),
    settingsVoiceEn: document.getElementById('settingsVoiceEn'),
    settingsVoiceHe: document.getElementById('settingsVoiceHe'),
    btnTestVoiceEn: document.getElementById('btnTestVoiceEn'),
    btnTestVoiceHe: document.getElementById('btnTestVoiceHe'),
    settingsSpeedSlider: document.getElementById('settingsSpeedSlider'),
    settingsSpeedVal: document.getElementById('settingsSpeedVal'),
    btnSettingsSpeedDown: document.getElementById('btnSettingsSpeedDown'),
    btnSettingsSpeedUp: document.getElementById('btnSettingsSpeedUp'),
    previewStatus: document.getElementById('previewStatus'),
    previewSampleText: document.getElementById('previewSampleText'),
    elevenApiKey: document.getElementById('elevenApiKey'),
    googleApiKey: document.getElementById('googleApiKey'),
    dragZone: document.getElementById('dragZone')
  };

  let userWidth = 460;
  let userExpandedHeight = 360;
  let userCompactHeight = 60;

  // Helpers
  function isHebrew(text) {
    return /[\u0590-\u05FF]/.test(text);
  }

  function isHebrewVoice(v) {
    if (!v) return false;
    const lower = v.toLowerCase();
    return lower.includes('-he-') ||
           lower.includes('_he_') ||
           lower.startsWith('he-') ||
           lower.startsWith('he_') ||
           lower.includes('hebrew') ||
           lower.includes('avri') ||
           lower.includes('hila') ||
           lower.includes('roboshaul') ||
           lower.includes('shaul');
  }

  function formatSpeed(val) {
    return val.toFixed(1) + 'x';
  }

  function clamp(val, min, max) {
    return Math.min(Math.max(val, min), max);
  }

  function setSpeed(newSpeed) {
    // 0.5 to 2.5 in 0.1 increments
    state.speed = Math.round(clamp(newSpeed, 0.5, 2.5) * 10) / 10;
    const formatted = formatSpeed(state.speed);
    if (dom.btnSpeedVal) dom.btnSpeedVal.textContent = formatted;
    if (dom.speedSlider) dom.speedSlider.value = state.speed;
    if (dom.speedSliderVal) dom.speedSliderVal.textContent = formatted;
    if (dom.settingsSpeedSlider) dom.settingsSpeedSlider.value = state.speed;
    if (dom.settingsSpeedVal) dom.settingsSpeedVal.textContent = formatted;

    if (state.audioElement && !state.audioElement.paused) {
      state.audioElement.playbackRate = state.speed;
    }

    localStorage.setItem('guy_reader_speed', state.speed);
    notifyNative('setSpeed', { speed: state.speed });
  }

  function notifyNative(action, payload = {}) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.app) {
      window.webkit.messageHandlers.app.postMessage({ action, ...payload });
    }
  }

  // Sentence Splitter (Clean sentence extraction preserving text boundaries, decimals, emails, URLs, abbreviations)
  function splitSentences(rawText) {
    if (!rawText) return [];
    const cleaned = rawText.replace(/\r\n/g, '\n').replace(/\r/g, '\n').trim();
    if (!cleaned) return [];

    let text = cleaned;
    // 1. Protect numbers with decimals and multi-dot dates (e.g. 3.5, 7.10, 7.10.2023, $19.99)
    while (/(\d)\.(\d)/.test(text)) {
      text = text.replace(/(\d)\.(\d)/g, (m, d1, d2) => d1 + '\uE000' + d2);
    }

    // 2. Protect email addresses
    text = text.replace(/([a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+)/g, (m) => m.replace(/\./g, '\uE000'));

    // 3. Protect URLs and domains
    text = text.replace(/(https?:\/\/[^\s]+)/gi, (m) => m.replace(/\./g, '\uE000'));
    text = text.replace(/([a-zA-Z0-9_-]+\.(?:com|org|net|io|co|il|edu|gov|ai|app|dev|me)[^\s]*)/gi, (m) => m.replace(/\./g, '\uE000'));

    // 4. Protect a.m. / p.m.
    text = text.replace(/\b([ap]\.m\.)/gi, (m) => m.replace(/\./g, '\uE000'));

    // 5. Protect English single letter initials followed by capital letter
    text = text.replace(/\b([A-Z])\.\s+(?=[A-Z])/g, '$1\uE000 ');

    // 6. Protect Hebrew initials followed by Hebrew word (e.g. א. כהן, י. שמעוני)
    text = text.replace(/(^|[\s("״'׳])([א-ת])\.\s+(?=[א-ת])/g, (m, p1, p2) => p1 + p2 + '\uE000 ');

    // 7. Protect common English abbreviations & titles
    const englishAbbrevs = [
      'dr', 'mr', 'mrs', 'ms', 'prof', 'sr', 'jr', 'vs', 'etc',
      'u.s.', 'u.s', 'e.g.', 'e.g', 'i.e.', 'i.e',
      'inc', 'ltd', 'corp', 'co', 'gen', 'col', 'gov', 'sen', 'rep',
      'st', 'ave', 'blvd', 'dept', 'no', 'fig', 'vol', 'al'
    ];
    englishAbbrevs.forEach(abbr => {
      const esc = abbr.replace(/\./g, '\\.');
      const regex = new RegExp('\\b' + esc + (abbr.endsWith('.') ? '' : '\\.'), 'gi');
      text = text.replace(regex, (m) => m.replace(/\./g, '\uE000'));
    });

    // 8. Protect Hebrew title abbreviations before names (e.g. פרופ., ופרופ., ד"ר., עו"ד., וכו.)
    const hebrewDotAbbrs = [
      /(^|[\s("״'׳])([בלמכושה]?פרופ)\./g,
      /(^|[\s("״'׳])([בלמכושה]?ד["״'׳]ר)\./g,
      /(^|[\s("״'׳])([בלמכושה]?עו["״'׳]ד)\./g,
      /(^|[\s("״'׳])([בלמכושה]?רו["״'׳]ח)\./g,
      /(^|[\s("״'׳])(וכו)\./g
    ];
    hebrewDotAbbrs.forEach(regex => {
      text = text.replace(regex, (m, p1, p2) => p1 + p2 + '\uE000');
    });

    // 9. Protect dialogue quotes ending in punctuation when followed by lowercase attribution
    text = text.replace(/([.!?׃]['"”’\)\]]*)\s+([a-z])/g, (match, p1, p2) => {
      return p1.replace(/\./g, '\uE000').replace(/!/g, '\uE001').replace(/\?/g, '\uE002') + ' ' + p2;
    });

    // Split on terminal punctuation followed by optional quotes/parens
    const regex = /([^.!?\n׃]+(?:[.!?׃]+['"”’\)\]]*|(?=[\n]|$))|[^.!?\n׃]+$)/g;
    const matches = text.match(regex) || [text];

    return matches
      .map(s => s.replace(/\uE000/g, '.').replace(/\uE001/g, '!').replace(/\uE002/g, '?').trim())
      .filter(s => s.length > 0 && /[\p{L}\p{N}]/u.test(s));
  }

  function updateEqualizer(active) {
    if (active) {
      dom.equalizer.classList.add('animating');
      dom.statusDot.className = 'status-dot active';
    } else {
      dom.equalizer.classList.remove('animating');
      dom.statusDot.className = state.isPaused ? 'status-dot paused' : 'status-dot';
    }
  }

  function setPlayPauseUI(playing) {
    state.isPlaying = playing;
    notifyNative('playbackState', { active: playing || state.isPaused });
    if (playing) {
      dom.iconPlay.style.display = 'none';
      dom.iconPause.style.display = 'block';
      updateEqualizer(true);
    } else {
      dom.iconPlay.style.display = 'block';
      dom.iconPause.style.display = 'none';
      updateEqualizer(false);
    }
  }

  // Render Sentences in Drawer (Readest-style highlight)
  function renderSentences() {
    if (!state.sentences || state.sentences.length === 0) {
      dom.emptyState.style.display = 'block';
      dom.sentencesList.style.display = 'none';
      dom.sentencesList.innerHTML = '';
      return;
    }

    dom.emptyState.style.display = 'none';
    dom.sentencesList.style.display = 'flex';
    dom.sentencesList.innerHTML = '';

    state.sentences.forEach((sentence, idx) => {
      const el = document.createElement('div');
      el.className = 'sentence-item';
      if (isHebrew(sentence)) {
        el.classList.add('rtl');
      }
      if (idx === state.currentIndex) {
        el.classList.add('active');
      }
      el.textContent = sentence;
      el.addEventListener('click', () => {
        playSentence(idx);
      });
      dom.sentencesList.appendChild(el);
    });
  }

  function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  function highlightSentence(index) {
    state.currentIndex = index;
    const items = dom.sentencesList.querySelectorAll('.sentence-item');
    items.forEach((item, idx) => {
      if (state.sentences[idx] !== undefined) item.textContent = state.sentences[idx];
      if (idx === index) {
        item.classList.add('active');
        item.scrollIntoView({ behavior: 'smooth', block: 'center' });
      } else {
        item.classList.remove('active');
      }
    });

    if (state.sentences[index]) {
      const sentence = state.sentences[index];
      const he = isHebrew(sentence);
      dom.langTag.textContent = he ? 'HE' : 'EN';
      dom.langTag.className = 'lang-tag' + (he ? ' hebrew' : '');
      const counter = `[${index + 1}/${state.sentences.length}]`;
      dom.previewText.innerHTML = `<span style="color:var(--accent-lime);font-weight:700;margin-right:5px;">${counter}</span> ${escapeHtml(sentence)}`;
      dom.previewText.className = 'preview-text' + (he ? ' rtl' : '');
    }
  }

  // Load new text into reader
  function loadText(rawText, autoStart = true) {
    if (!rawText || !rawText.trim()) return;
    stopSpeech();

    state.text = rawText.trim();
    notifyNative('textLoaded', { text: state.text });
    state.sentences = splitSentences(state.text);
    state.currentIndex = 0;

    const he = isHebrew(state.text);
    state.language = he ? 'he' : 'en';
    dom.langTag.textContent = he ? 'HE' : 'EN';
    dom.langTag.className = 'lang-tag' + (he ? ' hebrew' : '');

    state.voice = he ? state.voiceHe : state.voiceEn;
    dom.voiceSelect.value = state.voice;
    notifyNative('voiceChanged', { voice: state.voice });
    checkEvanBanner();
    clearPrebufferCache();

    renderSentences();

    // Auto-open reader drawer to reveal synchronized sentence highlighting
    if (!state.drawerOpen) {
      toggleDrawer(true);
    }

    if (autoStart && state.sentences.length > 0) {
      playSentence(0);
    }
  }

  // Speech Synthesizer Router
  function playSentence(index, continuous = false) {
    if (index < 0 || index >= state.sentences.length) {
      stopSpeech();
      return;
    }

    if (continuous) {
      // Smooth continuous sentence transition:
      // Detach listeners from previous audio and free previous URL without tearing down native bridge or sending IPC stop
      if (state.audioElement) {
        state.audioElement.onended = null;
        state.audioElement.onerror = null;
        state.audioElement.onplay = null;
      }
      if (state.activeUrl) {
        URL.revokeObjectURL(state.activeUrl);
        state.activeUrl = null;
      }
      if (state.currentUtterance) {
        state.currentUtterance.onend = null;
        state.currentUtterance.onerror = null;
        state.currentUtterance = null;
      }
    } else {
      abortAndResetPlayback();
    }
    state.playbackId++;
    state.pendingIndex = index;
    state.currentIndex = index;
    setPlayPauseUI(true);
    state.isPaused = false;

    const textToSpeak = state.sentences[index];
    const voiceChoice = voiceForSentence(textToSpeak);

    if (state.synchronized && !isHebrew(textToSpeak)) {
      let text = '';
      const segments = [];
      for (let i = index; i < state.sentences.length; i++) {
        const sentence = state.sentences[i];
        if (isHebrew(sentence) || (text.length && text.length + sentence.length > 2500)) break;
        if (text) text += ' ';
        segments.push({index:i,start:text.length});
        text += sentence;
      }
      state.connectedSegments = segments;
      highlightSentence(index);
      const syncVoice = voiceChoice.startsWith('apple-') ? voiceChoice : 'apple-evan';
      speakAppleVoice(text, syncVoice);
      return;
    }

    // For Apple local voices, highlight immediately; for network AI voices (Edge/Eleven/Google),
    // highlight when audio playback begins (onSpeechStart) to prevent desync!
    if (voiceChoice.startsWith('apple-') || !window.webkit || !window.webkit.messageHandlers) {
      state.currentIndex = index;
      highlightSentence(index);
    } else {
      const he = isHebrew(textToSpeak);
      dom.langTag.textContent = he ? 'HE' : 'EN';
      dom.langTag.className = 'lang-tag' + (he ? ' hebrew' : '');
      const counter = `[${index + 1}/${state.sentences.length}]`;
      dom.previewText.innerHTML = `<span style="color:var(--accent-lime);font-weight:700;margin-right:5px;">${counter}</span> ${escapeHtml(textToSpeak)}`;
      dom.previewText.className = 'preview-text' + (he ? ' rtl' : '');
    }

    // Send command to native speech engine or local Kokoro/RoboShaul server
    if (voiceChoice.startsWith('af_') || voiceChoice.startsWith('am_') || voiceChoice.startsWith('edge-') || voiceChoice === 'he-roboshaul' || voiceChoice.includes('roboshaul')) {
      state.currentIndex = index;
      highlightSentence(index);
      speakKokoroVoice(textToSpeak, voiceChoice, null, index);
    } else if (voiceChoice.startsWith('apple-')) {
      speakAppleVoice(textToSpeak, voiceChoice);
    } else if (voiceChoice.startsWith('eleven-')) {
      speakElevenVoice(textToSpeak, voiceChoice);
    } else if (voiceChoice.startsWith('google-')) {
      speakGoogleVoice(textToSpeak, voiceChoice);
    } else {
      speakKokoroVoice(textToSpeak, 'af_sarah', null, index);
    }
  }

  function voiceForSentence(text) {
    const selected = state.voice;
    if (isHebrew(text)) return isHebrewVoice(selected) ? selected : state.voiceHe;
    if (state.language === 'he') {
      const enChars = (text.match(/[a-zA-Z]/g) || []).length;
      if (enChars >= 3) return isHebrewVoice(selected) ? state.voiceEn : selected;
      return isHebrewVoice(selected) ? selected : state.voiceHe;
    }
    return isHebrewVoice(selected) ? state.voiceEn : selected;
  }

  async function requestAudio(text, voice, generation) {
    const controller = new AbortController();
    state.requests.add(controller);
    try {
      const res = await fetch('http://127.0.0.1:5050/synthesize', {
        method: 'POST', signal: controller.signal,
        headers: { 'Content-Type': 'application/json' },
        // Generate at normal speed; the player applies speed exactly once.
        body: JSON.stringify({ text, voice, speed: 1.0 })
      });
      if (!res.ok) throw new Error(`Speech synthesis failed: HTTP ${res.status}`);
      const blob = await res.blob();
      if (generation !== state.generation) return null;
      return URL.createObjectURL(blob);
    } finally {
      state.requests.delete(controller);
    }
  }

  // Next-sentence pre-buffering, owned by the current passage/settings generation.
  async function prebufferNextSentence(index) {
    if (index < 0 || index >= state.sentences.length || state.prebufferCache.has(index)) return;
    const text = state.sentences[index];
    const voice = voiceForSentence(text);
    if (!/^(af_|am_|edge-|he-roboshaul|roboshaul)/.test(voice)) return;
    const generation = state.generation;
    try {
      const url = await requestAudio(text, voice, generation);
      if (url && generation === state.generation) {
        const previous = state.prebufferCache.get(index);
        if (previous) URL.revokeObjectURL(previous);
        state.prebufferCache.set(index, url);

        // Chain prebuffering: buffer subsequent sentence as soon as current prebuffer completes
        if (index + 1 < state.sentences.length && !state.prebufferCache.has(index + 1)) {
          prebufferNextSentence(index + 1);
        }
      }
    } catch (_) { /* Playback will retry or use the installed voice. */ }
  }

  function playOwnedAudio(url, text, playbackId, onEnded, sentenceIndex, voiceChoice) {
    if (playbackId !== state.playbackId) { URL.revokeObjectURL(url); return; }
    state.backend = 'audio';
    const audio = new Audio(url);
    // Explicit assignment also supports native WebKit and the deterministic audio adapter.
    audio.src = url;
    state.audioElement = audio;
    state.activeUrl = url;
    audio.playbackRate = state.speed;
    audio.onplay = () => {
      if (playbackId !== state.playbackId || state.isPaused) { audio.pause(); return; }
      if (typeof sentenceIndex === 'number') highlightSentence(sentenceIndex);
    };
    audio.onended = () => {
      if (playbackId !== state.playbackId) return;
      if (onEnded) onEnded();
      else onSentenceFinished();
    };
    audio.onerror = () => {
      if (playbackId !== state.playbackId) return;
      stopCurrentAudio();
      if (!state.isPaused) {
        if (voiceChoice && voiceChoice.startsWith('edge-')) {
          speakEdgeVoice(text, voiceChoice);
        } else if (isHebrew(text)) {
          speakEdgeVoice(text, state.voiceHe || 'edge-he-avri');
        } else if (voiceChoice && voiceChoice.startsWith('apple-')) {
          speakAppleVoice(text, voiceChoice);
        } else {
          speakEdgeVoice(text, 'edge-en-jenny');
        }
      }
    };
    if (!state.isPaused) audio.play().catch(() => {
      if (playbackId !== state.playbackId) return;
      state.isPaused = true;
      setPlayPauseUI(false);
    });
    if (typeof sentenceIndex === 'number') {
      prebufferNextSentence(sentenceIndex + 1);
      prebufferNextSentence(sentenceIndex + 2);
    }
  }

  async function speakKokoroVoice(text, voiceChoice, onEnded, sentenceIndex) {
    const generation = state.generation, playbackId = state.playbackId;
    try {
      let url = state.prebufferCache.get(sentenceIndex);
      state.prebufferCache.delete(sentenceIndex);
      if (!url) url = await requestAudio(text, voiceChoice || 'af_sarah', generation);
      if (!url) return;
      playOwnedAudio(url, text, playbackId, onEnded, sentenceIndex, voiceChoice);
    } catch (err) {
      if (generation !== state.generation || playbackId !== state.playbackId) return;
      console.warn('[GuyReader] Local synthesis unavailable; using fallback:', err);
      if (!state.isPaused) {
        if (voiceChoice && voiceChoice.startsWith('edge-')) {
          speakEdgeVoice(text, voiceChoice);
        } else if (isHebrew(text)) {
          speakEdgeVoice(text, state.voiceHe || 'edge-he-avri');
        } else if (voiceChoice && voiceChoice.startsWith('apple-')) {
          speakAppleVoice(text, voiceChoice);
        } else {
          speakEdgeVoice(text, 'edge-en-jenny');
        }
      }
    }
  }

  async function testVoice(voice, hebrew) {
    abortAndResetPlayback();
    const sampleText = hebrew ? 'שלום! זוהי בדיקת הקראה בעברית.' : 'Hello! This is Guy Reader.';
    if (dom.previewSampleText) dom.previewSampleText.textContent = sampleText;
    if (dom.previewStatus) dom.previewStatus.textContent = 'Speaking...';
    updateEqualizer(true);
    state.previewFinish = () => {
      stopCurrentAudio();
      state.previewFinish = null;
      if (dom.previewStatus) dom.previewStatus.textContent = 'Ready';
      updateEqualizer(false);
    };
    if (voice.startsWith('apple-')) speakAppleVoice(sampleText, voice);
    else await speakKokoroVoice(sampleText, voice, state.previewFinish);
  }

  // Engine 1: Apple Local Voices (Evan Enhanced for US, Native Speech)
  function speakAppleVoice(text, voiceChoice) {
    state.backend = 'native';
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.speech) {
      window.webkit.messageHandlers.speech.postMessage({
        action: 'speak',
        requestId: state.playbackId,
        text: text,
        voice: voiceChoice,
        rate: state.speed
      });
      return;
    }

    // Web Speech Fallback
    window.speechSynthesis.cancel();
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.rate = state.speed;

    const voices = window.speechSynthesis.getVoices();
    const he = isHebrew(text);
    if (he) {
      console.warn('[GuyReader] Web Speech Hebrew (Carmit) is disabled.');
      if (dom.previewText) dom.previewText.textContent = 'Hebrew neural voice unavailable. Please ensure Guy Reader daemon is running.';
      return;
    }
    utterance.lang = 'en-US';
    const matching = voices.filter(v => v.lang.startsWith('en'));
    const voice = matching.find(v => v.name.includes('Evan')) || matching[0];
    if (voice) utterance.voice = voice;
    const playbackId = state.playbackId;
    utterance.onend = () => {
      if (playbackId !== state.playbackId) return;
      if (state.previewFinish) state.previewFinish();
      else onSentenceFinished();
    };
    utterance.onerror = () => {
      if (playbackId !== state.playbackId) return;
      stopSpeech();
      dom.previewText.textContent = 'Speech unavailable. Check installed voices in macOS settings.';
    };

    state.currentUtterance = utterance;
    window.speechSynthesis.speak(utterance);
  }

  // Engine 2: Microsoft Edge Neural TTS (Avri, Hila, Jenny, Guy) - Free & Ultra-Natural
  function speakEdgeVoice(text, voiceChoice) {
    state.backend = 'native';
    notifyNative('speakEdge', {
      requestId: state.playbackId,
      text: text,
      voice: voiceChoice,
      rate: state.speed,
      index: state.currentIndex
    });
  }

  // Engine 3: ElevenLabs Multilingual v2
  function speakElevenVoice(text, voiceChoice) {
    state.backend = 'native';
    const key = state.apiKeys.eleven;
    if (!key) {
      alert('ElevenLabs API key is missing. Please click ⚙ to enter your free ElevenLabs API key, or use Microsoft Edge Natural voices for free.');
      const fb = isHebrew(text) ? 'edge-he-avri' : 'apple-evan';
      dom.voiceSelect.value = fb;
      state.voice = fb;
      playSentence(state.currentIndex >= 0 ? state.currentIndex : 0);
      return;
    }

    const voiceIds = {
      'eleven-rachel': '21m00Tcm4TlvDq8ikWAM',
      'eleven-adam': 'pNInz6obpgDQGcFmaJgB',
      'eleven-charlie': 'IKne3meq5aSn9XLyUdCD'
    };
    const voiceId = voiceIds[voiceChoice] || '21m00Tcm4TlvDq8ikWAM';

    notifyNative('elevenTTS', { requestId: state.playbackId, text, voiceId, key, rate: state.speed });
  }

  // Engine 4: Google Cloud TTS
  function speakGoogleVoice(text, voiceChoice) {
    state.backend = 'native';
    const key = state.apiKeys.google;
    if (!key) {
      alert('Google Cloud TTS API key is missing. Please click ⚙ to add your key or use free Microsoft Edge Natural voices.');
      const fb = isHebrew(text) ? 'edge-he-avri' : 'apple-evan';
      dom.voiceSelect.value = fb;
      state.voice = fb;
      playSentence(state.currentIndex >= 0 ? state.currentIndex : 0);
      return;
    }
    notifyNative('googleTTS', { requestId: state.playbackId, text, voice: voiceChoice, key, rate: state.speed });
  }

  function onSentenceFinished() {
    if (!state.isPlaying) return;
    if (state.connectedSegments) {
      state.currentIndex = state.connectedSegments.at(-1).index;
      state.connectedSegments = null;
    }
    if (state.currentIndex + 1 < state.sentences.length) {
      playSentence(state.currentIndex + 1, true);
    } else {
      stopSpeech();
      state.currentIndex = 0; // Rewind to start so pressing play re-reads from sentence 0
      highlightSentence(0);
      setPlayPauseUI(false);
    }
  }

  function pauseSpeech() {
    state.isPaused = true;
    setPlayPauseUI(false);
    if (window.speechSynthesis && window.speechSynthesis.speaking) {
      window.speechSynthesis.pause();
    }
    if (state.audioElement && !state.audioElement.paused) {
      state.audioElement.pause();
    }
    notifyNative('pause');
  }

  function resumeSpeech() {
    if (state.browserActive) {
      state.isPaused = false; setPlayPauseUI(true); notifyNative('resume'); return;
    }
    if (state.isPaused && state.currentIndex >= 0) {
      state.isPaused = false;
      setPlayPauseUI(true);
      if (state.audioElement && state.audioElement.src) {
        state.audioElement.play().catch(console.warn);
      } else if (state.backend === 'native' && window.webkit) {
        notifyNative('resume');
      } else if (window.speechSynthesis && window.speechSynthesis.paused) {
        window.speechSynthesis.resume();
      } else {
        // Restart pending synthesis too; never resume an obsolete native request.
        playSentence(state.currentIndex);
      }
    } else if (state.sentences.length > 0) {
      playSentence(state.currentIndex >= 0 ? state.currentIndex : 0);
    } else {
      triggerReadSelection();
    }
  }

  function clearPrebufferCache() {
    if (state.prebufferCache) {
      for (const url of state.prebufferCache.values()) {
        try { URL.revokeObjectURL(url); } catch (e) {}
      }
      state.prebufferCache.clear();
    }
  }

  function stopCurrentAudio(notify = true) {
    state.playbackId++;
    if (state.audioElement) {
      state.audioElement.onended = null;
      state.audioElement.onerror = null;
      state.audioElement.onplay = null;
      state.audioElement.pause();
      state.audioElement.removeAttribute('src');
      state.audioElement.load();
    }
    if (state.activeUrl) URL.revokeObjectURL(state.activeUrl);
    state.activeUrl = null;
    if (state.currentUtterance) {
      state.currentUtterance.onend = null;
      state.currentUtterance.onerror = null;
      state.currentUtterance = null;
    }
    if (window.speechSynthesis) window.speechSynthesis.cancel();
    dom.sentencesList.querySelectorAll('.sentence-item').forEach((item, idx) => {
      if (state.sentences[idx] !== undefined) item.textContent = state.sentences[idx];
    });
    if (notify) notifyNative('stop');
  }

  function abortAndResetPlayback(notify = true) {
    state.generation++;
    stopCurrentAudio(notify);
    state.backend = null;
    state.connectedSegments = null;
    state.browserActive = false;
    for (const request of state.requests) request.abort();
    state.requests.clear();
    clearPrebufferCache();
    state.currentIndex = -1;
    state.pendingIndex = -1;
    state.previewFinish = null;
    state.isPlaying = false;
    state.isPaused = false;
    setPlayPauseUI(false);
  }

  function stopSpeech() {
    abortAndResetPlayback();
  }

  function triggerReadSelection() {
    notifyNative('readSelection');
  }

  function checkEvanBanner() {
    // Voice settings helper is placed inside the Settings modal (⚙)
  }

  // Toggle Drawer Height (Readest view)
  function toggleDrawer(open) {
    state.drawerOpen = (open !== undefined) ? open : !state.drawerOpen;
    dom.drawer.style.display = state.drawerOpen ? 'flex' : 'none';
    dom.btnToggleDrawer.classList.toggle('open', state.drawerOpen);

    const targetHeight = state.drawerOpen ? userExpandedHeight : userCompactHeight;
    notifyNative('resizeWindow', { height: targetHeight, width: userWidth });

    if (state.drawerOpen && state.currentIndex >= 0) {
      setTimeout(() => {
        const activeEl = dom.sentencesList.querySelector('.sentence-item.active');
        if (activeEl) {
          activeEl.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }
      }, 60);
    }
  }

  // Interactive Window Resizing in Both States (Compact & Expanded)
  function setupResizeHandle(handleEl, isCorner) {
    if (!handleEl) return;
    handleEl.addEventListener('mousedown', (e) => {
      e.preventDefault();
      e.stopPropagation();
      let lastX = e.screenX;
      let lastY = e.screenY;

      function onMouseMove(ev) {
        const dw = ev.screenX - lastX;
        const dh = isCorner ? (ev.screenY - lastY) : 0;
        lastX = ev.screenX;
        lastY = ev.screenY;
        userWidth = Math.max(360, Math.min(1200, userWidth + dw));
        if (isCorner) {
          if (state.drawerOpen) {
            userExpandedHeight = Math.max(160, Math.min(900, userExpandedHeight + dh));
          } else {
            userCompactHeight = Math.max(48, Math.min(140, userCompactHeight + dh));
          }
        }
        notifyNative('resizeWindowDelta', { dw, dh });
      }

      function onMouseUp() {
        window.removeEventListener('mousemove', onMouseMove);
        window.removeEventListener('mouseup', onMouseUp);
      }

      window.addEventListener('mousemove', onMouseMove);
      window.addEventListener('mouseup', onMouseUp);
    });
  }

  setupResizeHandle(dom.resizeHandleRight, false);
  setupResizeHandle(dom.resizeHandleCorner, true);

  // Event Listeners
  if (dom.btnStop) dom.btnStop.addEventListener('click', stopSpeech);
  if (dom.synchronizedMode) {
    dom.synchronizedMode.checked = state.synchronized;
    dom.synchronizedMode.addEventListener('change', e => {
      state.synchronized = e.target.checked;
      localStorage.setItem('guy_reader_sync', String(state.synchronized));
      if (state.isPlaying || state.isPaused) playSentence(Math.max(0, state.currentIndex));
    });
  }
  dom.btnSpeedDown.addEventListener('click', () => setSpeed(state.speed - 0.1));
  dom.btnSpeedUp.addEventListener('click', () => setSpeed(state.speed + 0.1));
  dom.speedSlider.addEventListener('input', (e) => setSpeed(parseFloat(e.target.value)));

  dom.btnPlayPause.addEventListener('click', () => {
    if (state.isPlaying) {
      pauseSpeech();
    } else if (state.isPaused) {
      resumeSpeech();
    } else {
      notifyNative('playButtonClicked');
    }
  });

  // Window Dragging System (Smooth, responsive floating window movement)
  let isWindowDragging = false;
  let dragStartScreenX = 0;
  let dragStartScreenY = 0;
  let hasWindowMoved = false;

  function onWindowDragStart(e) {
    if (isWindowDragging) return;
    if (e.button !== 0) return; // Left mouse button only

    // Exclude interactive elements from initiating drag
    if (e.target.closest('button, input, select, textarea, .resize-handle, .hotkey-badge, .speed-pill-group, .sentence-item, .modal-content, .reader-content, a')) {
      return;
    }

    isWindowDragging = true;
    hasWindowMoved = false;
    dragStartScreenX = e.screenX;
    dragStartScreenY = e.screenY;

    document.body.classList.add('is-window-dragging');

    const targetEl = e.currentTarget || e.target;
    if (e.pointerId !== undefined && targetEl && targetEl.setPointerCapture) {
      try {
        targetEl.setPointerCapture(e.pointerId);
      } catch (err) {}
    }

    function onWindowDragMove(ev) {
      if (!isWindowDragging) return;
      const dx = ev.screenX - dragStartScreenX;
      const dy = ev.screenY - dragStartScreenY;

      if (Math.abs(dx) >= 1 || Math.abs(dy) >= 1) {
        hasWindowMoved = true;
        dragStartScreenX = ev.screenX;
        dragStartScreenY = ev.screenY;
        notifyNative('moveWindowDelta', { dx, dy });
      }
    }

    function onWindowDragEnd(ev) {
      if (!isWindowDragging) return;
      isWindowDragging = false;
      document.body.classList.remove('is-window-dragging');

      if (ev && ev.pointerId !== undefined && targetEl && targetEl.releasePointerCapture) {
        try {
          targetEl.releasePointerCapture(ev.pointerId);
        } catch (err) {}
      }

      window.removeEventListener('pointermove', onWindowDragMove);
      window.removeEventListener('pointerup', onWindowDragEnd);
      window.removeEventListener('pointercancel', onWindowDragEnd);
      window.removeEventListener('mousemove', onWindowDragMove);
      window.removeEventListener('mouseup', onWindowDragEnd);

      setTimeout(() => {
        hasWindowMoved = false;
      }, 150);
    }

    window.addEventListener('pointermove', onWindowDragMove);
    window.addEventListener('pointerup', onWindowDragEnd);
    window.addEventListener('pointercancel', onWindowDragEnd);
    window.addEventListener('mousemove', onWindowDragMove);
    window.addEventListener('mouseup', onWindowDragEnd);
  }

  // Bind drag listener to draggable areas
  const pillBar = document.getElementById('pillBar');
  if (pillBar) {
    pillBar.addEventListener('pointerdown', onWindowDragStart);
    pillBar.addEventListener('mousedown', onWindowDragStart);
  }
  if (dom.dragZone) {
    dom.dragZone.addEventListener('pointerdown', onWindowDragStart);
    dom.dragZone.addEventListener('mousedown', onWindowDragStart);
  }
  const drawerHeader = document.querySelector('.drawer-header');
  if (drawerHeader) {
    drawerHeader.addEventListener('pointerdown', onWindowDragStart);
    drawerHeader.addEventListener('mousedown', onWindowDragStart);
  }

  dom.btnReadSelection.addEventListener('click', triggerReadSelection);
  if (dom.btnPillPaste) {
    dom.btnPillPaste.addEventListener('click', () => {
      notifyNative('pasteClipboard');
    });
  }
  dom.previewZone.addEventListener('click', () => {
    if (hasWindowMoved) {
      hasWindowMoved = false;
      return;
    }
    toggleDrawer(!state.drawerOpen);
  });
  dom.btnToggleDrawer.addEventListener('click', () => toggleDrawer(!state.drawerOpen));

  if (dom.btnMinimize) {
    dom.btnMinimize.addEventListener('click', (e) => {
      e.stopPropagation();
      pauseSpeech();
      notifyNative('minimize');
    });
  }

  if (dom.btnExit) {
    dom.btnExit.addEventListener('click', (e) => {
      e.stopPropagation();
      stopSpeech();
      notifyNative('exit');
    });
  }

  dom.voiceSelect.addEventListener('change', (e) => {
    state.voice = e.target.value;
    if (isHebrewVoice(state.voice)) {
      state.voiceHe = state.voice;
      localStorage.setItem('guy_reader_voice_he', state.voiceHe);
    } else {
      state.voiceEn = state.voice;
      localStorage.setItem('guy_reader_voice_en', state.voiceEn);
    }
    localStorage.setItem('guy_reader_voice', state.voice);
    localStorage.setItem('glaido_voice', state.voice);
    if (!state.voice.startsWith('apple-')) {
      state.synchronized = false;
      localStorage.setItem('guy_reader_sync', 'false');
      if (dom.synchronizedMode) dom.synchronizedMode.checked = false;
    }
    checkEvanBanner();
    clearPrebufferCache();
    notifyNative('voiceChanged', { voice: state.voice });
    // Immediately switch speech output without restarting
    if (state.isPlaying || state.isPaused) {
      playSentence(state.currentIndex >= 0 ? state.currentIndex : 0);
    } else {
      abortAndResetPlayback();
    }
  });

  dom.btnPasteText.addEventListener('click', () => {
    notifyNative('pasteClipboard');
  });

  if (dom.btnEmptyPaste) {
    dom.btnEmptyPaste.addEventListener('click', () => {
      notifyNative('pasteClipboard');
    });
  }

  if (dom.btnReadManualText) {
    dom.btnReadManualText.addEventListener('click', () => {
      const txt = dom.manualTextInput ? dom.manualTextInput.value.trim() : '';
      if (txt) {
        loadText(txt, true);
      }
    });
  }

  if (dom.btnEditText) {
    dom.btnEditText.addEventListener('click', () => {
      stopSpeech();
      if (!state.drawerOpen) {
        toggleDrawer(true);
      }
      dom.emptyState.style.display = 'block';
      dom.sentencesList.style.display = 'none';
      if (dom.manualTextInput) {
        dom.manualTextInput.value = state.text || '';
        dom.manualTextInput.focus();
        dom.manualTextInput.select();
      }
    });
  }

  dom.btnClearText.addEventListener('click', () => {
    stopSpeech();
    state.sentences = [];
    state.text = '';
    notifyNative('textLoaded', { text: '' });
    state.currentIndex = -1;
    renderSentences();
    if (dom.manualTextInput) {
      dom.manualTextInput.value = '';
      dom.manualTextInput.focus();
    }
    dom.previewText.textContent = 'Cleared. Highlight text or enter text below';
    dom.previewText.className = 'preview-text';
  });

  function openSettingsModal() {
    if (dom.settingsVoiceEn) dom.settingsVoiceEn.value = state.voiceEn;
    if (dom.settingsVoiceHe) dom.settingsVoiceHe.value = state.voiceHe;
    if (dom.settingsSpeedSlider) dom.settingsSpeedSlider.value = state.speed;
    if (dom.settingsSpeedVal) dom.settingsSpeedVal.textContent = formatSpeed(state.speed);
    if (dom.synchronizedMode) dom.synchronizedMode.checked = state.synchronized;
    if (dom.elevenApiKey) dom.elevenApiKey.value = state.apiKeys.eleven;
    if (dom.googleApiKey) dom.googleApiKey.value = state.apiKeys.google;
    if (dom.previewStatus) dom.previewStatus.textContent = 'Ready';

    // Expand window so settings modal fits completely without clipping
    notifyNative('resizeWindow', { height: 460, width: 480 });
    dom.settingsModal.style.display = 'flex';
  }

  function closeSettingsModal() {
    dom.settingsModal.style.display = 'none';
    const targetHeight = state.drawerOpen ? userExpandedHeight : userCompactHeight;
    notifyNative('resizeWindow', { height: targetHeight, width: userWidth });
  }

  if (dom.btnPillSettings) {
    dom.btnPillSettings.addEventListener('click', openSettingsModal);
  }
  if (dom.btnSettings) {
    dom.btnSettings.addEventListener('click', openSettingsModal);
  }

  dom.btnCloseSettings.addEventListener('click', (e) => {
    e.stopPropagation();
    closeSettingsModal();
  });

  if (dom.btnTestVoiceEn) {
    dom.btnTestVoiceEn.addEventListener('click', () => {
      const v = dom.settingsVoiceEn ? dom.settingsVoiceEn.value : state.voiceEn;
      testVoice(v, false);
    });
  }

  if (dom.btnTestVoiceHe) {
    dom.btnTestVoiceHe.addEventListener('click', () => {
      const v = dom.settingsVoiceHe ? dom.settingsVoiceHe.value : state.voiceHe;
      testVoice(v, true);
    });
  }

  if (dom.btnSettingsSpeedDown) {
    dom.btnSettingsSpeedDown.addEventListener('click', () => {
      setSpeed(state.speed - 0.1);
    });
  }

  if (dom.btnSettingsSpeedUp) {
    dom.btnSettingsSpeedUp.addEventListener('click', () => {
      setSpeed(state.speed + 0.1);
    });
  }

  if (dom.settingsSpeedSlider) {
    dom.settingsSpeedSlider.addEventListener('input', (e) => {
      setSpeed(parseFloat(e.target.value));
    });
  }

  if (dom.btnResetSettings) {
    dom.btnResetSettings.addEventListener('click', () => {
      state.voiceEn = 'af_sarah';
      state.voiceHe = 'edge-he-avri';
      state.synchronized = false;
      localStorage.setItem('guy_reader_sync', 'false');
      if (dom.synchronizedMode) dom.synchronizedMode.checked = false;
      setSpeed(1.0);
      if (dom.settingsVoiceEn) dom.settingsVoiceEn.value = state.voiceEn;
      if (dom.settingsVoiceHe) dom.settingsVoiceHe.value = state.voiceHe;
      if (dom.elevenApiKey) dom.elevenApiKey.value = '';
      if (dom.googleApiKey) dom.googleApiKey.value = '';
    });
  }

  dom.btnSaveSettings.addEventListener('click', () => {
    if (dom.settingsVoiceEn) state.voiceEn = dom.settingsVoiceEn.value;
    if (dom.settingsVoiceHe) state.voiceHe = dom.settingsVoiceHe.value;
    if (dom.synchronizedMode) state.synchronized = dom.synchronizedMode.checked;
    if (dom.elevenApiKey) state.apiKeys.eleven = dom.elevenApiKey.value.trim();
    if (dom.googleApiKey) state.apiKeys.google = dom.googleApiKey.value.trim();

    localStorage.setItem('guy_reader_voice_en', state.voiceEn);
    localStorage.setItem('guy_reader_voice_he', state.voiceHe);
    localStorage.setItem('guy_reader_sync', String(state.synchronized));
    localStorage.setItem('guy_reader_speed', state.speed);
    localStorage.setItem('guy_reader_eleven_key', state.apiKeys.eleven);
    localStorage.setItem('guy_reader_google_key', state.apiKeys.google);

    // Update active voice based on current language
    state.voice = (state.language === 'he') ? state.voiceHe : state.voiceEn;
    dom.voiceSelect.value = state.voice;
    localStorage.setItem('guy_reader_voice', state.voice);
    if (!state.voice.startsWith('apple-')) {
      state.synchronized = false;
      localStorage.setItem('guy_reader_sync', 'false');
      if (dom.synchronizedMode) dom.synchronizedMode.checked = false;
    }

    clearPrebufferCache();
    notifyNative('voiceChanged', { voice: state.voice });
    notifyNative('saveKeys', state.apiKeys);

    if (state.isPlaying || state.isPaused) playSentence(Math.max(0, state.currentIndex));
    else abortAndResetPlayback();
    closeSettingsModal();
  });

  // Global Keyboard Shortcuts (inside webview)
  window.addEventListener('keydown', (e) => {
    if (e.code === 'Space' && e.target.tagName !== 'INPUT' && e.target.tagName !== 'TEXTAREA') {
      e.preventDefault();
      if (state.isPlaying) pauseSpeech();
      else resumeSpeech();
    }
  });

  // Bridge APIs exposed to Native Cocoa Host
  window.guyReaderApp = window.glaidoApp = {
    receiveText: (text) => {
      loadText(text, true);
    },
    browserState: status => {
      if (!state.browserActive) return;
      state.isPaused = status.paused;
      setPlayPauseUI(status.playing);
      if (!status.playing && !status.paused) {
        state.browserActive = false;
        dom.previewText.textContent = 'Browser reading finished. Click text, then Read.';
      }
    },
    browserStarted: () => {
      abortAndResetPlayback(false);
      state.browserActive = true;
      dom.previewText.textContent = 'Reading in your browser · follow the highlighted word';
      setPlayPauseUI(true);
    },
    prepareBrowserRead: () => abortAndResetPlayback(false),
    onWordBoundary: (requestId, location, length) => {
      if (requestId !== state.playbackId || !state.connectedSegments || state.isPaused) return;
      const segment = [...state.connectedSegments].reverse().find(s => s.start <= location);
      if (!segment) return;
      highlightSentence(segment.index);
      const sentence = state.sentences[segment.index], offset = location - segment.start;
      const html = escapeHtml(sentence.slice(0, offset)) + '<mark class="reader-current-word">' +
        escapeHtml(sentence.slice(offset, offset + length)) + '</mark>' + escapeHtml(sentence.slice(offset + length));
      const item = dom.sentencesList.querySelectorAll('.sentence-item')[segment.index];
      if (item) item.innerHTML = html;
    },
    onSentenceComplete: (requestId) => {
      if (requestId !== state.playbackId) return;
      if (state.previewFinish) state.previewFinish();
      else onSentenceFinished();
    },
    onSpeechStart: (requestId) => {
      if (requestId !== state.playbackId || state.isPaused) return;
      if (state.pendingIndex !== undefined && state.pendingIndex >= 0) {
        state.currentIndex = state.pendingIndex;
        highlightSentence(state.currentIndex);
        setPlayPauseUI(true);
      }
    },
    onNativePause: (requestId) => {
      if (requestId !== state.playbackId) return;
      state.isPaused = true;
      setPlayPauseUI(false);
    },
    playAudioUrl: (url) => {
      if (state.audioElement) {
        state.audioElement.src = url;
        state.audioElement.playbackRate = state.speed;
        state.audioElement.play().catch(console.warn);
        state.audioElement.onended = () => onSentenceFinished();
      }
    },
    togglePlayPause: () => {
      if (state.isPlaying) pauseSpeech();
      else resumeSpeech();
    },
    setSpeedValue: (val) => {
      setSpeed(val);
    },
    showHint: (msg) => {
      dom.previewText.textContent = msg;
      dom.previewText.style.color = '#F59E0B';
      setTimeout(() => {
        dom.previewText.style.color = '';
        if (!state.isPlaying && state.sentences.length === 0) {
          dom.previewText.textContent = 'Ready. Click Read or Paste to begin';
        }
      }, 4000);
    }
  };

  // Initialization
  setSpeed(state.speed);
  dom.voiceSelect.value = state.voice;
  checkEvanBanner();
  notifyNative('voiceChanged', { voice: state.voice });

  // Load voices for Web Speech
  if ('speechSynthesis' in window) {
    window.speechSynthesis.onvoiceschanged = () => {
      checkEvanBanner();
    };
  }
})();
