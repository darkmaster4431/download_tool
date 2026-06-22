const DOWNLOAD_EXTENSIONS = /\.(dmg|pkg|zip|iso|tar|gz|xz|7z|rar|exe|msi|mp4|mkv|mov|mp3|flac|pdf)(?:$|[?#])/i;

document.addEventListener("click", async (event) => {
  if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
  const anchor = event.target.closest?.("a[href]");
  if (!anchor) return;
  const url = anchor.href;
  if (!/^https?:\/\//i.test(url) || (!anchor.hasAttribute("download") && !DOWNLOAD_EXTENSIONS.test(url))) return;

  event.preventDefault();
  try {
    const response = await browser.runtime.sendMessage({
      type: "flashflow-download",
      payload: {
        url,
        filename: anchor.getAttribute("download") || undefined,
        headers: { Referer: location.href, "User-Agent": navigator.userAgent }
      }
    });
    if (!response?.ok) location.assign(url);
  } catch (_) {
    location.assign(url);
  }
}, true);
