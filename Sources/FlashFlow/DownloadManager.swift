import AppKit
import Foundation
import ServiceManagement

@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var records: [DownloadRecord] = []
    @Published var destinationDirectory: String
    @Published var connectionCount = 0
    @Published var lastMessage: String?
    @Published var hashResult: FileHashResult?
    @Published var hashingRecordID: UUID?
    @Published var launchAtLoginEnabled = false

    private var workers: [UUID: Task<Void, Never>] = [:]
    private var ariaGIDs: [UUID: String] = [:]
    private let aria = Aria2RPC()
    private let storeURL: URL

    init() {
        let defaultDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FlashFlow", isDirectory: true).path
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/FlashFlow").path
        destinationDirectory = UserDefaults.standard.string(forKey: "destinationDirectory") ?? defaultDirectory

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FlashFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        storeURL = support.appendingPathComponent("tasks.json")
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        load()
    }

    func add(
        _ rawInput: String,
        startImmediately: Bool = true,
        suggestedName: String? = nil,
        requestHeaders: [String: String]? = nil
    ) {
        let classified = LinkClassifier.classify(rawInput)
        guard classified.kind != .unknown else {
            lastMessage = "无法识别这个链接或文件"
            return
        }

        let record = DownloadRecord(
            id: UUID(),
            source: classified.normalized,
            kind: classified.kind,
            name: (suggestedName ?? classified.suggestedName).safeFilename,
            destinationDirectory: destinationDirectory,
            status: .queued,
            totalBytes: 0,
            completedBytes: 0,
            bytesPerSecond: 0,
            errorMessage: nil,
            createdAt: Date(),
            activeConnections: nil,
            requestHeaders: requestHeaders
        )
        records.insert(record, at: 0)
        save()
        if startImmediately { start(record.id) }
    }

    func addFile(_ url: URL) {
        add(url.absoluteString)
    }

    func handleOpenURL(_ url: URL) {
        guard url.scheme?.lowercased() == "flashflow", url.host == "import",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value,
              let identifier = UUID(uuidString: value) else {
            add(url.absoluteString)
            return
        }
        let localInbox = storeURL.deletingLastPathComponent().appendingPathComponent("Inbox", isDirectory: true)
        let sharedInbox = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.local.flashflow")?
            .appendingPathComponent("Inbox", isDirectory: true)
        let candidates = [localInbox, sharedInbox].compactMap { $0 }
            .map { $0.appendingPathComponent(identifier.uuidString).appendingPathExtension("json") }
        do {
            guard let requestURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let data = try Data(contentsOf: requestURL)
            let request = try JSONDecoder().decode(BrowserImportRequest.self, from: data)
            try? FileManager.default.removeItem(at: requestURL)
            add(request.url, suggestedName: request.filename, requestHeaders: request.headers)
        } catch {
            lastMessage = "浏览器任务导入失败：\(error.localizedDescription)"
        }
    }

    func start(_ id: UUID) {
        guard workers[id] == nil, let record = records.first(where: { $0.id == id }) else { return }
        update(id) {
            $0.status = .downloading
            $0.errorMessage = nil
        }

        workers[id] = Task { [weak self] in
            guard let self else { return }
            do {
                switch record.kind {
                case .http:
                    if let detected = await RemoteLinkInspector.inspect(record.source) {
                        var redirected = record
                        redirected.kind = detected
                        self.update(record.id) { $0.kind = detected }
                        try await self.runAria(redirected)
                    } else {
                        try await self.runHTTP(record)
                    }
                case .magnet, .torrent, .metalink:
                    try await self.runAria(record)
                case .ed2k:
                    throw DownloadError.unsupported("eD2k 将在后续版本加入")
                case .unknown:
                    throw DownloadError.unsupported("未知任务")
                }
                if !Task.isCancelled {
                    self.update(id) {
                        $0.status = .completed
                        $0.bytesPerSecond = 0
                        if $0.totalBytes > 0 { $0.completedBytes = $0.totalBytes }
                    }
                }
            } catch is CancellationError {
                self.update(id) {
                    $0.status = .paused
                    $0.bytesPerSecond = 0
                }
            } catch {
                self.update(id) {
                    $0.status = .failed
                    $0.bytesPerSecond = 0
                    $0.errorMessage = error.localizedDescription
                }
            }
            self.workers[id] = nil
            self.save()
        }
    }

    func pause(_ id: UUID) {
        workers[id]?.cancel()
        workers[id] = nil
        if let gid = ariaGIDs[id] {
            Task { try? await aria.pause(gid: gid) }
        }
        update(id) {
            $0.status = .paused
            $0.bytesPerSecond = 0
        }
    }

    func remove(_ id: UUID) {
        pause(id)
        ariaGIDs[id] = nil
        records.removeAll { $0.id == id }
        save()
    }

    func reveal(_ record: DownloadRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([record.destinationURL])
    }

    func canHash(_ record: DownloadRecord) -> Bool {
        var isDirectory: ObjCBool = false
        return record.status == .completed
            && FileManager.default.fileExists(atPath: record.destinationURL.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    func calculateHash(_ record: DownloadRecord, algorithm: FileHashAlgorithm) {
        guard canHash(record) else {
            lastMessage = "找不到可校验的已下载文件"
            return
        }
        hashingRecordID = record.id
        Task { [weak self] in
            do {
                let digest = try await FileHasher.hash(file: record.destinationURL, algorithm: algorithm)
                self?.hashResult = FileHashResult(filename: record.name, algorithm: algorithm, digest: digest)
            } catch {
                self?.lastMessage = "哈希计算失败：\(error.localizedDescription)"
            }
            self?.hashingRecordID = nil
        }
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            destinationDirectory = url.path
            UserDefaults.standard.set(url.path, forKey: "destinationDirectory")
        }
    }

    func installChromeIntegration() {
        do {
            try BrowserIntegrationInstaller.installChromeHost()
            lastMessage = "Chrome本地桥接器已注册，请继续加载扩展文件夹"
        } catch {
            lastMessage = "Chrome桥接器注册失败：\(error.localizedDescription)"
        }
    }

    func revealChromeExtension() {
        do {
            try BrowserIntegrationInstaller.revealChromeExtension()
        } catch {
            lastMessage = error.localizedDescription
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            lastMessage = "登录启动设置失败：请先把FlashFlow拖入“应用程序”后再试。\n\(error.localizedDescription)"
        }
    }

    private func runHTTP(_ record: DownloadRecord) async throws {
        guard let url = URL(string: record.source) else { throw DownloadError.invalidURL }
        let downloader = HTTPDownloader()
        try await downloader.download(
            source: url,
            destination: record.destinationURL,
            connections: connectionCount,
            headers: record.requestHeaders
        ) { [weak self] completed, total, speed in
            Task { @MainActor in
                self?.update(record.id) {
                    $0.completedBytes = completed
                    $0.totalBytes = total
                    $0.bytesPerSecond = speed
                }
            }
        } selectedConnections: { [weak self] count in
            Task { @MainActor in self?.update(record.id) { $0.activeConnections = count } }
        }
    }

    private func runAria(_ record: DownloadRecord) async throws {
        let gid: String
        if let existing = ariaGIDs[record.id] {
            try await aria.unpause(gid: existing)
            gid = existing
        } else {
            gid = try await aria.add(source: record.source, kind: record.kind, directory: record.destinationDirectory)
        }
        ariaGIDs[record.id] = gid
        while !Task.isCancelled {
            let status = try await aria.status(gid: gid)
            update(record.id) {
                $0.totalBytes = status.total
                $0.completedBytes = status.completed
                $0.bytesPerSecond = status.speed
            }
            switch status.state {
            case "complete": return
            case "error", "removed": throw DownloadError.aria2(status.error ?? status.state)
            case "paused": throw CancellationError()
            default: break
            }
            try await Task.sleep(nanoseconds: 700_000_000)
        }
        throw CancellationError()
    }

    private func update(_ id: UUID, mutation: (inout DownloadRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        mutation(&records[index])
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              var restored = try? JSONDecoder().decode([DownloadRecord].self, from: data) else { return }
        for index in restored.indices where restored[index].status == .downloading {
            restored[index].status = .paused
            restored[index].bytesPerSecond = 0
        }
        records = restored
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
