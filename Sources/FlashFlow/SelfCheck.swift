import Foundation

enum SelfCheck {
    static func run() -> Bool {
        let wrapped = Data("AAhttps://example.com/movie.mp4ZZ".utf8).base64EncodedString()
        let checks: [(String, Bool)] = [
            ("HTTP", LinkClassifier.classify("https://example.com/demo.zip").kind == .http),
            ("Magnet", LinkClassifier.classify("magnet:?xt=urn:btih:abc&dn=Demo").suggestedName == "Demo"),
            ("Torrent", LinkClassifier.classify("/tmp/demo.torrent").kind == .torrent),
            ("Metalink", LinkClassifier.classify("https://example.com/release.meta4").kind == .metalink),
            ("Thunder", LinkClassifier.classify("thunder://\(wrapped)").normalized == "https://example.com/movie.mp4"),
            ("eD2k", LinkClassifier.classify("ed2k://|file|demo.iso|1|A|/").suggestedName == "demo.iso")
        ]
        for check in checks {
            print("\(check.1 ? "✓" : "✗") \(check.0)")
        }
        return checks.allSatisfy(\.1)
    }
}
