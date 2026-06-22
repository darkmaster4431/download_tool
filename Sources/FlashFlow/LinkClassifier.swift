import Foundation

enum LinkClassifier {
    static func classify(_ rawInput: String) -> ClassifiedLink {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if input.lowercased().hasPrefix("thunder://"),
           let decoded = decodeThunder(String(input.dropFirst("thunder://".count))) {
            let nested = classify(decoded)
            return ClassifiedLink(
                original: input,
                normalized: nested.normalized,
                kind: nested.kind,
                suggestedName: nested.suggestedName
            )
        }

        let lower = input.lowercased()
        if lower.hasPrefix("magnet:?") {
            return ClassifiedLink(
                original: input,
                normalized: input,
                kind: .magnet,
                suggestedName: magnetName(input) ?? "磁力下载"
            )
        }

        if lower.hasPrefix("ed2k://") {
            return ClassifiedLink(original: input, normalized: input, kind: .ed2k, suggestedName: ed2kName(input) ?? "eD2k 下载")
        }

        if let fileURL = localFileURL(input) {
            let ext = fileURL.pathExtension.lowercased()
            let kind: DownloadKind = ext == "torrent" ? .torrent : (["meta4", "metalink"].contains(ext) ? .metalink : .unknown)
            return ClassifiedLink(original: input, normalized: fileURL.absoluteString, kind: kind, suggestedName: fileURL.lastPathComponent)
        }

        guard let url = URL(string: input), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return ClassifiedLink(original: input, normalized: input, kind: .unknown, suggestedName: "未识别任务")
        }

        let ext = url.pathExtension.lowercased()
        let kind: DownloadKind
        if ext == "torrent" {
            kind = .torrent
        } else if ["meta4", "metalink"].contains(ext) {
            kind = .metalink
        } else {
            kind = .http
        }

        let rawName = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        let name = rawName.isEmpty ? "下载-\(UUID().uuidString.prefix(8))" : rawName
        return ClassifiedLink(original: input, normalized: input, kind: kind, suggestedName: name.safeFilename)
    }

    private static func localFileURL(_ input: String) -> URL? {
        if input.lowercased().hasPrefix("file://") {
            return URL(string: input)
        }
        if input.hasPrefix("/") {
            return URL(fileURLWithPath: input)
        }
        return nil
    }

    private static func decodeThunder(_ encoded: String) -> String? {
        guard let data = Data(base64Encoded: encoded), var value = String(data: data, encoding: .utf8) else { return nil }
        if value.hasPrefix("AA") && value.hasSuffix("ZZ") {
            value.removeFirst(2)
            value.removeLast(2)
        }
        return value
    }

    private static func magnetName(_ value: String) -> String? {
        guard let components = URLComponents(string: value) else { return nil }
        return components.queryItems?.first(where: { $0.name == "dn" })?.value?.safeFilename
    }

    private static func ed2kName(_ value: String) -> String? {
        let parts = value.split(separator: "|")
        guard parts.count > 2 else { return nil }
        return String(parts[2]).removingPercentEncoding?.safeFilename
    }
}
