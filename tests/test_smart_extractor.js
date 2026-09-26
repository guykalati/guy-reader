// Test smart extractor, sentence splitting, and speed logic via JXA (JavaScriptCore)
(() => {
  'use strict';

  let testsRun = 0;
  let testsPassed = 0;

  function assert(condition, message) {
    testsRun++;
    if (condition) {
      console.log('  [PASS] ' + message);
      testsPassed++;
    } else {
      console.log('  [FAIL] ' + message);
    }
  }

  console.log('=== Running Smart Extractor & UI Logic Tests ===');

  // 1. Sentence Splitter Tests
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

  const englishSentences = splitSentences("This is the first sentence. Here is the second sentence! Is this the third? Yes it is");
  assert(englishSentences.length === 4, "Splits 4 English sentences on period, exclamation, question mark");
  assert(englishSentences[0] === "This is the first sentence.", "First sentence preserved correctly");
  assert(englishSentences[1] === "Here is the second sentence!", "Second sentence preserved correctly");
  assert(englishSentences[2] === "Is this the third?", "Third sentence preserved correctly");
  assert(englishSentences[3] === "Yes it is", "Fourth sentence (no trailing period) preserved correctly");

  const hebrewSentences = splitSentences("שלום לכולם! זוהי בדיקה של הקראת טקסט בעברית. האם זה עובד היטב? כן, בהחלט.");
  assert(hebrewSentences.length === 4, "Splits Hebrew sentences properly");
  assert(hebrewSentences[0] === "שלום לכולם!", "First Hebrew sentence captured");

  // Adversarial Splitter Tests: Decimals, Abbreviations, URLs
  const decimalTest = splitSentences("The stock rose by 3.5% today. New sentence.");
  assert(decimalTest.length === 2, "Does NOT split on decimal point in 3.5%");
  assert(decimalTest[0] === "The stock rose by 3.5% today.", "Decimal sentence preserved intact");

  const priceTest = splitSentences("Price is $19.99 right now! Buy it today.");
  assert(priceTest.length === 2 && priceTest[0].includes("$19.99"), "Preserves currency with decimal $19.99");

  const abbrevTest = splitSentences("Dr. Smith visited the U.S. today. He had a great time.");
  assert(abbrevTest.length === 2, "Does NOT split on abbreviation Dr. or U.S.");
  assert(abbrevTest[0] === "Dr. Smith visited the U.S. today.", "Abbreviation sentence preserved intact");

  const urlTest = splitSentences("Check out https://guyreader.app for info. It is great.");
  assert(urlTest.length === 2, "Does NOT split on dots inside URLs");
  assert(urlTest[0] === "Check out https://guyreader.app for info.", "URL sentence preserved intact");

  // Adversarial Email Splitting Tests
  const emailTest = splitSentences("Please email john.doe@example.com for help. Thanks.");
  assert(emailTest.length === 2, "Does NOT split email address with dots");
  assert(emailTest[0] === "Please email john.doe@example.com for help.", "Email address preserved intact in sentence");

  const emailTest2 = splitSentences("Contact support.team@guyreader.app immediately. We are ready.");
  assert(emailTest2.length === 2, "Does NOT split subdomain email address");
  assert(emailTest2[0] === "Contact support.team@guyreader.app immediately.", "Subdomain email preserved intact");

  // Adversarial AM/PM Notation Tests
  const pmTest = splitSentences("The flight leaves at 5 p.m. today. Please arrive early.");
  assert(pmTest.length === 2, "Does NOT split on p.m. time notation");
  assert(pmTest[0] === "The flight leaves at 5 p.m. today.", "P.M. sentence preserved intact");

  const amTest = splitSentences("Wake up at 6 a.m. tomorrow. Have breakfast.");
  assert(amTest.length === 2, "Does NOT split on a.m. time notation");
  assert(amTest[0] === "Wake up at 6 a.m. tomorrow.", "A.M. sentence preserved intact");

  // Adversarial Initials and Names Tests
  const initialsTest = splitSentences("John F. Kennedy was president. He was born in Brookline.");
  assert(initialsTest.length === 2, "Does NOT split on middle initial John F. Kennedy");
  assert(initialsTest[0] === "John F. Kennedy was president.", "Name with initial preserved intact");

  // Hebrew Initials, Dates, and Title Abbreviations Tests
  const hebInitialsTest = splitSentences("ד\"ר א. כהן ופרופ. שמעוני הגיעו מארה\"ב ב-7.10.2023. הם ביקרו בצה\"ל.");
  assert(hebInitialsTest.length === 2, "Does NOT split on Hebrew initial א. כהן, title פרופ., or multi-dot date 7.10.2023");
  assert(hebInitialsTest[0] === "ד\"ר א. כהן ופרופ. שמעוני הגיעו מארה\"ב ב-7.10.2023.", "Hebrew initials and date sentence preserved intact");
  assert(hebInitialsTest[1] === "הם ביקרו בצה\"ל.", "Second Hebrew sentence preserved intact");

  const hebMultiDateTest = splitSentences("האירוע התרחש ב-7.10.2023 באזור הדרום. כוחות צה\"ל הוזעקו למקום.");
  assert(hebMultiDateTest.length === 2, "Preserves multi-dot date 7.10.2023 without breaking");
  assert(hebMultiDateTest[0] === "האירוע התרחש ב-7.10.2023 באזור הדרום.", "Date sentence preserved intact");

  const hebTitlesTest = splitSentences("עו\"ד. לוי ורו\"ח. שטרן נפגשו בלשכה. הדיון נמשך זמן רב.");
  assert(hebTitlesTest.length === 2, "Does NOT split on Hebrew professional titles עו\"ד. and רו\"ח.");

  const hebEtcTest = splitSentences("נרכשו עטים, ספרים וכו. במבצע מיוחד. המשפט הבא מתחיל כאן.");
  assert(hebEtcTest.length === 2, "Does NOT split on Hebrew abbreviation וכו.");

  // Adversarial Corporate and Publication Abbreviations Tests
  const corpTest = splitSentences("Apple Inc. is in Cupertino. Microsoft Corp. is in Redmond.");
  assert(corpTest.length === 2, "Does NOT split on corporate abbreviations Inc. or Corp.");
  assert(corpTest[0] === "Apple Inc. is in Cupertino.", "Inc. corporate sentence preserved intact");

  const etAlTest = splitSentences("Johnson et al. published the report. It was peer-reviewed.");
  assert(etAlTest.length === 2, "Does NOT split on citation et al.");
  assert(etAlTest[0] === "Johnson et al. published the report.", "et al. citation sentence preserved intact");

  // Adversarial Dialogue Quotes Followed by Lowercase Attribution
  const dialogueTest = splitSentences('"Is this true?" she asked. "Yes," he replied.');
  assert(dialogueTest.length === 2, "Keeps dialogue quote intact with its attribution clause");
  assert(dialogueTest[0] === '"Is this true?" she asked.', "First dialogue sentence preserved with attribution");
  assert(dialogueTest[1] === '"Yes," he replied.', "Second dialogue sentence preserved with attribution");

  assert(splitSentences("").length === 0, "Empty string returns empty array");
  assert(splitSentences("   \n\n  ").length === 0, "Whitespace only returns empty array");
  assert(splitSentences("...").length === 0, "Punctuation without letters/digits returns empty array");

  // 2. Speed stepping and clamping tests
  function clamp(val, min, max) {
    return Math.min(Math.max(val, min), max);
  }

  function stepSpeed(current, delta) {
    return Math.round(clamp(current + delta, 0.5, 2.5) * 10) / 10;
  }

  assert(stepSpeed(1.0, 0.1) === 1.1, "Speed increments by 0.1x from 1.0x to 1.1x");
  assert(stepSpeed(1.0, -0.1) === 0.9, "Speed decrements by 0.1x from 1.0x to 0.9x");
  assert(stepSpeed(2.5, 0.1) === 2.5, "Speed clamped at max 2.5x");
  assert(stepSpeed(0.5, -0.1) === 0.5, "Speed clamped at min 0.5x");
  assert(stepSpeed(1.9, 0.1) === 2.0, "Speed handles floating point rounding (1.9 + 0.1 -> 2.0)");

  // 3. Hebrew language detection
  function isHebrew(text) {
    return /[\u0590-\u05FF]/.test(text);
  }

  assert(isHebrew("שלום"), "Hebrew detection returns true for Hebrew");
  assert(!isHebrew("Hello world"), "Hebrew detection returns false for English");
  assert(isHebrew("Guy_reader בעברית"), "Hebrew detection returns true for mixed string");

  // 4. Twitter / X tweet selection logic simulation
  const mockTweets = [
    {
      top: -200, bottom: -50, height: 150,
      text: "Old tweet above viewport that was scrolled past"
    },
    {
      top: 40, bottom: 260, height: 220,
      text: "Breaking: Guy_reader releases major update with Fn+Space hotkey and Apple Evan voice!"
    },
    {
      top: 300, bottom: 500, height: 200,
      text: "Third tweet further down in timeline"
    }
  ];

  function findForegroundTweet(tweets, viewportHeight) {
    let bestTweet = null;
    let bestScore = -1e9;
    for (let i = 0; i < tweets.length; i++) {
      const t = tweets[i];
      const visibleTop = Math.max(0, t.top);
      const visibleBottom = Math.min(viewportHeight, t.bottom);
      const visibleHeight = Math.max(0, visibleBottom - visibleTop);
      if (visibleHeight > 30) {
        const score = visibleHeight - Math.abs(t.top);
        if (score > bestScore) {
          bestScore = score;
          bestTweet = t;
        }
      }
    }
    return bestTweet ? bestTweet.text : null;
  }

  const extractedTweet = findForegroundTweet(mockTweets, 800);
  assert(extractedTweet && extractedTweet.includes("Breaking: Guy_reader"), "Intelligently extracts the foreground tweet in view");

  // 5. Web boilerplate filtering with short words support
  function filterBoilerplate(lines) {
    const cleanLines = lines
      .map(l => l.trim())
      .filter(l => {
        if (l.length === 0) return false;
        // Skip non-alphanumeric noise lines (like · or -)
        if (!/[\p{L}\p{N}]/u.test(l)) return false;
        if (l === "Follow" || l === "Share" || l === "Reply" || l === "Like" || l === "Repost" || l === "Subscribe" ||
            l === "Promoted" || l === "Show more" || l === "Show this thread" || l === "Pinned Tweet" || l === "Bookmark" ||
            l === "Translate post" || l === "View quotes") return false;
        if (l.endsWith("Retweets") || l.endsWith("Reposts") || l.endsWith("Likes") || l.endsWith("Views") || l.endsWith("Quotes") || l.endsWith("Replies")) return false;
        if (/^[·\s]*\d+[smhdwy](?:\s+ago)?$/i.test(l)) return false; // timestamps like "2h", "· 2h", "15m ago"
        return true;
      });

    return cleanLines;
  }

  const rawLines = ["Follow", "·", "2h", "This is the real core post that should be read by Guy_reader.", "Reply", "Share", "124 Retweets"];
  const cleanLines = filterBoilerplate(rawLines);
  assert(cleanLines.length === 1 && cleanLines[0].startsWith("This is the real core post"), "Filters out Twitter/Web action buttons, dots, and timestamps");

  // Adversarial timestamp & noise tests
  assert(filterBoilerplate(["· 2h"]).length === 0, "Filters out bullet timestamp '· 2h'");
  assert(filterBoilerplate(["15m ago"]).length === 0, "Filters out relative timestamp '15m ago'");
  assert(filterBoilerplate(["Promoted"]).length === 0, "Filters out Twitter ad badge 'Promoted'");
  assert(filterBoilerplate(["Show this thread"]).length === 0, "Filters out Twitter thread link 'Show this thread'");
  assert(filterBoilerplate(["Pinned Tweet"]).length === 0, "Filters out 'Pinned Tweet' header");

  // Adversarial: short words must NOT be eliminated
  assert(filterBoilerplate(["OK"])[0] === "OK", "Preserves short valid 2-letter word 'OK'");
  assert(filterBoilerplate(["Go"])[0] === "Go", "Preserves short valid 2-letter word 'Go'");
  assert(filterBoilerplate(["Hi"])[0] === "Hi", "Preserves short valid 2-letter word 'Hi'");
  assert(filterBoilerplate(["·"]).length === 0, "Filters out standalone bullet dot");

  // 6. Adversarial Test: isHebrewVoice vs eleven-rachel & standalone voice names
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

  assert(!isHebrewVoice('eleven-rachel'), "eleven-rachel is NOT classified as Hebrew voice (does not trigger false switch)");
  assert(!isHebrewVoice('eleven-adam'), "eleven-adam is not classified as Hebrew voice");
  assert(!isHebrewVoice('apple-evan'), "apple-evan is not classified as Hebrew voice");
  assert(!isHebrewVoice('edge-en-jenny'), "edge-en-jenny is not classified as Hebrew voice");
  assert(!isHebrewVoice('apple-heather'), "apple-heather is not classified as Hebrew voice");
  assert(isHebrewVoice('edge-he-avri'), "edge-he-avri is correctly classified as Hebrew voice");
  assert(isHebrewVoice('edge-he-hila'), "edge-he-hila is correctly classified as Hebrew voice");
  assert(isHebrewVoice('google-he-neural2'), "google-he-neural2 is correctly classified as Hebrew voice");
  assert(isHebrewVoice('he-roboshaul'), "he-roboshaul is correctly classified as Hebrew voice");
  assert(isHebrewVoice('roboshaul'), "standalone roboshaul is correctly classified as Hebrew voice");
  assert(isHebrewVoice('shaul'), "standalone shaul is correctly classified as Hebrew voice");
  assert(!isHebrewVoice('apple-carmit'), "apple-carmit is NOT recognized as Hebrew voice (purged)");
  assert(isHebrewVoice('avri'), "standalone avri is correctly classified as Hebrew voice");
  assert(isHebrewVoice('hila'), "standalone hila is correctly classified as Hebrew voice");

  // 7. Exact Selection Priority in Smart Extractor & Tag Bypassing
  function simulateExtractor(hasSelection, selectedText, hasTweets, tweetText) {
    if (hasSelection && selectedText && selectedText.trim().length > 0) {
      return "__GUY_READER_EXACT_SEL__" + selectedText.trim();
    }
    if (hasTweets && tweetText) {
      return tweetText.trim();
    }
    return "fallback page content";
  }

  function handleExtractedResult(result) {
    if (result.startsWith("__GUY_READER_EXACT_SEL__")) {
      return result.substring(24); // Exact selection delivered directly without filtering
    }
    if (result.startsWith("__GLAIDO_EXACT_SEL__")) {
      return result.substring(20); // Backwards-compatible exact selection
    }
    return filterBoilerplate(result.split("\n")).join("\n\n");
  }

  assert(simulateExtractor(true, "Selected passage", true, "Entire foreground tweet") === "__GUY_READER_EXACT_SEL__Selected passage",
    "Active mouse selection returns __GUY_READER_EXACT_SEL__ tag");
  assert(handleExtractedResult(simulateExtractor(true, "Follow", false, "")) === "Follow",
    "Exact mouse selection with keyword 'Follow' is NOT filtered by boilerplate rules");
  assert(handleExtractedResult("__GLAIDO_EXACT_SEL__Legacy passage") === "Legacy passage",
    "Backwards-compatible __GLAIDO_EXACT_SEL__ tag is handled correctly");
  assert(handleExtractedResult(simulateExtractor(false, "", true, "Follow\n· 2h\nReal tweet")) === "Real tweet",
    "Viewport tweet content without selection IS filtered by boilerplate rules");

  // 8. Article and Web Content Extraction (Short Headings and Paragraphs)
  function extractArticleParas(elements) {
    return elements
      .map(el => (el.innerText || "").trim())
      .filter(pt => pt.length > 5 && /[\p{L}\p{N}]/u.test(pt));
  }

  const mockDomElements = [
    { innerText: "Update" }, // 6 chars (valid heading)
    { innerText: "Short Note" }, // 10 chars (valid heading)
    { innerText: "This is a standard length paragraph in the article." }, // long paragraph
    { innerText: "   " }, // empty
    { innerText: "..." } // punctuation only
  ];
  const extractedParas = extractArticleParas(mockDomElements);
  assert(extractedParas.length === 3, "Preserves short headings/paragraphs with > 5 chars and letters");
  assert(extractedParas[0] === "Update", "First short heading 'Update' preserved");
  assert(extractedParas[1] === "Short Note", "Second short heading 'Short Note' preserved");

  // 9. Replay Rewind and Highlight Reset Test
  let testSentences = ["Sentence 1", "Sentence 2", "Sentence 3"];
  let testIndex = 0;
  let testPlaying = true;
  let highlightedIndex = -1;
  function highlightSentence(idx) {
    highlightedIndex = idx;
  }
  function finishSentence() {
    if (testIndex + 1 < testSentences.length) {
      testIndex++;
      highlightSentence(testIndex);
    } else {
      testPlaying = false;
      testIndex = 0; // Rewind
      highlightSentence(0); // Rewind highlight to 0
    }
  }
  finishSentence(); // to 1
  finishSentence(); // to 2
  finishSentence(); // completes
  assert(!testPlaying, "Playback stops after last sentence");
  assert(testIndex === 0, "Index is rewound to 0 after finishing so replay starts from the beginning");
  assert(highlightedIndex === 0, "Highlighted sentence rewinds to index 0 on playback completion");

  // 10. Resize Support in Both Modes
  function computeResizeDelta(isCorner, rawDh) {
    return isCorner ? rawDh : 0;
  }

  assert(computeResizeDelta(true, 120) === 120, "Corner resize allows vertical dh for resizing");
  assert(computeResizeDelta(false, 120) === 0, "Edge horizontal handle ignores vertical dh");

  // 11. Missing API key fallback routes to appropriate language voice
  function getFallbackVoice(text) {
    return isHebrew(text) ? 'edge-he-avri' : 'apple-evan';
  }

  assert(getFallbackVoice("English text without key") === "apple-evan", "Missing API key on English text falls back to apple-evan");
  // 12. Window Dragging Delta & Boundary Clamping
  function computeWindowMove(origin, dx, dy, screenSize, windowSize) {
    let newX = origin.x + dx;
    let newY = origin.y - dy; // Cocoa Y is inverted relative to screen Y

    const minX = -windowSize.width + 60;
    const maxX = screenSize.width - 60;
    const minY = 0;
    const maxY = screenSize.height - 30;

    newX = Math.max(minX, Math.min(maxX, newX));
    newY = Math.max(minY, Math.min(maxY, newY));

    return { x: newX, y: newY };
  }

  const initialOrigin = { x: 500, y: 700 };
  const moved = computeWindowMove(initialOrigin, 25, 10, { width: 1440, height: 900 }, { width: 460, height: 60 });
  assert(moved.x === 525, "Window X moves right by dx (+25)");
  assert(moved.y === 690, "Window Y moves downward by -dy (-10 in Cocoa coordinates)");

  // Screen clamping test
  const clampedOffRight = computeWindowMove(initialOrigin, 2000, 0, { width: 1440, height: 900 }, { width: 460, height: 60 });
  assert(clampedOffRight.x === 1440 - 60, "Window X is clamped to stay partially on screen on right");

  const clampedOffBottom = computeWindowMove(initialOrigin, 0, 2000, { width: 1440, height: 900 }, { width: 460, height: 60 });
  assert(clampedOffBottom.y === 0, "Window Y is clamped to stay above screen bottom");

  // Drag threshold and interactive exclusion tests
  function shouldInitiateDrag(targetTagName, targetClasses, deltaMovement) {
    const interactiveTags = ['BUTTON', 'INPUT', 'SELECT', 'TEXTAREA', 'A'];
    if (interactiveTags.includes(targetTagName)) return false;
    if (targetClasses.some(c => ['resize-handle', 'hotkey-badge', 'speed-pill-group', 'sentence-item', 'modal-content'].includes(c))) {
      return false;
    }
    return Math.abs(deltaMovement) >= 1;
  }

  assert(shouldInitiateDrag('DIV', ['drag-zone'], 5) === true, "Drag initiates on drag-zone with movement");
  assert(shouldInitiateDrag('DIV', ['pill-bar'], 10) === true, "Drag initiates on pill-bar with movement");
  // 13. Smart Hierarchy Selection vs Full Article Extraction Tests
  function smartHierarchyExtract(articleSentences, selectedText) {
    if (!articleSentences || articleSentences.length === 0) return { startIndex: 0, sentences: [] };
    if (!selectedText || !selectedText.trim()) {
      return { startIndex: 0, sentences: articleSentences, mode: 'full_article' };
    }
    const cleanSel = selectedText.trim();
    // Find matching sentence index
    let matchedIdx = 0;
    for (let i = 0; i < articleSentences.length; i++) {
      if (articleSentences[i].includes(cleanSel) || cleanSel.includes(articleSentences[i].slice(0, 20))) {
        matchedIdx = i;
        break;
      }
    }
    return { startIndex: matchedIdx, sentences: articleSentences.slice(matchedIdx), mode: 'selection' };
  }

  const sampleArticle = [
    "This is the opening headline of the article.",
    "This is paragraph one explaining the context.",
    "This is paragraph two with detailed analysis.",
    "This is the conclusion of the article."
  ];

  const fullExtract = smartHierarchyExtract(sampleArticle, "");
  assert(fullExtract.mode === 'full_article', "Smart Hierarchy defaults to full article when no selection");
  assert(fullExtract.startIndex === 0, "Full article starts at sentence 0 (first word)");
  assert(fullExtract.sentences.length === 4, "Full article contains all 4 sentences");

  const selExtract = smartHierarchyExtract(sampleArticle, "paragraph two with detailed");
  assert(selExtract.mode === 'selection', "Smart Hierarchy detects user selection");
  assert(selExtract.startIndex === 2, "Selection matches sentence index 2");
  assert(selExtract.sentences.length === 2, "Reads from selected sentence 2 through to the end");
  assert(selExtract.sentences[0] === "This is paragraph two with detailed analysis.", "First read sentence is selected sentence");
  assert(selExtract.sentences[1] === "This is the conclusion of the article.", "Continues through to the end of the article");

  // 14. Local Engine Routing Tests (Ticket 03)
  console.log('\n--- 14. Local Engine Routing ---');

  // Simulate engine routing decision
  function routeSynthesis(engineAvailable, voice, textIsHebrew) {
    if (engineAvailable) return 'local-engine';
    if (voice.startsWith('edge-') || textIsHebrew) return 'edge-tts-background';
    return 'web-speech';
  }

  assert(routeSynthesis(true, 'af_sarah', false) === 'local-engine', 'English with engine available routes to local engine');
  assert(routeSynthesis(true, 'edge-he-avri', true) === 'local-engine', 'Hebrew with engine available routes to local engine');
  assert(routeSynthesis(false, 'edge-he-avri', true) === 'edge-tts-background', 'Hebrew without engine falls back to Edge TTS');
  assert(routeSynthesis(false, 'af_sarah', false) === 'web-speech', 'English Kokoro without engine falls back to Web Speech');
  assert(routeSynthesis(false, 'edge-en-jenny', false) === 'edge-tts-background', 'Edge voice without engine routes to Edge TTS');
  assert(routeSynthesis(false, 'am_adam', true) === 'edge-tts-background', 'Hebrew text without engine routes to Edge TTS even with Kokoro voice');

  // 15. Voice Selection for Kokoro Voices (Ticket 03)
  console.log('\n--- 15. Voice Selection ---');

  function autoDetectVoice(currentVoice, isHebrew) {
    if (isHebrew && !currentVoice.includes('he-')) {
      return 'edge-he-avri';
    } else if (!isHebrew && currentVoice.includes('he-')) {
      return 'af_sarah';
    }
    return currentVoice;
  }

  assert(autoDetectVoice('af_sarah', false) === 'af_sarah', 'English text keeps Kokoro Sarah voice');
  assert(autoDetectVoice('af_sarah', true) === 'edge-he-avri', 'Hebrew text switches from Kokoro to Avri');
  assert(autoDetectVoice('edge-he-avri', false) === 'af_sarah', 'English text switches from Avri to Kokoro Sarah');
  assert(autoDetectVoice('edge-he-avri', true) === 'edge-he-avri', 'Hebrew text keeps Avri voice');
  assert(autoDetectVoice('am_adam', false) === 'am_adam', 'English text keeps Kokoro Adam voice');
  assert(autoDetectVoice('am_michael', true) === 'edge-he-avri', 'Hebrew text switches from Michael to Avri');

  // 16. Word Timer Duration from Audio Element (Ticket 03)
  console.log('\n--- 16. Word Timer Duration ---');

  function computeMsPerWord(text, audioDuration, speed) {
    const words = text.trim().split(/\s+/);
    if (words.length === 0) return 0;
    if (audioDuration && isFinite(audioDuration)) {
      return Math.max(80, Math.round((audioDuration * 1000) / words.length));
    }
    return Math.max(120, Math.round(280 / speed));
  }

  // "Hello world how are you" = 5 words, 2.5s duration => 500ms per word
  assert(computeMsPerWord('Hello world how are you', 2.5, 1.0) === 500, 'Audio-based: 5 words in 2.5s = 500ms/word');
  // 10 words in 1.0s => 100ms per word (clamped to 100, > 80)
  assert(computeMsPerWord('a b c d e f g h i j', 1.0, 1.0) === 100, 'Audio-based: 10 words in 1.0s = 100ms/word');
  // 100 words in 0.5s => 5ms per word, clamped to 80
  assert(computeMsPerWord(Array(100).fill('word').join(' '), 0.5, 1.0) === 80, 'Audio-based: clamped to 80ms minimum');
  // Fallback when no audio duration
  assert(computeMsPerWord('Hello world', null, 1.0) === 280, 'Heuristic fallback at 1.0x speed: 280ms/word');
  assert(computeMsPerWord('Hello world', null, 2.0) === 140, 'Heuristic fallback at 2.0x speed: 140ms/word');
  assert(computeMsPerWord('Hello world', NaN, 1.0) === 280, 'NaN duration uses heuristic fallback');

  // 17. Clean Reader Mode Toggle (Ticket 03)
  console.log('\n--- 17. Clean Reader Mode ---');

  function buildCleanParagraphs(sentences) {
    const paras = [];
    let lastEl = null;
    for (const item of sentences) {
      if (item.element !== lastEl) {
        paras.push([]);
        lastEl = item.element;
      }
      paras[paras.length - 1].push(item.text);
    }
    return paras;
  }

  const elA = { id: 'p1' };
  const elB = { id: 'p2' };
  const cleanSentences = [
    { text: 'First sentence.', element: elA },
    { text: 'Second sentence.', element: elA },
    { text: 'Third sentence.', element: elB },
    { text: 'Fourth sentence.', element: elB },
  ];

  const paras = buildCleanParagraphs(cleanSentences);
  assert(paras.length === 2, 'Clean Reader groups into 2 paragraphs from 2 DOM elements');
  assert(paras[0].length === 2, 'First paragraph has 2 sentences');
  assert(paras[1].length === 2, 'Second paragraph has 2 sentences');
  assert(paras[0].join(' ') === 'First sentence. Second sentence.', 'First paragraph text is correct');
  assert(paras[1].join(' ') === 'Third sentence. Fourth sentence.', 'Second paragraph text is correct');

  // Edge case: all from same element
  const sameElSentences = [
    { text: 'A.', element: elA },
    { text: 'B.', element: elA },
    { text: 'C.', element: elA },
  ];
  const sameParas = buildCleanParagraphs(sameElSentences);
  assert(sameParas.length === 1, 'All sentences from same element = 1 paragraph');
  assert(sameParas[0].length === 3, 'Single paragraph has all 3 sentences');

  // 18. Click-to-Seek Index Resolution (Ticket 03)
  console.log('\n--- 18. Click-to-Seek ---');

  function resolveClickIndex(clickedEl, sentences) {
    for (let i = 0; i < sentences.length; i++) {
      const item = sentences[i];
      if (item.element === clickedEl) return i;
    }
    return -1;
  }

  const seekSentences = [
    { text: 'First.', element: elA },
    { text: 'Second.', element: elB },
  ];
  assert(resolveClickIndex(elA, seekSentences) === 0, 'Click on first element seeks to index 0');
  assert(resolveClickIndex(elB, seekSentences) === 1, 'Click on second element seeks to index 1');
  assert(resolveClickIndex({ id: 'unknown' }, seekSentences) === -1, 'Click on unrelated element returns -1 (no seek)');

  // 19. Global Hotkey Detection (Ticket 04: Fn + G & Option + G)
  console.log('\n--- 19. Global Hotkey Detection ---');

  function isHotkeyTrigger(keyCode, isFn, isOption) {
    // Key 5 is 'G', Key 49 is 'Space'
    return ((keyCode === 5 && (isFn || isOption)) ||
            (keyCode === 49 && (isFn || isOption)));
  }

  assert(isHotkeyTrigger(5, true, false), 'Fn + G triggers hotkey');
  assert(isHotkeyTrigger(5, false, true), 'Option + G triggers hotkey');
  assert(isHotkeyTrigger(5, true, true), 'Fn + Option + G triggers hotkey');
  assert(!isHotkeyTrigger(5, false, false), 'Plain G does not trigger hotkey');
  assert(isHotkeyTrigger(49, true, false), 'Fn + Space fallback triggers hotkey');
  assert(isHotkeyTrigger(49, false, true), 'Option + Space fallback triggers hotkey');
  assert(!isHotkeyTrigger(49, false, false), 'Plain Space does not trigger hotkey');
  assert(!isHotkeyTrigger(0, true, false), 'Fn + A does not trigger hotkey');

  // 20. Active Window Inspection & Browser Classification (Ticket 04)
  console.log('\n--- 20. Active Window Inspection ---');

  function classifyTargetApp(bundleId) {
    if (!bundleId) return 'desktop';
    const lower = bundleId.toLowerCase();
    const isBrowser = lower.includes('chrome') ||
                      lower.includes('brave') ||
                      lower.includes('edge') ||
                      lower.includes('arc') ||
                      lower.includes('thebrowser') ||
                      lower.includes('opera') ||
                      lower.includes('vivaldi');
    return isBrowser ? 'browser_bridge' : 'desktop_native';
  }

  assert(classifyTargetApp('com.google.Chrome') === 'browser_bridge', 'Google Chrome routes to browser bridge');
  assert(classifyTargetApp('com.brave.Browser') === 'browser_bridge', 'Brave routes to browser bridge');
  assert(classifyTargetApp('com.microsoft.edgemac') === 'browser_bridge', 'Microsoft Edge routes to browser bridge');
  assert(classifyTargetApp('company.thebrowser.Browser') === 'browser_bridge', 'Arc routes to browser bridge');
  assert(classifyTargetApp('com.apple.Preview') === 'desktop_native', 'Preview PDF app routes to desktop native drawer');
  assert(classifyTargetApp('com.apple.Notes') === 'desktop_native', 'Notes app routes to desktop native drawer');
  assert(classifyTargetApp('com.microsoft.Word') === 'desktop_native', 'MS Word routes to desktop native drawer');
  assert(classifyTargetApp('com.tinyspeck.slackmacgap') === 'desktop_native', 'Slack routes to desktop native drawer');

  // 21. Context-Aware Re-trigger Logic (Ticket 04)
  console.log('\n--- 21. Context-Aware Re-trigger ---');

  function handleTriggerContext({ isPlaying, isPaused, currentText, newSelection }) {
    if (isPlaying || isPaused) {
      if (newSelection && newSelection.trim() && newSelection.trim() !== currentText) {
        return { action: 'read_new', text: newSelection.trim() };
      }
      return { action: isPlaying ? 'pause' : 'resume' };
    }
    return { action: 'capture_and_speak' };
  }

  // Case 1: Playing, user presses hotkey with no new selection -> pauses
  assert(handleTriggerContext({ isPlaying: true, isPaused: false, currentText: 'Hello', newSelection: null }).action === 'pause',
    'Playing + no new selection -> toggle pause');
  // Case 2: Paused, user presses hotkey with same text -> resumes
  assert(handleTriggerContext({ isPlaying: false, isPaused: true, currentText: 'Hello', newSelection: 'Hello' }).action === 'resume',
    'Paused + same text -> toggle resume');
  // Case 3: Playing, user highlights new text -> interrupts and reads new
  const resNew = handleTriggerContext({ isPlaying: true, isPaused: false, currentText: 'Old text', newSelection: 'Brand new paragraph' });
  assert(resNew.action === 'read_new' && resNew.text === 'Brand new paragraph',
    'Playing + new selection -> immediately interrupts and reads new passage');
  // Case 4: Paused, user highlights new text -> reads new
  const resNewPaused = handleTriggerContext({ isPlaying: false, isPaused: true, currentText: 'Old text', newSelection: 'Different passage' });
  assert(resNewPaused.action === 'read_new' && resNewPaused.text === 'Different passage',
    'Paused + new selection -> reads new passage');
  // Case 5: Stopped, user presses hotkey -> starts capture
  assert(handleTriggerContext({ isPlaying: false, isPaused: false, currentText: '', newSelection: null }).action === 'capture_and_speak',
    'Stopped -> captures and speaks');

  // 22. Pill Play Button Transport Routing (Ticket 04)
  console.log('\n--- 22. Pill Play Button Transport ---');

  function routePlayButtonClick({ isPlaying, isPaused, hasSentences }) {
    if (isPlaying) return 'pause';
    if (isPaused) return 'resume';
    if (hasSentences) return 'replay';
    return 'read_selection';
  }

  assert(routePlayButtonClick({ isPlaying: true, isPaused: false, hasSentences: true }) === 'pause',
    'Pill Play button when playing pauses speech');
  assert(routePlayButtonClick({ isPlaying: false, isPaused: true, hasSentences: true }) === 'resume',
    'Pill Play button when paused resumes speech');
  assert(routePlayButtonClick({ isPlaying: false, isPaused: false, hasSentences: false }) === 'read_selection',
    'Pill Play button when empty triggers read selection on active window');

  // 23. Voice Catalog Classification (Ticket 05: Kokoro & Phonikud)
  console.log('\n--- 23. Voice Catalog Classification ---');

  function classifyVoice(voiceId) {
    if (!voiceId) return 'unknown';
    if (voiceId.startsWith('af_') || voiceId.startsWith('am_')) return 'kokoro_local';
    if (voiceId.startsWith('edge-he-')) return 'phonikud_hebrew';
    if (voiceId.startsWith('apple-')) return 'apple_native';
    if (voiceId.startsWith('edge-en-')) return 'edge_ai_english';
    return 'other';
  }

  assert(classifyVoice('af_sarah') === 'kokoro_local', 'af_sarah classified as Kokoro local');
  assert(classifyVoice('am_adam') === 'kokoro_local', 'am_adam classified as Kokoro local');
  assert(classifyVoice('af_nicole') === 'kokoro_local', 'af_nicole classified as Kokoro local');
  assert(classifyVoice('am_michael') === 'kokoro_local', 'am_michael classified as Kokoro local');
  assert(classifyVoice('edge-he-avri') === 'phonikud_hebrew', 'edge-he-avri classified as Phonikud Hebrew');
  assert(classifyVoice('edge-he-hila') === 'phonikud_hebrew', 'edge-he-hila classified as Phonikud Hebrew');
  assert(classifyVoice('apple-evan') === 'apple_native', 'apple-evan classified as Apple native');
  assert(classifyVoice('edge-en-jenny') === 'edge_ai_english', 'edge-en-jenny classified as Edge AI English');

  // 24. Speed Stepper & Formatting (Ticket 05)
  console.log('\n--- 24. Speed Stepper & Formatting ---');

  function stepSpeedWithFormat(current, delta) {
    const min = 0.5;
    const max = 2.5;
    const stepped = Math.round(Math.min(Math.max(current + delta, min), max) * 10) / 10;
    return {
      value: stepped,
      formatted: stepped.toFixed(1) + 'x'
    };
  }

  assert(stepSpeedWithFormat(1.0, 0.1).formatted === '1.1x', '1.0 + 0.1 = 1.1x');
  assert(stepSpeedWithFormat(1.0, -0.1).formatted === '0.9x', '1.0 - 0.1 = 0.9x');
  assert(stepSpeedWithFormat(2.5, 0.1).formatted === '2.5x', 'Speed clamped at 2.5x max');
  assert(stepSpeedWithFormat(0.5, -0.1).formatted === '0.5x', 'Speed clamped at 0.5x min');
  assert(stepSpeedWithFormat(1.9, 0.1).formatted === '2.0x', 'Rounding handles floating point 1.9 + 0.1');

  // 25. Settings Live Preview Sample Resolution (Ticket 05)
  console.log('\n--- 25. Settings Live Preview Resolution ---');

  function getPreviewSample(voiceId) {
    const isHe = voiceId.includes('he') || voiceId.includes('avri') || voiceId.includes('hila');
    return {
      lang: isHe ? 'he' : 'en',
      sample: isHe
        ? "שלום! זוהי הקראה טבעית בעברית עם פוניקוד."
        : "Hello! This is Guy Reader with Kokoro-82M neural speech."
    };
  }

  assert(getPreviewSample('af_sarah').lang === 'en', 'Sarah preview is in English');
  assert(getPreviewSample('af_sarah').sample.includes('Kokoro-82M'), 'Sarah sample mentions Kokoro-82M');
  assert(getPreviewSample('edge-he-avri').lang === 'he', 'Avri preview is in Hebrew');
  assert(getPreviewSample('edge-he-avri').sample.includes('פוניקוד'), 'Avri sample is Hebrew Phonikud');

  console.log(`UI Logic & Extractor tests: ${testsPassed} / ${testsRun} passed\n`);
  if (testsPassed !== testsRun) {
    throw new Error("Some tests failed!");
  }
})();
