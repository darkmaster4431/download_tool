import CryptoKit
import Foundation

enum FileHasher {
    static func hash(file: URL, algorithm: FileHashAlgorithm) async throws -> String {
        try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }

            switch algorithm {
            case .sha256:
                var hasher = SHA256()
                try consume(handle) { hasher.update(data: $0) }
                return hex(hasher.finalize())
            case .sha1:
                var hasher = Insecure.SHA1()
                try consume(handle) { hasher.update(data: $0) }
                return hex(hasher.finalize())
            case .md5:
                var hasher = Insecure.MD5()
                try consume(handle) { hasher.update(data: $0) }
                return hex(hasher.finalize())
            }
        }.value
    }

    private static func consume(_ handle: FileHandle, update: (Data) -> Void) throws {
        while true {
            try Task.checkCancellation()
            guard let data = try handle.read(upToCount: 4 * 1_024 * 1_024), !data.isEmpty else { return }
            update(data)
        }
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
