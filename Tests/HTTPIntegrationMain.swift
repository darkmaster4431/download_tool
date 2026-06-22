import Foundation

@main
struct HTTPIntegrationMain {
    static func main() async throws {
        guard (3...4).contains(CommandLine.arguments.count),
              let source = URL(string: CommandLine.arguments[1]) else {
            throw DownloadError.invalidURL
        }
        let destination = URL(fileURLWithPath: CommandLine.arguments[2])
        let downloader = HTTPDownloader()
        try await downloader.download(source: source, destination: destination, connections: 0) { completed, total, _ in
            if completed == total { print("downloaded \(total) bytes") }
        } selectedConnections: { print("selected \($0) connections") }
        if CommandLine.arguments.count == 4 {
            let expected = URL(fileURLWithPath: CommandLine.arguments[3])
            guard try Data(contentsOf: destination) == Data(contentsOf: expected) else {
                throw DownloadError.badRangeLength
            }
            print("HTTP segmented download byte check passed")
        }
    }
}
