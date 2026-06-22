import Foundation

enum DownloadKind: String, Codable, CaseIterable {
    case http
    case magnet
    case torrent
    case metalink
    case ed2k
    case unknown

    var title: String {
        switch self {
        case .http: return "HTTP"
        case .magnet: return "Magnet"
        case .torrent: return "Torrent"
        case .metalink: return "Metalink"
        case .ed2k: return "eD2k"
        case .unknown: return "未知"
        }
    }

    var symbol: String {
        switch self {
        case .http: return "globe"
        case .magnet: return "magnet"
        case .torrent: return "point.3.connected.trianglepath.dotted"
        case .metalink: return "link.badge.plus"
        case .ed2k: return "network"
        case .unknown: return "questionmark.circle"
        }
    }
}

enum DownloadStatus: String, Codable {
    case queued
    case downloading
    case paused
    case completed
    case failed

    var title: String {
        switch self {
        case .queued: return "等待中"
        case .downloading: return "下载中"
        case .paused: return "已暂停"
        case .completed: return "已完成"
        case .failed: return "失败"
        }
    }
}

struct DownloadRecord: Identifiable, Codable, Equatable {
    let id: UUID
    var source: String
    var kind: DownloadKind
    var name: String
    var destinationDirectory: String
    var status: DownloadStatus
    var totalBytes: Int64
    var completedBytes: Int64
    var bytesPerSecond: Int64
    var errorMessage: String?
    var createdAt: Date
    var activeConnections: Int? = nil
    var requestHeaders: [String: String]? = nil

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(completedBytes) / Double(totalBytes))
    }

    var destinationURL: URL {
        URL(fileURLWithPath: destinationDirectory, isDirectory: true)
            .appendingPathComponent(name)
    }
}

enum FileHashAlgorithm: String, CaseIterable, Identifiable {
    case sha256
    case sha1
    case md5

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sha256: return "SHA-256"
        case .sha1: return "SHA-1"
        case .md5: return "MD5"
        }
    }
}

struct FileHashResult: Identifiable {
    let id = UUID()
    let filename: String
    let algorithm: FileHashAlgorithm
    let digest: String
}

struct BrowserImportRequest: Codable {
    let url: String
    let filename: String?
    let headers: [String: String]?
}

struct ClassifiedLink: Equatable {
    let original: String
    let normalized: String
    let kind: DownloadKind
    let suggestedName: String
}

enum DownloadError: LocalizedError {
    case invalidURL
    case unsupported(String)
    case invalidResponse
    case serverChanged
    case rangeNotHonored
    case badRangeLength
    case aria2Unavailable
    case aria2(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "链接格式无效"
        case .unsupported(let value): return "暂不支持：\(value)"
        case .invalidResponse: return "服务器响应无效"
        case .serverChanged: return "服务器文件已变化，无法继续断点任务"
        case .rangeNotHonored: return "服务器未按要求返回文件分片"
        case .badRangeLength: return "服务器返回的分片长度不正确"
        case .aria2Unavailable: return "BT 引擎不可用，请先安装 aria2（brew install aria2）"
        case .aria2(let message): return "aria2：\(message)"
        }
    }
}

extension Int64 {
    var fileSizeText: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension String {
    var safeFilename: String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = components(separatedBy: forbidden).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "未命名下载" : String(cleaned.prefix(180))
    }
}
