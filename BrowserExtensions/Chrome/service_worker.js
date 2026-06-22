const HOST = "local.flashflow.bridge";
const active = new Set();

function basename(value) {
  return (value || "").split(/[\\/]/).pop() || undefined;
}

async function resumeSafely(id) {
  try { await chrome.downloads.resume(id); } catch (_) {}
}

chrome.downloads.onCreated.addListener(async (item) => {
  const settings = await chrome.storage.local.get({ enabled: true });
  if (!settings.enabled || active.has(item.id) || item.byExtensionId === chrome.runtime.id) return;

  const url = item.finalUrl || item.url;
  if (!/^https?:\/\//i.test(url)) return;
  active.add(item.id);

  try { await chrome.downloads.pause(item.id); } catch (_) {}
  const headers = { "User-Agent": navigator.userAgent };
  if (item.referrer) headers.Referer = item.referrer;

  chrome.runtime.sendNativeMessage(HOST, {
    url,
    filename: basename(item.filename),
    headers
  }, async (response) => {
    const failed = chrome.runtime.lastError || !response || !response.ok;
    if (failed) {
      await resumeSafely(item.id);
    } else {
      try { await chrome.downloads.cancel(item.id); } catch (_) {}
      try { await chrome.downloads.erase({ id: item.id }); } catch (_) {}
    }
    active.delete(item.id);
  });
});
