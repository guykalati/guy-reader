document.addEventListener('DOMContentLoaded', () => {
  const btnReadArticle = document.getElementById('btnReadArticle');
  const btnReadSelection = document.getElementById('btnReadSelection');
  const statusNotice = document.getElementById('statusNotice');

  function showStatus(text, isError = false) {
    if (!statusNotice) return;
    statusNotice.textContent = text;
    statusNotice.className = 'status-notice' + (isError ? ' error' : '');
    statusNotice.style.display = 'block';
  }

  async function sendToActiveTab(action) {
    showStatus('Connecting to page...');

    let tabs;
    try {
      tabs = await chrome.tabs.query({ active: true, currentWindow: true });
    } catch (e) {
      showStatus('Cannot access active tab.', true);
      return;
    }

    const tab = tabs && tabs[0];
    if (!tab || !tab.id) {
      showStatus('No active browser tab found.', true);
      return;
    }

    if (!tab.url || tab.url.startsWith('chrome://') || tab.url.startsWith('brave://') || tab.url.startsWith('edge://') || tab.url.startsWith('about:') || tab.url.startsWith('chrome-extension://')) {
      showStatus('Guy_reader cannot run on internal browser pages. Please open an article or web page.', true);
      return;
    }

    async function trySendMessage() {
      return await chrome.tabs.sendMessage(tab.id, { action });
    }

    let response = null;
    try {
      response = await trySendMessage();
    } catch (err) {
      // Content script is not running yet on this open tab; inject it dynamically
      showStatus('Loading reader into webpage...');
      try {
        if (chrome.scripting) {
          await chrome.scripting.insertCSS({ target: { tabId: tab.id }, files: ['content.css'] }).catch(() => {});
          await chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ['content.js'] }).catch(() => {});
          await new Promise(r => setTimeout(r, 120));
          response = await trySendMessage();
        }
      } catch (injectErr) {
        console.error('Script injection error:', injectErr);
        showStatus('Please refresh this webpage once and click again.', true);
        return;
      }
    }

    if (response && response.success) {
      window.close();
    } else {
      showStatus('Starting speech playback...');
      setTimeout(() => window.close(), 400);
    }
  }

  btnReadArticle.addEventListener('click', () => {
    sendToActiveTab('read-from-start');
  });

  btnReadSelection.addEventListener('click', () => {
    sendToActiveTab('read-from-selection');
  });
});
