import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var manager: DownloadManager
    @State private var input = ""
    @State private var isDropTarget = false
    @State private var showingBrowserSetup = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if manager.records.isEmpty {
                emptyState
            } else {
                taskList
            }
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("提示", isPresented: Binding(
            get: { manager.lastMessage != nil },
            set: { if !$0 { manager.lastMessage = nil } }
        )) {
            Button("知道了") { manager.lastMessage = nil }
        } message: {
            Text(manager.lastMessage ?? "")
        }
        .sheet(item: $manager.hashResult) { result in
            HashResultView(result: result)
        }
        .sheet(isPresented: $showingBrowserSetup) {
            BrowserSetupView().environmentObject(manager)
        }
        .onOpenURL { manager.handleOpenURL($0) }
        .onDrop(of: [.fileURL, .url, .plainText], isTargeted: $isDropTarget, perform: handleDrop)
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.orange)
                Text("FlashFlow")
                    .font(.title2.weight(.semibold))
                Spacer()
                Picker("连接", selection: $manager.connectionCount) {
                    Text("自动").tag(0)
                    ForEach([1, 2, 4, 8, 12, 16], id: \.self) { Text("\($0) 连接").tag($0) }
                }
                .frame(width: 120)
            }

            HStack(spacing: 8) {
                TextField("粘贴 HTTP、Magnet、Torrent 或 Metalink", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addInput)
                Button(action: addInput) {
                    Label("新建下载", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
    }

    private var taskList: some View {
        List {
            ForEach(manager.records) { record in
                TaskRow(record: record)
                    .environmentObject(manager)
            }
        }
        .listStyle(.inset)
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.orange, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(12)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.circle.dotted")
                .font(.system(size: 58, weight: .light))
                .foregroundStyle(.secondary)
            Text("把下载链接或 .torrent 文件拖到这里")
                .font(.title3.weight(.medium))
            Text("HTTP 自动分片；Magnet、Torrent 与 Metalink 由本机 BT 引擎处理")
                .foregroundStyle(.secondary)
            Text("首次使用 BT：brew install aria2")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.orange.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.orange, style: StrokeStyle(lineWidth: 3, dash: [8])))
                    .padding(12)
            }
        }
    }

    private var footer: some View {
        HStack {
            Image(systemName: "folder")
            Text(manager.destinationDirectory)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            Spacer()
            Button("浏览器接管…") { showingBrowserSetup = true }
            Button("更改目录…") { manager.chooseDestination() }
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .frame(height: 38)
    }

    private func addInput() {
        let value = input
        input = ""
        manager.add(value)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                    else if let value = item as? URL { url = value }
                    else { url = nil }
                    if let url { Task { @MainActor in manager.addFile(url) } }
                }
                return true
            }
            if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                    if let value = value as? NSString {
                        Task { @MainActor in manager.add(String(value)) }
                    }
                }
                return true
            }
        }
        return false
    }
}

private struct TaskRow: View {
    @EnvironmentObject private var manager: DownloadManager
    let record: DownloadRecord

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: record.kind.symbol)
                .font(.system(size: 23))
                .foregroundStyle(record.status == .failed ? .red : .orange)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(record.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(record.kind.title)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.12), in: Capsule())
                    Spacer()
                    Text(statusText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(record.status == .failed ? .red : .secondary)
                }

                ProgressView(value: record.progress)
                    .opacity(record.totalBytes > 0 ? 1 : 0.35)

                if let error = record.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            controls
        }
        .padding(.vertical, 7)
        .contextMenu {
            if record.status == .completed {
                Button("在 Finder 中显示") { manager.reveal(record) }
                Menu("哈希校验") {
                    ForEach(FileHashAlgorithm.allCases) { algorithm in
                        Button(algorithm.title) { manager.calculateHash(record, algorithm: algorithm) }
                    }
                }
                .disabled(!manager.canHash(record) || manager.hashingRecordID == record.id)
            }
            Button("删除任务", role: .destructive) { manager.remove(record.id) }
        }
    }

    @ViewBuilder
    private var controls: some View {
        if record.status == .downloading {
            Button { manager.pause(record.id) } label: { Image(systemName: "pause.fill") }
                .buttonStyle(.borderless)
        } else if [.paused, .failed, .queued].contains(record.status) {
            Button { manager.start(record.id) } label: { Image(systemName: "play.fill") }
                .buttonStyle(.borderless)
        } else {
            Button { manager.reveal(record) } label: { Image(systemName: "folder") }
                .buttonStyle(.borderless)
        }
    }

    private var statusText: String {
        if record.status == .downloading {
            let size = record.totalBytes > 0 ? "\(record.completedBytes.fileSizeText) / \(record.totalBytes.fileSizeText)" : record.completedBytes.fileSizeText
            let connections = record.activeConnections.map { "  ·  \($0)连接" } ?? ""
            return "\(size)  ·  \(record.bytesPerSecond.fileSizeText)/s\(connections)"
        }
        return record.status.title
    }
}

private struct HashResultView: View {
    @Environment(\.dismiss) private var dismiss
    let result: FileHashResult
    @State private var expected = ""

    private var normalizedExpected: String {
        expected.lowercased().filter { $0.isHexDigit }
    }

    private var comparison: Bool? {
        guard !normalizedExpected.isEmpty else { return nil }
        return normalizedExpected == result.digest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(result.algorithm.title) 校验")
                .font(.title2.weight(.semibold))
            Text(result.filename)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(result.digest)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            TextField("粘贴期望的 \(result.algorithm.title) 值进行对比", text: $expected)
                .textFieldStyle(.roundedBorder)
            if let comparison {
                Label(comparison ? "校验一致" : "校验不一致", systemImage: comparison ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .foregroundStyle(comparison ? .green : .red)
            }
            HStack {
                Spacer()
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.digest, forType: .string)
                }
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
