import SwiftUI

struct RepositoryReleaseBadge: View {
    let release: Release
    let latestID: Int?
    var body: some View {
        if RepositoryReleaseRules.isLatest(release, latestID: latestID) { Text("Latest").font(.caption).foregroundColor(.green) }
        else if release.prerelease == true { Text("Pre-release").font(.caption).foregroundColor(.orange) }
    }
}
struct RepositoryReleaseLabel: View {
    let release: Release
    let latestID: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(release.name?.isEmpty == false ? release.name! : release.tag_name).lineLimit(2)
            HStack {
                RepositoryReleaseBadge(release: release, latestID: latestID)
                if let text = release.published_at, let date = ISO8601DateFormatter().date(from: text) {
                    Text(date, style: .relative).font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }
}
struct RepositoryReleaseSection: View {
    @ObservedObject var api: GitHub
    let repo: String
    @ObservedObject var state: RepositoryReleaseState
    var body: some View {
        if let count = state.count, count > 0, let recent = state.recent {
            Section {
                NavigationLink { RepositoryReleaseHistory(api: api, repo: repo, state: state) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("发行版 · \(count)", systemImage: "shippingbox")
                        RepositoryReleaseLabel(release: recent, latestID: state.latestID)
                    }.padding(.vertical, 5)
                }.softGroupedRow(top: true, bottom: true)
            }
        } else if let error = state.error {
            Section {
                Button { Task { await state.load(api: api, repo: repo, retry: true) } } label: {
                    Label(error, systemImage: "arrow.clockwise").font(.caption)
                }.softGroupedRow(top: true, bottom: true)
            }
        } else if state.loading {
            Section { ProgressView("载入发行版…").softGroupedRow(top: true, bottom: true) }
        }
    }
}
struct RepositoryReleaseHistory: View {
    @ObservedObject var api: GitHub
    let repo: String
    @ObservedObject var state: RepositoryReleaseState
    var body: some View {
        List {
            ForEach(state.history) { release in
                NavigationLink { RepositoryReleaseDetail(api: api, repo: repo, release: release, latestID: state.latestID) } label: {
                    RepositoryReleaseLabel(release: release, latestID: state.latestID)
                }
            }
            if state.paging { ProgressView("载入历史版本…") }
            if let error = state.historyError { Text(error).font(.caption).foregroundColor(.secondary) }
            if state.hasNext { Button(state.historyError == nil ? "载入更多版本" : "重试") { state.more(api: api, repo: repo) }.disabled(state.paging) }
        }
        .navigationTitle("历史发行版")
        .task { if state.history.isEmpty { state.more(api: api, repo: repo) } }
    }
}
struct RepositoryReleaseDetail: View {
    @ObservedObject var api: GitHub
    let repo: String
    let release: Release
    let latestID: Int?
    @StateObject private var download = RepositoryAssetDownload()
    @State private var share: SharedFile?
    var body: some View {
        List {
            Section {
                RepositoryReleaseLabel(release: release, latestID: latestID)
                Text(release.tag_name).font(.caption).foregroundColor(.secondary)
            }
            Section("更新说明") {
                // Verbatim selectable body preserves the complete notes without executing embedded URLs/HTML.
                Text(release.body?.isEmpty == false ? release.body! : "未提供更新说明。")
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("附件 · \(release.assets.count)") {
                if release.assets.isEmpty { Text("此发行版没有附件。").foregroundColor(.secondary) }
                ForEach(release.assets) { asset in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(asset.name).textSelection(.enabled)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(asset.size), countStyle: .file)).font(.caption).foregroundColor(.secondary)
                        Button("下载到所选文件夹") { download.start(api: api, repo: repo, asset: asset) }
                            .disabled(download.activeID != nil || !api.isCurrentSession)
                    }
                }
            }
            if download.activeID != nil {
                Section {
                    ProgressView(value: download.progress)
                    Button("取消下载", role: .cancel) { download.cancel() }
                }
            }
            if let message = download.message { Section { Text(message).font(.caption).textSelection(.enabled) } }
            if let file = download.saved { Section { Button("系统分享 / 选择应用") { share = SharedFile(url: file) } } }
        }
        .navigationTitle("发行版详情")
        .sheet(item: $share) { ShareSheet(url: $0.url) }
        .onDisappear { download.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: .githubAccountChanged)) { _ in download.reset(); share = nil }
    }
}
