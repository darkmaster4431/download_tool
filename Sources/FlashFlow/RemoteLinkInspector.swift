import Foundation

enum RemoteLinkInspector {
    static func inspect(_ source: String) async -> DownloadKind? {
        guard let url = URL(string: source), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        let ordinaryExtensions: Set<String> = [
            "dmg", "pkg", "zip", "iso", "exe", "msi", "tar", "gz", "xz", "7z", "rar",
            "mp4", "mkv", "mov", "mp3", "flac", "pdf", "docx", "xlsx"
        ]
        if ordinaryExtensions.contains(url.pathExtension.lowercased()) { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }

        let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        let disposition = http.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        let finalExtension = http.url?.pathExtension.lowercased() ?? ""
        if contentType.contains("bittorrent") || disposition.contains(".torrent") || finalExtension == "torrent" {
            return .torrent
        }
        if contentType.contains("metalink") || disposition.contains(".meta4") || disposition.contains(".metalink") || ["meta4", "metalink"].contains(finalExtension) {
            return .metalink
        }
        return nil
    }
}
