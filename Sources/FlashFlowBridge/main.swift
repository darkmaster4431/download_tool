import AppKit
import Foundation

private struct BridgeMessage: Codable {
    let url: String
    let filename: String?
    let headers: [String: String]?
}

private struct BridgeResponse: Codable {
    let ok: Bool
    let error: String?
}

private func readMessage() throws -> Data {
    let input = FileHandle.standardInput
    guard let lengthData = try input.read(upToCount: 4), lengthData.count == 4 else {
        throw CocoaError(.fileReadCorruptFile)
    }
    let length = lengthData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
    guard length > 0, length <= 8 * 1_024 * 1_024,
          let payload = try input.read(upToCount: Int(length)), payload.count == Int(length) else {
        throw CocoaError(.fileReadTooLarge)
    }
    return payload
}

private func writeResponse(_ response: BridgeResponse) {
    guard let payload = try? JSONEncoder().encode(response) else { return }
    var length = UInt32(payload.count).littleEndian
    let prefix = Data(bytes: &length, count: 4)
    try? FileHandle.standardOutput.write(contentsOf: prefix)
    try? FileHandle.standardOutput.write(contentsOf: payload)
}

do {
    let payload = try readMessage()
    let message = try JSONDecoder().decode(BridgeMessage.self, from: payload)
    guard let source = URL(string: message.url), ["http", "https"].contains(source.scheme?.lowercased() ?? "") else {
        throw CocoaError(.validationMissingMandatoryProperty)
    }

    let environment = ProcessInfo.processInfo.environment
    let support = environment["FLASHFLOW_BRIDGE_INBOX"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FlashFlow/Inbox", isDirectory: true)
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    let identifier = UUID()
    let requestURL = support.appendingPathComponent(identifier.uuidString).appendingPathExtension("json")
    try payload.write(to: requestURL, options: .atomic)

    var components = URLComponents()
    components.scheme = "flashflow"
    components.host = "import"
    components.queryItems = [URLQueryItem(name: "id", value: identifier.uuidString)]
    if environment["FLASHFLOW_BRIDGE_NO_OPEN"] != "1" {
        guard let openURL = components.url, NSWorkspace.shared.open(openURL) else {
            throw CocoaError(.featureUnsupported)
        }
    }
    writeResponse(BridgeResponse(ok: true, error: nil))
} catch {
    writeResponse(BridgeResponse(ok: false, error: error.localizedDescription))
    exit(1)
}
