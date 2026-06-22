import Foundation

actor Aria2RPC {
    struct Status {
        let state: String
        let total: Int64
        let completed: Int64
        let speed: Int64
        let error: String?
    }

    private var process: Process?
    private let port: Int
    private let secret = UUID().uuidString
    private let session = URLSession(configuration: .ephemeral)

    init(port: Int = 16800) {
        self.port = port
    }

    func ensureStarted(downloadDirectory: String) async throws {
        if process?.isRunning == true { return }
        guard let executable = Self.findExecutable() else { throw DownloadError.aria2Unavailable }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = [
            "--enable-rpc=true",
            "--rpc-listen-all=false",
            "--rpc-listen-port=\(port)",
            "--rpc-secret=\(secret)",
            "--dir=\(downloadDirectory)",
            "--continue=true",
            "--max-concurrent-downloads=5",
            "--max-connection-per-server=8",
            "--split=8",
            "--min-split-size=4M",
            "--file-allocation=none",
            "--enable-dht=true",
            "--enable-dht6=true",
            "--bt-enable-lpd=true",
            "--seed-time=0",
            "--follow-torrent=true",
            "--follow-metalink=true",
            "--console-log-level=warn"
        ]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try proc.run()
        process = proc

        for _ in 0..<20 {
            if (try? await version()) != nil { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        proc.terminate()
        process = nil
        throw DownloadError.aria2("RPC 服务启动失败")
    }

    func add(source: String, kind: DownloadKind, directory: String) async throws -> String {
        try await ensureStarted(downloadDirectory: directory)
        if kind == .torrent, source.lowercased().hasPrefix("file://"), let fileURL = URL(string: source) {
            let data = try Data(contentsOf: fileURL)
            let result = try await call(method: "aria2.addTorrent", params: [data.base64EncodedString(), [], ["dir": directory]])
            guard let gid = result as? String else { throw DownloadError.aria2("无法创建 Torrent 任务") }
            return gid
        }

        let result = try await call(method: "aria2.addUri", params: [[source], ["dir": directory]])
        guard let gid = result as? String else { throw DownloadError.aria2("无法创建任务") }
        return gid
    }

    func status(gid: String) async throws -> Status {
        let keys = ["status", "totalLength", "completedLength", "downloadSpeed", "errorMessage"]
        let result = try await call(method: "aria2.tellStatus", params: [gid, keys])
        guard let dictionary = result as? [String: Any] else { throw DownloadError.aria2("任务状态无效") }
        return Status(
            state: dictionary["status"] as? String ?? "error",
            total: Int64(dictionary["totalLength"] as? String ?? "0") ?? 0,
            completed: Int64(dictionary["completedLength"] as? String ?? "0") ?? 0,
            speed: Int64(dictionary["downloadSpeed"] as? String ?? "0") ?? 0,
            error: dictionary["errorMessage"] as? String
        )
    }

    func pause(gid: String) async throws {
        _ = try await call(method: "aria2.forcePause", params: [gid])
    }

    func unpause(gid: String) async throws {
        _ = try await call(method: "aria2.unpause", params: [gid])
    }

    private func version() async throws -> Any {
        try await call(method: "aria2.getVersion", params: [])
    }

    private func call(method: String, params: [Any]) async throws -> Any {
        guard let url = URL(string: "http://127.0.0.1:\(port)/jsonrpc") else { throw DownloadError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var authorizedParams: [Any] = ["token:\(secret)"]
        authorizedParams.append(contentsOf: params)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": method,
            "params": authorizedParams
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DownloadError.aria2("RPC 请求失败")
        }
        if let error = object["error"] as? [String: Any] {
            throw DownloadError.aria2(error["message"] as? String ?? "未知错误")
        }
        return object["result"] as Any
    }

    private static func findExecutable() -> String? {
        let candidates = [
            "/opt/homebrew/bin/aria2c",
            "/usr/local/bin/aria2c",
            "/usr/bin/aria2c"
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }
}
