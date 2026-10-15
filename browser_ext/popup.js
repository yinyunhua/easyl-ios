const $ = (id) => document.getElementById(id);
chrome.storage.local.get({ extraAds: true, hideStrip: false, bindToken: '' }, (cfg) => {
  $('extraAds').checked = !!cfg.extraAds;
  $('hideStrip').checked = !!cfg.hideStrip;
  $('bindToken').value = cfg.bindToken || '';
});
$('save').addEventListener('click', () => {
  chrome.storage.local.set({
    extraAds: $('extraAds').checked,
    hideStrip: $('hideStrip').checked,
    bindToken: $('bindToken').value.trim(),
  }, () => {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      const id = tabs[0] && tabs[0].id;
      if (id) chrome.tabs.reload(id);
    });
    window.close();
  });
});
