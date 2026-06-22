import Foundation

enum BrowserIntegrationInstaller {
    static let chromeExtensionID = "dfcefcmamgmoopkghgeabpiidkdpfnle"

    static func installChromeHost() throws {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/FlashFlowBridge")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw DownloadError.unsupported("应用包中缺少 FlashFlowBridge")
        }
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "name": "local.flashflow.bridge",
            "description": "FlashFlow browser download bridge",
            "path": helper.path,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(chromeExtensionID)/"]
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("local.flashflow.bridge.json"), options: .atomic)
    }

}
