# FlashFlow

FlashFlow 是一个纯本地的 macOS 多协议下载器原型：

- HTTP/HTTPS：4 MiB动态工作队列、自动档默认2连接、可手动选择1～16连接、Range校验、失败重试和跨启动断点续传。
- Magnet/Torrent：通过本机 aria2 的 JSON-RPC 接入 Tracker、DHT、PEX 与 Web Seed。
- Metalink：通过 aria2 使用多镜像源。
- 自动识别：HTTP、Magnet、`.torrent`、Metalink、Thunder解码及eD2k识别。
- 原生界面：SwiftUI任务列表、拖放、暂停、恢复、速度和进度展示。
- 文件校验：任务右键计算SHA-256、SHA-1或MD5，并可粘贴期望值直接比较。
- Chrome接管：Manifest V3扩展暂停浏览器任务，经应用包内原生桥接器导入FlashFlow；失败时自动退回Chrome。
- Safari接入：提供可转换为Safari Web Extension的共用扩展源和原生处理器源码。
- 后台常驻：关闭主窗口后继续运行，菜单栏可查看活动任务、重新打开窗口、退出及控制登录启动。

## 运行

需要 macOS 13 或更新版本与 Swift 5.10+。HTTP下载不需要任何第三方依赖。

```bash
./scripts/build-app.sh
open dist/FlashFlow.app
```

启用 Magnet、Torrent 和 Metalink：

```bash
brew install aria2
open dist/FlashFlow.app
```

## 测试

```bash
./scripts/test.sh
```

仓库还包含一个本地 Range 服务器和字节级HTTP集成检查入口，见 `Tests/HTTPIntegrationMain.swift`。

## DMG

```bash
./scripts/package-dmg.sh
```

生成 `dist/FlashFlow.dmg`，其中包含FlashFlow和“应用程序”快捷方式。安装后首次打开应用，在“浏览器接管…”中注册Chrome桥接器并加载扩展目录。

## 当前边界

- HTTP和BT来源已经统一到同一个任务界面，但任意HTTP URL与Torrent piece的跨协议合并尚未实现；aria2支持Torrent自带的Web Seed。
- HTTP暂停发生在当前网络请求结束/取消时，已完成的4 MiB块会从sidecar恢复。
- 首版未进行App Sandbox签名与App Store打包；完整Xcode安装后可再生成正式`.app`工程。
- eD2k目前只识别链接，不执行下载。
- Chrome扩展需要在 `chrome://extensions` 中以“加载已解压的扩展程序”安装一次；应用内“浏览器接管…”会注册本地桥接器并显示扩展目录。
- Safari扩展必须由完整Xcode和Apple Developer签名打包；当前环境只有Command Line Tools，因此仓库交付的是可转换、可签名的扩展源。
- 浏览器接管不读取Cookie；依赖登录会话、`blob:`或浏览器内存生成的下载仍由浏览器处理。

## 目录

```text
Sources/FlashFlow/
├── LinkClassifier.swift   链接规范化与协议识别
├── HTTPDownloader.swift   HTTP Range分块内核
├── Aria2RPC.swift         BT/Metalink适配层
├── DownloadManager.swift  统一任务状态与持久化
└── ContentView.swift      SwiftUI界面
BrowserExtensions/
├── Chrome/                Chrome Manifest V3扩展
└── Safari/                Safari Web Extension资源与处理器源码
```
