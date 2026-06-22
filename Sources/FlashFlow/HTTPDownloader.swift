import Foundation

struct HTTPProbe {
    let totalBytes: Int64?
    let supportsRanges: Bool
    let etag: String?
    let lastModified: String?
}

struct HTTPResumeState: Codable {
    let source: String
    let totalBytes: Int64
    let chunkSize: Int64
    let etag: String?
    let lastModified: String?
    var completedChunks: Set<Int>
}

actor ChunkWriter {
    private let handle: FileHandle

    init(url: URL, length: Int64) throws {
        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil)
        }
        handle = try FileHandle(forUpdating: url)
        try handle.truncate(atOffset: UInt64(length))
    }

    func write(_ data: Data, at offset: Int64) throws {
        try handle.seek(toOffset: UInt64(offset))
        try handle.write(contentsOf: data)
    }

    func close() throws {
        try handle.close()
    }
}

actor ChunkQueue {
    private var pending: [Int]

    init(_ indexes: [Int]) {
        pending = indexes
    }

    func next() -> Int? {
        guard !pending.isEmpty else { return nil }
        return pending.removeFirst()
    }
}

actor ProgressMeter {
    private var completed: Int64
    private let total: Int64
    private var sampleBytes: Int64
    private var sampleDate = Date()
    private var speed: Int64 = 0

    init(completed: Int64, total: Int64) {
        self.completed = completed
        self.total = total
        self.sampleBytes = completed
    }

    func add(_ bytes: Int64) -> (Int64, Int64, Int64) {
        completed += bytes
        let now = Date()
        let elapsed = now.timeIntervalSince(sampleDate)
        if elapsed >= 0.35 {
            speed = Int64(Double(completed - sampleBytes) / elapsed)
            sampleBytes = completed
            sampleDate = now
        }
        return (completed, total, speed)
    }
}

actor ResumeStore {
    private var state: HTTPResumeState
    private let url: URL

    init(state: HTTPResumeState, url: URL) {
        self.state = state
        self.url = url
    }

    func markCompleted(_ index: Int) throws {
        state.completedChunks.insert(index)
        let data = try JSONEncoder().encode(state)
        try data.write(to: url, options: .atomic)
    }

}

final class HTTPDownloader {
    typealias ProgressHandler = (Int64, Int64, Int64) -> Void
    typealias ConnectionHandler = (Int) -> Void
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        configuration.httpMaximumConnectionsPerHost = 16
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    func download(
        source: URL,
        destination: URL,
        connections: Int,
        headers: [String: String]? = nil,
        progress: @escaping ProgressHandler,
        selectedConnections: @escaping ConnectionHandler = { _ in }
    ) async throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let probe = try await probe(source, headers: headers)

