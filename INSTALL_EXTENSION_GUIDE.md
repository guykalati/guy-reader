# How to Use Guy_reader (Brave/Chrome Extension & Mac App)

---

## 🌐 1. Brave / Chrome Extension (For Web Articles like Substack)

### If you already added the extension to Brave:
1. Go to:
   ```
   brave://extensions
   ```
2. Find the card for **Guy_reader - Natural AI Web Reader**.
3. Click the **🔄 Reload (Refresh)** icon in the bottom-right corner of that card.
4. Go back to your Substack article and **refresh the page** (`⌘ + R`).
5. Click the extension icon in your toolbar, then click **"Read Entire Article"** (or press **`Alt + Space`**)!

### If installing for the first time:
1. Open `brave://extensions` (or `chrome://extensions`).
2. Turn ON **Developer mode** in the top-right corner.
3. Click **"Load unpacked"** in the top-left.
4. Select this folder:
   ```
   /Users/gyklty/Desktop/Guy/TTS/extension
   ```
5. Click **Select**.

### How it works on Webpages:
- **Read Entire Article**: Reads the full article from first word to last word.
- **Read from a Click or Selection**: Click the word where you want to begin, then choose "Read from Selection" (or press `Alt + Space`). A highlighted selection also works. Reading continues to the end.
- **Glowing Highlights**: The active sentence and active words glow in lime directly on the webpage.
- **Click-to-Seek**: Click any word anywhere on the webpage to jump the audio immediately to that sentence!
- **Floating Player**: Use the floating pill on the page to pause, resume, change speed, or switch voices.

---

## 💻 2. macOS Desktop App (Guy_reader.app)

The desktop app reads text from any Mac app (Antigravity IDE, Notes, TextEdit, Pages, Slack, Word, PDFs).

### How to Start / Restart:
Double-click:
```
/Users/gyklty/Desktop/Guy/TTS/Launch_Guy_reader.command
```
*(Or run `./start_guy_reader.sh` in Terminal)*

### How to Read Any Content:
1. **Click-to-Read**:
   - Click the text where reading should begin, then click **Read** in Guy_reader. You can also highlight text and press **`Fn + Space`** or **`Control + Space`** (`⌃ + Space`).
   - Guy_reader continues through the remaining accessible text until it finishes or you click **Stop**.
2. **One-Click Paste & Read (`📋`)**:
   - If you copy text (`⌘ + C`), click the **`📋`** button. The Read button does not consume unrelated clipboard text.
3. **Clear Feedback**:
   - If no text was highlighted, the preview bar immediately alerts you with:
     `⚠️ Click the text you want, then click Read. Use Paste for clipboard text.`
     so you are never left guessing!
