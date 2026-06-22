browser.runtime.onMessage.addListener(async (message) => {
  if (!message || message.type !== "flashflow-download") return { ok: false };
  return browser.runtime.sendNativeMessage("local.flashflow.mac", message.payload);
});
