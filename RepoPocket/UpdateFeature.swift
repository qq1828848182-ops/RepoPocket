import SwiftUI
import UIKit
import ZIPFoundation

@MainActor final class UpdateChecker: ObservableObject {
    @Published var checking = false
    @Published var message = ""
    @Published var release: AppUpdateRelease?
    @Published var downloaded: URL?
    @Published var downloading = false
    @Published var progress: Double = 0
    private var downloadTask: URLSessionDownloadTask?
    private var downloadSession: URLSession?
    private var delegate: UpdateDownloadDelegate?
    func check() async {
        guard !checking, !downloading else { return }
        checking = true; release = nil; downloaded = nil; message = ""; defer { checking = false }
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/wm0104/RepoPocket/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("RepoPocket", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 30
            let config = URLSessionConfiguration.ephemeral
            config.urlCredentialStorage = nil; config.httpCookieStorage = nil
            let session = URLSession(configuration: config); defer { session.finishTasksAndInvalidate() }
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw AppError(text: AppUpdateRules.statusError(status)) }
            let value = try JSONDecoder().decode(AppUpdateRelease.self, from: data)
            guard value.html_url.scheme == "https", value.html_url.host == "github.com", value.html_url.path.hasPrefix("/wm0104/RepoPocket/releases/") else { throw AppError(text: "发布页地址不可信。") }
            let local = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
            if try AppUpdateRules.isNewer(value, local: local, localBuild: build) {
                release = value
                message = "发现正式版本 \(value.tag_name)。由你选择更新，不会自动安装。"
            } else { message = "当前 \(local)（build \(build)）已无更新的正式版本。发布标签未提供 build 时不推断同版本构建更新。" }
        } catch { message = "检查更新失败：\(error.localizedDescription)" }
    }
    func ignore() { release = nil; message = "本次不更新。仅手动检查，不会在每次进入时弹出。" }
    func cancelDownload() { downloadTask?.cancel() }
    func download() {
        guard !downloading, let release, let source = release.ipaURL else { message = "未找到唯一可信的 RepoPocket IPA 附件，请查看发布页。"; return }
        downloading = true; progress = 0; downloaded = nil; message = "正在下载到本机，完成后校验 IPA。"
        let handler = UpdateDownloadDelegate(progress: { [weak self] value in Task { @MainActor in self?.progress = value } }, completion: { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                defer { self.downloading = false; self.downloadTask = nil; self.downloadSession?.finishTasksAndInvalidate(); self.downloadSession = nil; self.delegate = nil }
                do {
                    let file = try result.get()
                    do {
                        let archive = try Archive(url: file, accessMode: .read)
                        guard archive.contains(where: { $0.path.hasPrefix("Payload/") && $0.path.hasSuffix(".app/Info.plist") }) else { throw AppError(text: "下载内容不是有效的 IPA（缺少 Payload App）。") }
                        // Exercise CRC validation without extracting untrusted paths to disk.
                        for entry in archive { _ = try archive.extract(entry, consumer: { _ in }) }
                        let checksumName = source.lastPathComponent + ".sha256"
                        if let checksum = release.assets.first(where: { $0.name == checksumName }) {
                            guard checksum.browser_download_url.scheme == "https", checksum.browser_download_url.host == "github.com", checksum.browser_download_url.path.hasPrefix("/wm0104/RepoPocket/releases/download/") else { throw AppError(text: "SHA256 附件地址不可信。") }
                            let (data, response) = try await URLSession.shared.data(from: checksum.browser_download_url)
                            guard (response as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data, encoding: .utf8), let expected = text.split(whereSeparator: { $0.isWhitespace }).first, expected.count == 64, expected.allSatisfy({ $0.isHexDigit }) else { throw AppError(text: "官方 SHA256 附件无效或下载失败。") }
                            guard try LocalStore.snapshotFileSHA256(file) == expected.lowercased() else { throw AppError(text: "IPA SHA256 与官方附件不符，已阻止安装。") }
                            self.message = "IPA ZIP/CRC 及官方 SHA256 已验证。"
                        } else { self.message = "IPA ZIP/CRC 已验证；发布未提供 SHA256，无法验证官方摘要。" }
                        self.downloaded = file
                        self.message += " 可分享已下载文件给 TrollStore，或使用官方远端 URL 接口（TrollStore 会再次下载）。安装确认由 TrollStore 处理。"
                    } catch { try? FileManager.default.removeItem(at: file); throw error }
                } catch { self.message = (error as? URLError)?.code == .cancelled ? "已取消下载。" : "下载/校验失败：\(error.localizedDescription)" }
            }
        })
        delegate = handler
        let config = URLSessionConfiguration.ephemeral; config.urlCredentialStorage = nil; config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: handler, delegateQueue: nil)
        downloadSession = session; downloadTask = session.downloadTask(with: source); downloadTask?.resume()
    }
    func openTrollStore() {
        guard downloaded != nil, let url = release?.ipaURL else { return }
        var components = URLComponents(); components.scheme = "apple-magnifier"; components.host = "install"
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        guard let install = components.url else { return }
        UIApplication.shared.open(install, options: [:]) { [weak self] opened in
            Task { @MainActor in self?.message = opened ? "已请求打开官方安装接口；TrollStore 将重新下载远端 IPA 并显示安装确认。若打开的是放大镜，请使用分享已下载 IPA。" : "无法打开安装接口，请分享已下载 IPA 给 TrollStore。" }
        }
    }
}
final class UpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let progress: (Double) -> Void
    let completion: (Result<URL, Error>) -> Void
    private var result: Result<URL, Error>?
    init(progress: @escaping (Double) -> Void, completion: @escaping (Result<URL, Error>) -> Void) { self.progress = progress; self.completion = completion }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) { if totalBytesExpectedToWrite > 0 { progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) } }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else { throw AppError(text: "IPA 下载 HTTP 状态无效。") }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RepoPocket-update-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("RepoPocket.ipa")
            try FileManager.default.moveItem(at: location, to: file); result = .success(file)
        } catch { result = .failure(error) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { completion(error.map { .failure($0) } ?? result ?? .failure(AppError(text: "下载未生成文件。"))) }
}
struct AppUpdateSection: View {
    @StateObject private var checker = UpdateChecker()
    @State private var share: SharedFile?
    var body: some View {
        Group {
            Button(checker.checking ? "检查中…" : "检查应用更新") { Task { await checker.check() } }.disabled(checker.checking || checker.downloading)
            if !checker.message.isEmpty { Text(checker.message).font(.caption).textSelection(.enabled) }
            Link("打开 RepoPocket 官方仓库下载页", destination: URL(string: "https://github.com/wm0104/RepoPocket/releases")!)
            if let release = checker.release {
                Link("查看正式发布 \(release.tag_name)", destination: release.html_url)
                if let ipa = release.ipaURL { Link("到官方仓库下载 IPA（可靠兜底）", destination: ipa) }
                Text("适配官方 TrollStore（com.opa334.TrollStore），其他修改版未验证。OTA 接口按官方文档实现，设备安装转交尚未真机验证。") .font(.caption)
                if checker.downloaded == nil {
                    Button("更新：下载 IPA") { checker.download() }.disabled(checker.downloading || release.ipaURL == nil)
                    Button("不接受本次更新") { checker.ignore() }.disabled(checker.downloading)
                }
            }
            if checker.downloading { ProgressView(value: checker.progress); Button("取消下载", role: .cancel) { checker.cancelDownload() } }
            if let file = checker.downloaded {
                Button("分享已下载 IPA 给 TrollStore") { share = SharedFile(url: file) }
                Button("打开 TrollStore 安装（远端重新下载）") { checker.openTrollStore() }
            }
        }.sheet(item: $share) { ShareSheet(url: $0.url) }
    }
}
