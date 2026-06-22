import AppKit
import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject private var manager: DownloadManager
    @Environment(\.openWindow) private var openWindow

    private var activeRecords: [DownloadRecord] {
        manager.records.filter { $0.status == .downloading }
    }

    var body: some View {
        Button("打开 FlashFlow") {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("o")

        if activeRecords.isEmpty {
            Text("当前没有下载任务")
        } else {
            ForEach(activeRecords.prefix(3)) { record in
                Text("↓ \(record.name)  \(record.bytesPerSecond.fileSizeText)/s")
            }
        }

        Divider()
        Toggle("登录时自动启动", isOn: Binding(
            get: { manager.launchAtLoginEnabled },
            set: { manager.setLaunchAtLogin($0) }
        ))
        Button("浏览器接管设置…") {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("退出 FlashFlow") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
