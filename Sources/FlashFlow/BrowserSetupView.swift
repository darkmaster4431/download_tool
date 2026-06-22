import AppKit
import SwiftUI

struct BrowserSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var manager: DownloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("浏览器下载接管")
                .font(.title2.weight(.semibold))

            GroupBox("Google Chrome") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("1. 注册本地桥接器。")
                    Text("2. 打开 chrome://extensions，启用开发者模式。")
                    Text("3. 选择“加载已解压的扩展程序”，选中桌面的 FlashFlow-Chrome-Extension 文件夹。")
                    HStack {
                        Button("注册Chrome桥接器") { manager.installChromeIntegration() }
                            .buttonStyle(.borderedProminent)
                        Button("打开扩展管理页") {
                            NSWorkspace.shared.open(URL(string: "chrome://extensions")!)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            GroupBox("Safari") {
                Text("Safari需要由完整Xcode签名的Web Extension容器。兼容扩展源已随项目提供；安装包签名完成前，Safari只能使用扩展内的“发送到FlashFlow”入口，不能像Chrome一样可靠监听全部下载事件。")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }

            Text("隐私：接管信息只写入本机；当前不会读取或导出浏览器Cookie。需要登录态的下载可能仍需浏览器完成。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 650)
    }
}
