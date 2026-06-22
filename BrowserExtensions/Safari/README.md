# Safari Web Extension packaging

Safari requires a signed containing app plus a Safari Web Extension target. The extension cannot be shipped as a loose folder.

With full Xcode installed:

1. Run `xcrun safari-web-extension-converter BrowserExtensions/Safari/Resources --project-location SafariBuild`.
2. Add `SafariWebExtensionHandler.swift` to the generated extension target.
3. Give the app and extension the App Group `group.local.flashflow`.
4. Set the containing app URL scheme to `flashflow`.
5. Sign both targets with the same Apple Developer team, build, then enable the extension in Safari Settings.

Safari does not expose Chrome's reliable `downloads.onCreated` workflow. This first implementation catches explicit download links (`download` attribute or a known downloadable extension); authenticated, JavaScript-generated, `blob:` and response-header-only downloads remain in Safari.
