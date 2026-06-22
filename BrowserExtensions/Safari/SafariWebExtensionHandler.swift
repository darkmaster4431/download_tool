import AppKit
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        var response: [String: Any] = ["ok": false]

        if let message,
           JSONSerialization.isValidJSONObject(message),
           let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.local.flashflow") {
            do {
                let inbox = container.appendingPathComponent("Inbox", isDirectory: true)
                try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
                let identifier = UUID()
                let data = try JSONSerialization.data(withJSONObject: message)
                try data.write(to: inbox.appendingPathComponent(identifier.uuidString).appendingPathExtension("json"), options: .atomic)
                var components = URLComponents()
                components.scheme = "flashflow"
                components.host = "import"
                components.queryItems = [URLQueryItem(name: "id", value: identifier.uuidString)]
                if let url = components.url, NSWorkspace.shared.open(url) { response = ["ok": true] }
            } catch {
                response = ["ok": false, "error": error.localizedDescription]
            }
        }

        let responseItem = NSExtensionItem()
        responseItem.userInfo = [SFExtensionMessageKey: response]
        context.completeRequest(returningItems: [responseItem])
    }
}