        if probe.supportsRanges, let total = probe.totalBytes, total >= 2 * 1_024 * 1_024 {
            try await segmentedDownload(
                source: source,
                destination: destination,
                total: total,
                connections: max(0, min(16, connections)),
                headers: headers,
                probe: probe,
                progress: progress,
                selectedConnections: selectedConnections
            )
        } else {
            selectedConnections(1)
            var request = URLRequest(url: source)
            headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            let (temporary, response) = try await session.download(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw DownloadError.invalidResponse
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temporary, to: destination)
            let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            progress(size, size, 0)
        }
    }

    private func probe(_ url: URL, headers: [String: String]?) async throws -> HTTPProbe {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DownloadError.invalidResponse }
        let headerLength = http.expectedContentLength > 0 ? http.expectedContentLength : nil
        return HTTPProbe(
            totalBytes: headerLength,
            supportsRanges: http.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased().contains("bytes") == true,
            etag: http.value(forHTTPHeaderField: "ETag"),
            lastModified: http.value(forHTTPHeaderField: "Last-Modified")
        )
    }

    private func segmentedDownload(
        source: URL,
        destination: URL,
        total: Int64,
        connections: Int,
        headers: [String: String]?,
        probe: HTTPProbe,
        progress: @escaping ProgressHandler,
        selectedConnections: @escaping ConnectionHandler
    ) async throws {
        let partURL = destination.appendingPathExtension("ffpart")
        let resumeURL = destination.appendingPathExtension("ffresume")
        let chunkSize: Int64 = 4 * 1_024 * 1_024
        let chunkCount = Int((total + chunkSize - 1) / chunkSize)
        var state = try loadOrCreateResume(
            at: resumeURL,
            source: source,
            total: total,
            chunkSize: chunkSize,
            probe: probe
        )

        if !FileManager.default.fileExists(atPath: partURL.path) {
            state.completedChunks.removeAll()
        }

        let initialBytes = state.completedChunks.reduce(Int64(0)) { value, index in
            let start = Int64(index) * chunkSize
            return value + max(0, min(chunkSize, total - start))
        }
        progress(initialBytes, total, 0)

        let writer = try ChunkWriter(url: partURL, length: total)
        let meter = ProgressMeter(completed: initialBytes, total: total)
        let resumeStore = ResumeStore(state: state, url: resumeURL)
        let pending = (0..<chunkCount).filter { !state.completedChunks.contains($0) }
        let chosenConnections = connections == 0 ? min(2, max(1, pending.count)) : max(1, connections)

        selectedConnections(chosenConnections)
        if !pending.isEmpty {
            _ = try await downloadBatch(
                indexes: pending, parallelism: chosenConnections, source: source, total: total, chunkSize: chunkSize,
                headers: headers, etag: probe.etag, writer: writer, resumeStore: resumeStore, meter: meter, progress: progress
            )
        }

        try await writer.close()
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: partURL, to: destination)
        try? FileManager.default.removeItem(at: resumeURL)
        progress(total, total, 0)
    }

    private func downloadBatch(
        indexes: [Int],
        parallelism: Int,
        source: URL,
        total: Int64,
        chunkSize: Int64,
        headers: [String: String]?,
        etag: String?,
        writer: ChunkWriter,
        resumeStore: ResumeStore,
        meter: ProgressMeter,
        progress: @escaping ProgressHandler
    ) async throws -> Double {
        guard !indexes.isEmpty else { return 0 }
        let queue = ChunkQueue(indexes)
        let plannedBytes = indexes.reduce(Int64(0)) { value, index in
            let start = Int64(index) * chunkSize
            return value + max(0, min(chunkSize, total - start))
        }
        let started = Date()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<min(parallelism, indexes.count) {
                group.addTask { [session] in
                    while let index = await queue.next() {
                        try Task.checkCancellation()
                        let start = Int64(index) * chunkSize
                        let end = min(total - 1, start + chunkSize - 1)
                        let data = try await Self.fetchChunk(session: session, url: source, start: start, end: end, headers: headers, etag: etag)
                        try await writer.write(data, at: start)
                        try await resumeStore.markCompleted(index)
                        let snapshot = await meter.add(Int64(data.count))
                        progress(snapshot.0, snapshot.1, snapshot.2)
                    }
                }
            }
            try await group.waitForAll()
        }
        return Double(plannedBytes) / max(0.001, Date().timeIntervalSince(started))
    }

    private static func fetchChunk(session: URLSession, url: URL, start: Int64, end: Int64, headers: [String: String]?, etag: String?) async throws -> Data {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                var request = URLRequest(url: url)
                headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
                request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                if let etag { request.setValue(etag, forHTTPHeaderField: "If-Range") }
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 206 else {
                    throw DownloadError.rangeNotHonored
                }
                guard data.count == Int(end - start + 1) else { throw DownloadError.badRangeLength }
                return data
            } catch {
                lastError = error
                if attempt < 2 {
                    try await Task.sleep(nanoseconds: UInt64(350_000_000 * (attempt + 1)))
                }
            }
        }
        throw lastError ?? DownloadError.invalidResponse
    }

    private func loadOrCreateResume(
        at url: URL,
        source: URL,
        total: Int64,
        chunkSize: Int64,
        probe: HTTPProbe
    ) throws -> HTTPResumeState {
        if let data = try? Data(contentsOf: url),
           let state = try? JSONDecoder().decode(HTTPResumeState.self, from: data) {
            guard state.source == source.absoluteString,
                  state.totalBytes == total,
                  state.chunkSize == chunkSize,
                  state.etag == probe.etag,
                  state.lastModified == probe.lastModified else {
                try? FileManager.default.removeItem(at: url)
                return HTTPResumeState(source: source.absoluteString, totalBytes: total, chunkSize: chunkSize, etag: probe.etag, lastModified: probe.lastModified, completedChunks: [])
            }
            return state
        }
        return HTTPResumeState(source: source.absoluteString, totalBytes: total, chunkSize: chunkSize, etag: probe.etag, lastModified: probe.lastModified, completedChunks: [])
    }
}
