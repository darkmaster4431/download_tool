import Foundation

@main
struct HashIntegrationMain {
    static func main() async throws {
        guard CommandLine.arguments.count == 4 else { throw DownloadError.invalidURL }
        let file = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let algorithm = FileHashAlgorithm(rawValue: CommandLine.arguments[2]) else { throw DownloadError.invalidURL }
        let digest = try await FileHasher.hash(file: file, algorithm: algorithm)
        guard digest == CommandLine.arguments[3].lowercased() else {
            throw DownloadError.serverChanged
        }
        print("\(algorithm.title) byte check passed")
    }
}
