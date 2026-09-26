// Guy_reader - In-Page Reader Content Script (Manifest V3)

(function () {
  if (window.__guyReaderInitialized) return;
  window.__guyReaderInitialized = true;

  // Local Speech Engine URL
  const SPEECH_ENGINE_URL = 'http://127.0.0.1:5050';

  // Reader State
  const state = {
    isActive: false,
    isPlaying: false,
    isPaused: false,
    speed: 1.0,
    voice: 'af_sarah', // Default to Kokoro Sarah for English
    sentences: [],
    currentIndex: -1,
    audioElement: null,
    currentSpeechUtterance: null,
    sequenceId: 0,
    pillEl: null,
    wordTimer: null,
    synchronized: false,
    generation: 0,
    prefetch: new Map(),
    lastPoint: null,
    wordOffset: 0,
    lastReportedState: '',
    engineAvailable: false, // Will be set after health check
    cleanReaderMode: false,
    cleanReaderOriginal: null, // Stashed original DOM for toggle-back
  };

  chrome.storage?.local.get({guy_reader_sync:false,guy_reader_voice:'af_sarah'}, prefs => {
    state.synchronized = prefs.guy_reader_sync;
    state.voice = prefs.guy_reader_voice;
  });

  // 1. Sentence Splitting Helper
  function splitIntoSentences(text) {
    if (!text || !text.trim()) return [];
    text = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');

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
      'st', 'ave', 'blvd', 'dept', 'no', 'fig', 'vol', 'al',
      'jan', 'feb', 'mar', 'apr', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'
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

    const regex = /([^.!?\n׃]+(?:[.!?׃]+['"”’\)\]]*|(?=[\n]|$))|[^.!?\n׃]+$)/g;
    const matches = text.match(regex) || [text];

    return matches
      .map(s => s.replace(/\uE000/g, '.').replace(/\uE001/g, '!').replace(/\uE002/g, '?').trim())
      .filter(s => s.length > 0 && /[\p{L}\p{N}]/u.test(s));
  }

  function isHebrew(text) {
    return /[\u0590-\u05FF]/.test(text);
  }

  function readableSource(root, junkSelectors) {
    let text = '';
    const segments = [];
    const blockTags = new Set(['P','DIV','LI','H1','H2','H3','H4','H5','H6','BLOCKQUOTE','SECTION','ARTICLE']);
    const appendSeparator = () => { if (text && !/\s$/u.test(text)) text += ' '; };
    const hidden = element => {
      if (!element) return false;
      if (element.closest?.(junkSelectors) || element.hidden || element.getAttribute?.('aria-hidden') === 'true') return true;
      if (typeof getComputedStyle === 'function') {
        const style = getComputedStyle(element);
        if (style?.display === 'none' || style?.visibility === 'hidden') return true;
      }
      return false;
    };
    const appendText = node => {
      if (hidden(node.parentElement)) return;
      const value = node.textContent || '';
      if (!value) return;
      const start = text.length;
      text += value;
      segments.push({node, textStart:start, textEnd:text.length});
    };
    const visit = node => {
      if (node.nodeType === 3) { appendText(node); return; }
      if (node !== root && hidden(node)) return;
      const tag = node.tagName?.toUpperCase?.();
      if (tag === 'BR') { appendSeparator(); return; }
      const block = node !== root && blockTags.has(tag);
      if (block) appendSeparator();
      for (const child of Array.from(node.childNodes || [])) visit(child);
      if (block) appendSeparator();
    };
    if (root.childNodes) visit(root);
    else {
      const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
      let node;
      while ((node = walker.nextNode())) appendText(node);
    }
    return {text, segments};
  }

  // Helper to expand truncated tweets/posts on X before extraction
  function expandXTruncatedContent(root = document) {
    try {
      const showMoreBtns = Array.from(root.querySelectorAll?.('[data-testid="tweet-text-show-more-link"], [data-testid="tweet-text-show-more"], [data-testid*="show-more"]') || []);
      for (const btn of showMoreBtns) {
        if (btn && typeof btn.click === 'function' && !btn.disabled) {
          btn.click();
        }
      }
      const allButtons = Array.from(root.querySelectorAll?.('button[data-testid*="show-more"], article button, button[role="button"]') || []);
      for (const btn of allButtons) {
        const t = (btn.innerText || btn.textContent || '').trim().toLowerCase();
        if ((t === 'show more' || t === 'הצג עוד' || t.includes('show more')) && typeof btn.click === 'function' && !btn.disabled) {
          btn.click();
        }
      }
    } catch (_) {}
  }

  // 2. Full Article DOM Extractor
  function extractArticleData() {
    const cleanOverlay = document.getElementById('guy-reader-clean-overlay');
    if (cleanOverlay) {
      const cleanParas = cleanOverlay.querySelectorAll('.guy-reader-clean-title, .guy-reader-clean-para');
      if (cleanParas && cleanParas.length > 0) {
        const sentences = [];
        for (const el of cleanParas) {
          const source = readableSource(el, '');
          const fullText = source.text;
          if (!fullText || fullText.length < 2) continue;
          const subSentences = splitIntoSentences(fullText);
          let searchFrom = 0;
          for (let s of subSentences) {
            const start = fullText.indexOf(s, searchFrom);
            if (start < 0) continue;
            searchFrom = start + s.length;
            sentences.push({
              start, end: searchFrom,
              text: s,
              element: el,
              originalText: fullText,
              source
            });
          }
        }
        if (sentences.length > 0) return sentences;
      }
    }

    const mainSelectors = '.available-content, .body.markup, article, [role="main"], main, .article-body, .post-content, .entry-content, #content, .story-body, .single-post, .post';
    const host = window.location?.hostname || '';
    const isX = host === 'x.com' || host.endsWith('.x.com') || host === 'twitter.com' || host.endsWith('.twitter.com');
    if (isX) {
      expandXTruncatedContent(document);
    }
    const pointNode = state.lastPoint?.node;
    const pointElement = pointNode?.nodeType === 1 ? pointNode : pointNode?.parentElement;
    const xSelector = '[data-testid="twitterArticleReadView"], [data-testid="twitterArticleRichTextView"], [data-testid="longformRichTextComponent"], article[data-testid="tweet"], article';
    let mainContainer = isX ? pointElement?.closest?.(xSelector) : null;
    if (!mainContainer && isX) {
      const candidates = Array.from(document.querySelectorAll(xSelector));
      mainContainer = candidates
        .filter(el => el.offsetParent !== null || el.offsetWidth > 0 || el.offsetHeight > 0)
        .sort((a,b) => (b.innerText || b.textContent || '').length - (a.innerText || a.textContent || '').length)[0];
    }
    if (!mainContainer) mainContainer = document.querySelector(mainSelectors);
    if (!mainContainer) mainContainer = document.body;
    if (isX && mainContainer) {
      expandXTruncatedContent(mainContainer);
    }

    const blockSelector = isX
      ? '[data-testid="tweetText"], [data-testid="longformRichTextComponent"] [class*="longform-"], [data-testid="twitterArticleReadView"] [class*="longform-"], [class*="longform-unstyled"], [class*="longform-header-"], [class*="longform-blockquote"], section[data-block="true"], p, h1, h2, h3, h4, blockquote, li'
      : 'p, h1, h2, h3, h4, blockquote, li';
    let blockElements = Array.from(mainContainer.querySelectorAll(blockSelector));
    if (isX && blockElements.length > 1) {
      blockElements = blockElements.filter(el => !blockElements.some(other => other !== el && el.contains(other)));
    }
    const sentences = [];

    const junkSelectors = 'nav, footer, aside, .nav, .menu, .sidebar, .comments, .ad, .advertisement, script, style, noscript, svg, [aria-hidden="true"], .timestamp, time, button, [role="tab"], [role="tablist"], [data-testid="ScrollSnap-List"]';

    for (let el of blockElements) {
      if (el.closest(junkSelectors)) continue;
      if (el.closest('#guy-reader-floating-pill')) continue;
      if (el.offsetParent === null && el.offsetWidth === 0 && el.offsetHeight === 0) continue;

      const source = readableSource(el, junkSelectors);
      const fullText = source.text;
      if (!fullText || fullText.length < 5) continue;
      if (isX && /^(Article|Conversation)$/iu.test(fullText.trim())) continue;

      const subSentences = splitIntoSentences(fullText);
      let searchFrom = 0;
      for (let s of subSentences) {
        const start = fullText.indexOf(s, searchFrom);
        if (start < 0) continue;
        searchFrom = start + s.length;
        sentences.push({
          start, end: searchFrom,
          text: s,
          element: el,
          originalText: fullText,
          source
        });
      }
    }

    // Fallback: If container returned nothing, scan all paragraphs in document
    if (sentences.length === 0 && mainContainer !== document.body && !isX) {
      const allParas = document.querySelectorAll('p, h1, h2, h3');
      for (let el of allParas) {
        if (el.closest(junkSelectors)) continue;
        if (el.closest('#guy-reader-floating-pill')) continue;
        const source = readableSource(el, junkSelectors);
        const fullText = source.text;
        if (fullText.length > 10 && /[\p{L}\p{N}]/u.test(fullText)) {
          const subSentences = splitIntoSentences(fullText);
          let searchFrom = 0;
          for (let s of subSentences) {
            const start = fullText.indexOf(s, searchFrom);
            if (start < 0) continue;
            searchFrom = start + s.length;
            sentences.push({
              start, end: searchFrom,
              text: s,
              element: el,
              originalText: fullText,
              source
            });
          }
        }
      }
    }

    return sentences;
  }

  // Check if local speech engine is running (routed via background.js to bypass webpage CSP)
  function checkLocalEngine() {
    try {
      chrome.runtime.sendMessage({ action: 'check-engine-health' }, (resp) => {
        if (chrome.runtime.lastError) {
          state.engineAvailable = false;
          return;
        }
        state.engineAvailable = !!(resp && resp.available);
        console.log('[GuyReader] Local engine:', state.engineAvailable ? 'available' : 'unavailable');
      });
    } catch (e) {
      state.engineAvailable = false;
      console.log('[GuyReader] Local engine not reachable, using Web Speech fallback');
    }
  }

  // Probe engine on load
  checkLocalEngine();

  // Find sentence index matching user selection
  function getSelectionSentenceIndex(sentences) {
    const sel = window.getSelection ? window.getSelection() : null;
    if (!sel || sel.rangeCount === 0 || sel.isCollapsed) return 0;

    const selectedText = sel.toString().trim();
    if (!selectedText) return 0;

    const anchorNode = sel.anchorNode;
    const anchorEl = anchorNode ? (anchorNode.nodeType === 1 ? anchorNode : anchorNode.parentElement) : null;

    // Check by DOM node match first
    if (anchorEl) {
      for (let i = 0; i < sentences.length; i++) {
        if (sentences[i].element === anchorEl || sentences[i].element.contains(anchorEl) || anchorEl.contains(sentences[i].element)) {
          return i;
        }
      }
    }

    // Fallback: match by substring
    const sample = selectedText.slice(0, 30);
    for (let i = 0; i < sentences.length; i++) {
      if (sentences[i].text.includes(sample) || sample.includes(sentences[i].text.slice(0, 20))) {
        return i;
      }
    }

    return 0;
  }

  // Ranges highlight the original DOM without wrapping, rewriting, or shifting text.
  function sourceRange(item, offset, length) {
    if (!item || !document.createRange) return null;
    const start = item.start + offset, end = start + length;
    const segments = item.source?.segments || [];
    const startSegment = segments.find(s => start >= s.textStart && start < s.textEnd) ||
      segments.find(s => s.textStart > start);
    const endSegment = [...segments].reverse().find(s => end > s.textStart && end <= s.textEnd) ||
      [...segments].reverse().find(s => s.textEnd < end);
    if (!startSegment || !endSegment) return null;
    const startOffset = Math.max(0, start - startSegment.textStart);
    const endOffset = Math.min(endSegment.node.textContent.length, end - endSegment.textStart);
    const range = document.createRange();
    range.setStart(startSegment.node, startOffset); range.setEnd(endSegment.node, endOffset);
    return range;
  }

  function paintRange(name, range) {
    if (typeof CSS !== 'undefined' && CSS.highlights && typeof Highlight !== 'undefined') {
      if (range) CSS.highlights.set(name, new Highlight(range));
      else CSS.highlights.delete(name);
    }
  }

  function clearOnPageHighlights() {
    paintRange('guy-reader-sentence', null);
    paintRange('guy-reader-word', null);
  }

  function highlightSentenceOnPage(index) {
    clearOnPageHighlights();
    const item = state.sentences[index];
    if (!item) return;
    paintRange('guy-reader-sentence', sourceRange(item, 0, item.text.length));
    const rect = item.element.getBoundingClientRect?.();
    if (rect && (rect.top < 0 || rect.bottom > window.innerHeight)) {
      item.element.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  }

  function highlightWordAt(characterIndex) {
    const item = state.sentences[state.currentIndex];
    if (!item) return;
    const words = [...item.text.matchAll(/\S+/gu)];
    const word = words.find(w => characterIndex >= w.index && characterIndex < w.index + w[0].length);
    if (word) {
      state.wordOffset = word.index;
      paintRange('guy-reader-word', sourceRange(item, word.index, word[0].length));
    }
  }

  function offsetInSource(source, node, offset) {
    const segment = source?.segments?.find(s => s.node === node);
    if (segment) return segment.textStart + Math.min(offset, segment.node.textContent.length);
    return -1;
  }

  function pointPosition(point) {
    if (!point) return null;
    let node = point.node, offset = point.offset;
    if (!node) {
      const caret = document.caretPositionFromPoint?.(point.x, point.y);
      const range = !caret && document.caretRangeFromPoint?.(point.x, point.y);
      node = caret?.offsetNode || range?.startContainer;
      offset = caret?.offset ?? range?.startOffset;
    }
    if (!node) return null;
    for (let i = 0; i < state.sentences.length; i++) {
      const item = state.sentences[i];
      if (!item.element.contains(node)) continue;
      const at = offsetInSource(item.source, node, offset);
      if (at >= item.start && at < item.end) {
        const relative = at - item.start;
        const word = [...item.text.matchAll(/\S+/gu)].find(w => relative < w.index + w[0].length);
        return { index: i, offset: word?.index || 0 };
      }
    }
    return null;
  }

  // Remember a reading origin even before playback starts. Ordinary page links still work.
  function setupClickToSeek() {
    document.addEventListener('click', e => {
      if (e.target.closest('#guy-reader-floating-pill, input, textarea, select, button, a, [contenteditable="true"]')) return;
      const caret = document.caretPositionFromPoint?.(e.clientX, e.clientY);
      const range = !caret && document.caretRangeFromPoint?.(e.clientX, e.clientY);
      chrome.runtime.sendMessage({action:'reader-focus'}, () => { void chrome.runtime.lastError; });
      state.lastPoint = {node: caret?.offsetNode || range?.startContainer,
        offset: caret?.offset ?? range?.startOffset, x:e.clientX, y:e.clientY};
      if (!state.isActive) return;
      const position = pointPosition(state.lastPoint);
      if (position) playSentence(position.index, false, position.offset);
    }, true);
  }

  // 5. Speech Playback Core
  function startReading(fromSelection = true) {
    stopReading();
    state.currentIndex = -1;
    state.sentences = extractArticleData();
    if (state.sentences.length === 0) {
      alert("Guy_reader: No readable article text found on this page.");
      return;
    }

    let startIndex = 0, startOffset = 0;
    if (fromSelection) {
      const selection = window.getSelection?.();
      const selected = selection && !selection.isCollapsed
        ? pointPosition({node:selection.anchorNode, offset:selection.anchorOffset}) : null;
      const point = selected || pointPosition(state.lastPoint);
      if (point) { startIndex = point.index; startOffset = point.offset; }
      else startIndex = getSelectionSentenceIndex(state.sentences);
    }

    // Auto-detect language and pick voice
    const sampleText = state.sentences[startIndex]?.text || '';
    const he = isHebrew(sampleText);
    if (he && !state.voice.includes('he-')) {
      state.voice = 'edge-he-avri';
    } else if (!he && state.voice.includes('he-')) {
      state.voice = 'af_sarah';
    }
    // Edge neural voices have a fixed identity but no word-boundary metadata.
    // Never replace a chosen Avri/Hila voice just to provide exact highlighting.
    if (state.voice.startsWith('edge-') && state.synchronized) {
      state.synchronized = false;
      chrome.storage?.local.set({guy_reader_sync:false});
      const mode = document.getElementById('guy-mode-select');
      if (mode) mode.value = 'neural';
    }

    state.isActive = true;
    showFloatingPill();
    updatePillUI();
    playSentence(startIndex, false, startOffset);
  }

  function stopReading() {
    state.isActive = false;
    state.isPlaying = false;
    state.isPaused = false;
    state.sequenceId++;
    state.generation++;
    state.prefetch.clear();
    stopCurrentAudioOnly();
    clearOnPageHighlights();
    updatePillUI();
  }

  function pauseReading() {
    state.isPaused = true;
    state.isPlaying = false;
    if (state.audioElement && !state.audioElement.paused) {
      state.audioElement.pause();
    }
    if ('speechSynthesis' in window && window.speechSynthesis.speaking) {
      window.speechSynthesis.pause();
    }
    if (state.wordTimer) {
      clearInterval(state.wordTimer);
      state.wordTimer = null;
    }
    updatePillUI();
  }

  function resumeReading() {
    if (state.isPaused && state.currentIndex >= 0) {
      state.isPaused = false;
      state.isPlaying = true;
      if (state.audioElement && state.audioElement.paused) {
        state.audioElement.play().catch(() => {});
      } else if ('speechSynthesis' in window && window.speechSynthesis.paused) {
        window.speechSynthesis.resume();
      } else {
        playSentence(state.currentIndex);
      }
      updatePillUI();
    } else if (state.sentences.length > 0) {
      playSentence(state.currentIndex >= 0 ? state.currentIndex : 0);
    } else {
      startReading(false);
    }
  }

  async function playSentence(index, continuous = false, offset = 0) {
    if (index < 0 || index >= state.sentences.length) {
      stopReading();
      return;
    }

    if (!continuous) { state.generation++; state.prefetch.clear(); }
    const mySeq = ++state.sequenceId;
    stopCurrentAudioOnly();
    state.currentIndex = index;
    state.isPlaying = true;
    state.isActive = true;
    state.isPaused = false;
    updatePillUI();

    const sentenceItem = state.sentences[index];
    state.wordOffset = offset;
    const textToSpeak = sentenceItem.text.slice(offset);
    const hebrewVoice = /he-|avri|hila|roboshaul|shaul/i.test(state.voice);
    const voice = isHebrew(textToSpeak)
      ? (hebrewVoice ? state.voice : 'edge-he-avri')
      : (hebrewVoice ? 'af_sarah' : state.voice);

    highlightSentenceOnPage(index);
    if (state.synchronized && !isHebrew(textToSpeak) && !voice.startsWith('edge-')) {
      speakConnectedPassage(index, offset, mySeq);
      return;
    }

    // Try local speech engine first (proxied via background.js to bypass webpage CSP)
    if (state.engineAvailable && !voice.startsWith('edge-')) {
      const localAudioDataUrl = await prefetchSentence(index, offset);

      if (state.sequenceId !== mySeq) return; // Stale

      if (localAudioDataUrl) {
        playAudioUrl(localAudioDataUrl, textToSpeak, mySeq, true, offset);
        prefetchSentence(index + 1);
        prefetchSentence(index + 2);
        return;
      }
    }

    // Direct local synthesis if voice is local (e.g. he-roboshaul or kokoro)
    if (state.engineAvailable && (!voice.startsWith('edge-') || voice.includes('roboshaul'))) {
      chrome.runtime.sendMessage({
        action: 'synthesize-local',
        text: textToSpeak,
        voice,
        speed: 1.0
      }, (localResp) => {
        if (state.sequenceId !== mySeq) return;
        if (localResp && localResp.success && localResp.audioDataUrl) {
          playAudioUrl(localResp.audioDataUrl, textToSpeak, mySeq, true, offset);
          prefetchSentence(index + 1);
          prefetchSentence(index + 2);
        } else if (isHebrew(textToSpeak)) {
          // Fallback to Edge Avri if local Hebrew engine fails
          chrome.runtime.sendMessage({
            action: 'synthesize-edge-tts',
            text: textToSpeak,
            voice: 'edge-he-avri',
            rate: 1.0
          }, (edgeResp) => {
            if (state.sequenceId !== mySeq) return;
            if (edgeResp && edgeResp.success && edgeResp.audioDataUrl) {
              playAudioUrl(edgeResp.audioDataUrl, textToSpeak, mySeq, false, offset);
            } else {
              console.warn('[GuyReader] Hebrew neural voice failed. Carmit fallback blocked.');
              onSentenceFinished();
            }
          });
        } else {
          speakWebSpeech(textToSpeak, mySeq, offset);
        }
      });
      return;
    }

    // Fallback: Edge TTS via background.js
    if (voice.startsWith('edge-') || isHebrew(textToSpeak)) {
      const edgeVoice = isHebrew(textToSpeak) ? (voice.startsWith('edge-') ? voice : 'edge-he-avri') : (voice.startsWith('edge-') ? voice : 'edge-en-jenny');
      chrome.runtime.sendMessage({
        action: 'synthesize-edge-tts',
        text: textToSpeak,
        voice: edgeVoice,
        rate: 1.0
      }, (resp) => {
        if (state.sequenceId !== mySeq) return;
        if (resp && resp.success && resp.audioDataUrl) {
          playAudioUrl(resp.audioDataUrl, textToSpeak, mySeq, false, offset);
          prefetchSentence(index + 1);
        } else if (state.engineAvailable) {
          chrome.runtime.sendMessage({
            action: 'synthesize-local',
            text: textToSpeak,
            voice,
            speed: 1.0
          }, (localResp) => {
            if (state.sequenceId !== mySeq) return;
            if (localResp && localResp.success && localResp.audioDataUrl) {
              playAudioUrl(localResp.audioDataUrl, textToSpeak, mySeq, true, offset);
            } else if (!isHebrew(textToSpeak)) {
              speakWebSpeech(textToSpeak, mySeq, offset);
            } else {
              console.warn('[GuyReader] Hebrew neural voice failed. Carmit fallback blocked.');
              onSentenceFinished();
            }
          });
        } else if (!isHebrew(textToSpeak)) {
          speakWebSpeech(textToSpeak, mySeq, offset);
        } else {
          console.warn('[GuyReader] Hebrew neural voice failed. Carmit fallback blocked.');
          onSentenceFinished();
        }
      });
    } else if (!isHebrew(textToSpeak)) {
      speakWebSpeech(textToSpeak, mySeq, offset);
    } else {
      console.warn('[GuyReader] Hebrew neural voice failed. Carmit fallback blocked.');
      onSentenceFinished();
    }
  }

  function speakConnectedPassage(index, offset, sequence) {
    const segments = [];
    let text = '';
    const hebrew = isHebrew(state.sentences[index].text);
    for (let i = index; i < state.sentences.length; i++) {
      const item = state.sentences[i];
      if (isHebrew(item.text) !== hebrew || (text.length && text.length + item.text.length > 2500)) break;
      const from = i === index ? offset : 0;
      if (text) text += ' ';
      segments.push({index:i, start:text.length, offset:from});
      text += item.text.slice(from);
    }
    speakWebSpeech(text, sequence, offset, segments);
  }

  function prefetchSentence(index, offset = 0) {
    const item = state.sentences[index];
    if (!item || !state.engineAvailable) return Promise.resolve(null);
    const isHeb = /he-|avri|hila|roboshaul|shaul/i.test(state.voice);
    const voice = isHebrew(item.text)
      ? (isHeb ? state.voice : 'edge-he-avri')
      : (isHeb ? 'af_sarah' : state.voice);
    const key = `${index}:${offset}:${voice}`;
    if (state.prefetch.has(key)) return state.prefetch.get(key);
    const generation = state.generation;
    const request = new Promise(resolve => {
      try {
        const action = voice.startsWith('edge-') ? 'synthesize-edge-tts' : 'synthesize-local';
        chrome.runtime.sendMessage({action,text:item.text.slice(offset),voice,speed:1.0,rate:1.0}, resp => {
          const audioUrl = (generation === state.generation && !chrome.runtime.lastError && resp?.success) ? resp.audioDataUrl : null;
          resolve(audioUrl);
          if (audioUrl && index + 1 < state.sentences.length) {
            prefetchSentence(index + 1);
          }
        });
      } catch (_) { resolve(null); }
    });
    state.prefetch.set(key, request);
    // Keep only a short window instead of retaining an entire article's audio.
    for (const old of state.prefetch.keys()) if (Number(old.split(':')[0]) < index - 1) state.prefetch.delete(old);
    return request;
  }

  let audioCtx = null;
  function getAudioContext() {
    try {
      if (!audioCtx && (window.AudioContext || window.webkitAudioContext)) {
        const Ctx = window.AudioContext || window.webkitAudioContext;
        audioCtx = new Ctx();
      }
      if (audioCtx && audioCtx.state === 'suspended') {
        audioCtx.resume().catch(() => {});
      }
      return audioCtx;
    } catch (_) {
      return null;
    }
  }

  function dataUrlToBlob(dataUrl) {
    if (typeof atob === 'undefined' || typeof Blob === 'undefined') return null;
    const parts = dataUrl.split(',');
    if (parts.length < 2) return null;
    const mime = (parts[0].match(/:(.*?);/) || [])[1] || 'audio/mp3';
    const bstr = atob(parts[1]);
    let n = bstr.length;
    const u8arr = new Uint8Array(n);
    while (n--) {
      u8arr[n] = bstr.charCodeAt(n);
    }
    return new Blob([u8arr], { type: mime });
  }

  function stopCurrentAudioOnly() {
    if (state.activeSourceNode) {
      try { state.activeSourceNode.stop(); } catch (_) {}
      state.activeSourceNode = null;
    }
    if (state.audioElement) {
      state.audioElement.onplay = null;
      state.audioElement.onended = null;
      state.audioElement.onerror = null;
      state.audioElement.pause();
      state.audioElement.removeAttribute('src');
      state.audioElement.load();
      state.audioElement = null;
    }
    if (state.currentSpeechUtterance) {
      state.currentSpeechUtterance.onend = null;
      state.currentSpeechUtterance.onerror = null;
      state.currentSpeechUtterance = null;
    }
    if ('speechSynthesis' in window) {
      window.speechSynthesis.cancel();
    }
    if (state.wordTimer) {
      clearInterval(state.wordTimer);
      state.wordTimer = null;
    }
  }

  function playAudioUrl(url, text, seqId, isBlobUrl, offset = 0) {
    if (state.sequenceId !== seqId) return;

    let playableUrl = url;
    let createdBlobUrl = false;
    let rawBlob = null;

    if (url && typeof url === 'string' && url.startsWith('data:')) {
      try {
        rawBlob = dataUrlToBlob(url);
        if (rawBlob && typeof URL !== 'undefined' && URL.createObjectURL) {
          playableUrl = URL.createObjectURL(rawBlob);
          createdBlobUrl = true;
        }
      } catch (_) {
        playableUrl = url;
      }
    }

    const cleanup = () => {
      if (createdBlobUrl || isBlobUrl) {
        try { if (typeof URL !== 'undefined' && URL.revokeObjectURL) URL.revokeObjectURL(playableUrl); } catch (_) {}
      }
    };

    const tryWebAudioFallback = async () => {
      try {
        const ctx = getAudioContext();
        if (!ctx) return false;
        if (ctx.state === 'suspended') await ctx.resume();
        let arrayBuf = null;
        if (rawBlob && rawBlob.arrayBuffer) {
          arrayBuf = await rawBlob.arrayBuffer();
        } else if (url && url.startsWith('data:') && typeof atob !== 'undefined') {
          const bstr = atob(url.split(',')[1]);
          const u8arr = new Uint8Array(bstr.length);
          for (let i = 0; i < bstr.length; i++) u8arr[i] = bstr.charCodeAt(i);
          arrayBuf = u8arr.buffer;
        } else if (typeof fetch !== 'undefined') {
          const res = await fetch(url);
          arrayBuf = await res.arrayBuffer();
        }
        if (!arrayBuf) return false;

        const audioBuffer = await ctx.decodeAudioData(arrayBuf);
        const source = ctx.createBufferSource();
        source.buffer = audioBuffer;
        source.playbackRate.value = state.speed;
        source.connect(ctx.destination);
        source.onended = () => {
          cleanup();
          if (state.sequenceId !== seqId) return;
          if (state.wordTimer) clearInterval(state.wordTimer);
          onSentenceFinished();
        };
        source.start(0);
        state.activeSourceNode = source;
        startWordTimer(text, { currentTime: 0, duration: audioBuffer.duration }, offset);
        updatePillUI();
        return true;
      } catch (err) {
        console.warn('[GuyReader] Web Audio fallback failed:', err);
        return false;
      }
    };

    const audio = new Audio(playableUrl);
    state.audioElement = audio;
    audio.playbackRate = state.speed;

    audio.onplay = () => {
      if (state.sequenceId !== seqId || state.isPaused) {
        audio.pause();
        cleanup();
        return;
      }
      startWordTimer(text, audio, offset);
      updatePillUI();
    };

    audio.onended = () => {
      cleanup();
      if (state.sequenceId !== seqId) return;
      if (state.wordTimer) clearInterval(state.wordTimer);
      onSentenceFinished();
    };

    audio.onerror = async (e) => {
      console.warn("Audio element error, attempting Web Audio fallback:", e);
      const recovered = await tryWebAudioFallback();
      if (recovered) return;

      cleanup();
      if (state.sequenceId !== seqId) return;
      if (isHebrew(text)) {
        console.warn('[GuyReader] Hebrew audio error; Carmit fallback blocked.');
        onSentenceFinished();
        return;
      }
      speakWebSpeech(text, seqId, offset);
    };

    const playPromise = state.isPaused ? undefined : audio.play();
    if (playPromise !== undefined) {
      playPromise.catch(async (err) => {
        if (state.sequenceId !== seqId) return;
        console.warn("Autoplay policy prevented audio.play(), trying Web Audio:", err);
        const recovered = await tryWebAudioFallback();
        if (recovered) return;

        cleanup();
        showFloatingPill();
        state.isPlaying = false;
        state.isPaused = true;
        updatePillUI();
      });
    }
  }

  function startWordTimer(text, audioEl, offset = 0) {
    if (state.wordTimer) clearInterval(state.wordTimer);
    // Neural audio without alignment metadata is explicitly an estimate, tied to media time.
    const words = [...text.matchAll(/\S+/gu)];
    const weights = words.map(w => Math.max(1, w[0].replace(/[^\p{L}\p{N}]/gu, '').length));
    const total = weights.reduce((a,b) => a+b, 0);
    const update = () => {
      if (state.isPaused || !Number.isFinite(audioEl.duration) || !audioEl.duration) return;
      let target = audioEl.currentTime / audioEl.duration * total, i = 0;
      while (i < weights.length - 1 && target >= weights[i]) target -= weights[i++];
      if (words[i]) highlightWordAt(offset + words[i].index);
    };
    update();
    state.wordTimer = setInterval(update, 40);
  }

  function speakWebSpeech(text, seqId, offset = 0, segments = null) {
    if (state.sequenceId !== seqId || state.isPaused) return;
    if (!('speechSynthesis' in window)) {
      onSentenceFinished();
      return;
    }

    window.speechSynthesis.cancel();
    const utt = new SpeechSynthesisUtterance(text);
    utt.rate = state.speed;

    const voices = window.speechSynthesis.getVoices();
    const isHeb = isHebrew(text);
    if (isHeb) {
      // Carmit is strictly eliminated. Never speak Hebrew via Web Speech fallback on macOS.
      console.warn('[GuyReader] Web Speech Hebrew (Carmit) is disabled.');
      onSentenceFinished();
      return;
    }
    utt.lang = 'en-US';
    const evan = voices.find(v => v.name.includes('Evan') && v.lang.startsWith('en'));
    const usVoice = evan || voices.find(v => v.lang.startsWith('en-US')) || voices[0];
    if (usVoice) utt.voice = usVoice;

    utt.onboundary = (e) => {
      if (e.name === 'word' && state.sequenceId === seqId) {
        if (segments) {
          const segment = [...segments].reverse().find(s => s.start <= e.charIndex);
          if (!segment) return;
          if (state.currentIndex !== segment.index) {
            state.currentIndex = segment.index;
            highlightSentenceOnPage(segment.index);
            updatePillUI();
          }
          highlightWordAt(segment.offset + e.charIndex - segment.start);
        } else highlightWordAt(offset + e.charIndex);
      }
    };

    utt.onend = () => {
      if (state.sequenceId !== seqId) return;
      if (segments) state.currentIndex = segments.at(-1).index;
      onSentenceFinished();
    };

    utt.onerror = () => {
      if (state.sequenceId !== seqId) return;
      stopReading();
      alert("Speech could not start. Check installed macOS voices or choose Neural audio mode.");
    };

    state.currentSpeechUtterance = utt;
    window.speechSynthesis.speak(utt);
  }

  function onSentenceFinished() {
    if (!state.isPlaying) return;
    if (state.currentIndex + 1 < state.sentences.length) {
      playSentence(state.currentIndex + 1, true);
    } else {
      stopReading();
    }
  }

  // 6. Floating Player UI Component
  function createFloatingPill() {
    if (document.getElementById('guy-reader-floating-pill')) return;

    const pill = document.createElement('div');
    pill.id = 'guy-reader-floating-pill';
    pill.innerHTML = `
      <div id="guy-reader-drag-handle" title="Drag to move">
        <svg viewBox="0 0 16 16" width="12" height="12" fill="currentColor">
          <circle cx="5" cy="4" r="1.4"/><circle cx="11" cy="4" r="1.4"/>
          <circle cx="5" cy="8" r="1.4"/><circle cx="11" cy="8" r="1.4"/>
          <circle cx="5" cy="12" r="1.4"/><circle cx="11" cy="12" r="1.4"/>
        </svg>
      </div>
      <span class="guy-reader-status-dot"></span>
      <button class="guy-reader-pill-btn guy-reader-pill-btn-play" id="guy-btn-play" title="Play / Pause (Space)">
        <span id="guy-icon-play">▶</span>
        <span id="guy-icon-pause" style="display:none;">⏸</span>
      </button>
      <button class="guy-reader-pill-btn" id="guy-btn-stop" title="Stop reading">■</button>
      <span class="guy-reader-counter" id="guy-counter">[0/0]</span>
      <div class="guy-reader-speed-group">
        <button class="guy-reader-speed-btn" id="guy-speed-down">−</button>
        <span class="guy-reader-speed-val" id="guy-speed-val">1.0x</span>
        <button class="guy-reader-speed-btn" id="guy-speed-up">+</button>
      </div>
      <select class="guy-reader-voice-select" id="guy-mode-select" title="Word highlighting mode">
        <option value="sync">Follow words · Evan (English)</option>
        <option value="neural">Neural · estimated words</option>
      </select>
      <select class="guy-reader-voice-select" id="guy-voice-select" title="Voice">
        <optgroup label="English (Local Kokoro)">
          <option value="af_sarah">🎙️ Sarah</option>
          <option value="am_michael">🎙️ Michael</option>
        </optgroup>
        <optgroup label="Hebrew Voices">
          <option value="he-roboshaul">🎙️ Shaul (RoboShaul)</option>
          <option value="edge-he-avri">🌟 Avri</option>
          <option value="edge-he-hila">🌟 Hila</option>
        </optgroup>
      </select>
      <span class="guy-reader-clean-btn" id="guy-btn-clean" title="Toggle Clean Reader Mode">📖</span>
      <span class="guy-reader-close-btn" id="guy-btn-close" title="Close Guy_reader">✕</span>
    `;

    document.body.appendChild(pill);
    state.pillEl = pill;

    // Dragging support
    setupPillDragging(pill);

    // Controls
    document.getElementById('guy-btn-stop').addEventListener('click', stopReading);
    const mode = document.getElementById('guy-mode-select');
    mode.value = state.synchronized ? 'sync' : 'neural';
    mode.addEventListener('change', e => {
      state.synchronized = e.target.value === 'sync';
      chrome.storage?.local.set({guy_reader_sync:state.synchronized});
      if (state.isPlaying || state.isPaused) playSentence(Math.max(0, state.currentIndex), false, state.wordOffset);
    });
    document.getElementById('guy-btn-play').addEventListener('click', () => {
      getAudioContext();
      if (state.isPlaying) pauseReading();
      else resumeReading();
    });

    document.getElementById('guy-speed-down').addEventListener('click', () => {
      setSpeed(Math.max(0.5, Math.round((state.speed - 0.1) * 10) / 10));
    });

    document.getElementById('guy-speed-up').addEventListener('click', () => {
      setSpeed(Math.min(2.5, Math.round((state.speed + 0.1) * 10) / 10));
    });

    document.getElementById('guy-voice-select').addEventListener('change', (e) => {
      state.voice = e.target.value;
      chrome.storage?.local.set({guy_reader_voice:state.voice});
      if (state.voice.startsWith('edge-') && state.synchronized) {
        state.synchronized = false;
        mode.value = 'neural';
        chrome.storage?.local.set({guy_reader_sync:false});
      }
      if (state.isPlaying || state.isPaused) {
        playSentence(state.currentIndex >= 0 ? state.currentIndex : 0);
      }
    });

    document.getElementById('guy-btn-clean').addEventListener('click', () => {
      toggleCleanReaderMode();
    });

    document.getElementById('guy-btn-close').addEventListener('click', () => {
      stopReading();
      exitCleanReaderMode();
      state.isActive = false;
      pill.classList.add('guy-hidden');
    });
  }

  function setSpeed(newSpeed) {
    state.speed = newSpeed;
    if (state.audioElement) {
      state.audioElement.playbackRate = state.speed;
    }
    const valEl = document.getElementById('guy-speed-val');
    if (valEl) valEl.textContent = state.speed.toFixed(1) + 'x';
  }

  function showFloatingPill() {
    createFloatingPill();
    if (state.pillEl) state.pillEl.classList.remove('guy-hidden');
  }

  function updatePillUI() {
    const summary = JSON.stringify([state.isPlaying,state.isPaused,state.currentIndex,state.sentences.length]);
    if (summary !== state.lastReportedState) {
      state.lastReportedState = summary;
      try { chrome.runtime.sendMessage({action:'reader-state',playing:state.isPlaying,paused:state.isPaused,
        index:state.currentIndex,total:state.sentences.length}, () => { void chrome.runtime.lastError; }); } catch (_) {}
    }
    const playIcon = document.getElementById('guy-icon-play');
    const pauseIcon = document.getElementById('guy-icon-pause');
    const counterEl = document.getElementById('guy-counter');
    const voiceSelect = document.getElementById('guy-voice-select');

    if (playIcon && pauseIcon) {
      if (state.isPlaying) {
        playIcon.style.display = 'none';
        pauseIcon.style.display = 'inline';
      } else {
        playIcon.style.display = 'inline';
        pauseIcon.style.display = 'none';
      }
    }

    if (counterEl) {
      const current = state.currentIndex >= 0 ? state.currentIndex + 1 : 0;
      counterEl.textContent = `[${current}/${state.sentences.length}]`;
    }

    if (voiceSelect) voiceSelect.style.display = '';
    if (voiceSelect && voiceSelect.value !== state.voice) {
      voiceSelect.value = state.voice;
    }
  }

  function setupPillDragging(el) {
    const handle = el.querySelector('#guy-reader-drag-handle');
    if (!handle) return;

    let isDragging = false;
    let startX = 0, startY = 0;
    let initialLeft = 0, initialTop = 0;

    handle.addEventListener('mousedown', (e) => {
      isDragging = true;
      startX = e.clientX;
      startY = e.clientY;
      const rect = el.getBoundingClientRect();
      initialLeft = rect.left;
      initialTop = rect.top;

      function onMouseMove(ev) {
        if (!isDragging) return;
        const dx = ev.clientX - startX;
        const dy = ev.clientY - startY;
        el.style.left = `${Math.max(10, Math.min(window.innerWidth - el.offsetWidth - 10, initialLeft + dx))}px`;
        el.style.top = `${Math.max(10, Math.min(window.innerHeight - el.offsetHeight - 10, initialTop + dy))}px`;
        el.style.right = 'auto';
      }

      function onMouseUp() {
        isDragging = false;
        window.removeEventListener('mousemove', onMouseMove);
        window.removeEventListener('mouseup', onMouseUp);
      }

      window.addEventListener('mousemove', onMouseMove);
      window.addEventListener('mouseup', onMouseUp);
    });
  }

  // 7. Clean Reader Mode
  function toggleCleanReaderMode() {
    if (state.cleanReaderMode) {
      exitCleanReaderMode();
    } else {
      enterCleanReaderMode();
    }
  }

  function enterCleanReaderMode() {
    if (state.cleanReaderMode) return;

    // Collect article text from sentences
    const textParagraphs = [];
    let lastEl = null;
    for (const item of state.sentences) {
      if (item.element !== lastEl) {
        textParagraphs.push([]);
        lastEl = item.element;
      }
      textParagraphs[textParagraphs.length - 1].push(item.text);
    }

    // Create overlay
    const overlay = document.createElement('div');
    overlay.id = 'guy-reader-clean-overlay';
    overlay.innerHTML = `
      <div class="guy-reader-clean-content">
        <h1 class="guy-reader-clean-title">${document.title || 'Article'}</h1>
        ${textParagraphs.map(para =>
          `<p class="guy-reader-clean-para">${para.join(' ')}</p>`
        ).join('\n')}
      </div>
    `;

    document.body.appendChild(overlay);
    state.cleanReaderMode = true;

    // Update button state
    const btn = document.getElementById('guy-btn-clean');
    if (btn) btn.title = 'Exit Clean Reader Mode';

    // Re-extract sentences from clean overlay so highlighting works
    state.sentences = extractArticleData();
    if (state.isPlaying && state.currentIndex >= 0) {
      highlightSentenceOnPage(state.currentIndex);
    }
  }

  function exitCleanReaderMode() {
    if (!state.cleanReaderMode) return;
    const overlay = document.getElementById('guy-reader-clean-overlay');
    if (overlay) overlay.remove();
    state.cleanReaderMode = false;

    const btn = document.getElementById('guy-btn-clean');
    if (btn) btn.title = 'Toggle Clean Reader Mode';

    // Re-extract from original DOM
    if (state.isActive) {
      state.sentences = extractArticleData();
    }
  }

  // 8. Message Router from Background or Popup
  chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
    if (msg.expiresAt && Date.now() > msg.expiresAt) {
      sendResponse({success:false, expired:true});
      return false;
    }
    if (msg.voice && msg.voice !== state.voice) {
      state.voice = msg.voice;
      chrome.storage?.local.set({ guy_reader_voice: state.voice });
      const voiceSelect = dom.pill?.querySelector('.pill-voice-select');
      if (voiceSelect) voiceSelect.value = state.voice;
    }
    if (msg.action === 'pause') {
      pauseReading(); sendResponse({success:true});
    } else if (msg.action === 'resume') {
      resumeReading(); sendResponse({success:true});
    } else if (msg.action === 'set-voice') {
      sendResponse({ success: true, voice: state.voice });
    } else if (msg.action === 'toggle-read') {
      const selected = window.getSelection ? window.getSelection().toString().trim() : '';
      const current = state.sentences[state.currentIndex]?.text || '';
      if (selected && !current.includes(selected)) {
        startReading(true);
      } else if (state.isPlaying) {
        pauseReading();
      } else if (state.isPaused) {
        resumeReading();
      } else {
        startReading(true);
      }
      sendResponse({ success: true, isPlaying: state.isPlaying });
    } else if (msg.action === 'read-from-start') {
      startReading(false);
      sendResponse({ success: state.isPlaying });
    } else if (msg.action === 'read-from-selection') {
      startReading(true);
      sendResponse({ success: state.isPlaying });
    } else if (msg.action === 'toggle-pill') {
      showFloatingPill();
      sendResponse({ success: true });
    } else if (msg.action === 'stop') {
      stopReading();
      sendResponse({ success: true });
    }
  });

  // Setup click to seek on start
  setupClickToSeek();
})();
