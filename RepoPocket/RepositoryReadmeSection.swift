import SwiftUI

enum ReadmePreviewRules {
    static let characterLimit = 1800
    static let lineLimit = 24
    static func preview(_ source: String) -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).prefix(lineLimit).joined(separator: "\n")
        return String(lines.prefix(characterLimit))
    }
    static func needsExpansion(_ source: String) -> Bool { preview(source) != source }
}

struct RepositoryReadmeSection: View {
    @ObservedObject var api: GitHub
    let repo: String
    let branch: String
    let canWrite: Bool
    @State private var entry: Entry?
    @State private var document: ReadmeDocument?
    @State private var bodyHeight: CGFloat = 180
    @State private var error = ""
    @State private var resolved = ""
    @State private var expanded = false
    @State private var revision = 0
    private var requestID: String { repo + "\n" + branch + "\n" + String(revision) }
    var body: some View {
        Section {
            SoftGroupRows {
                SoftGroupRow("heading") {
                    HStack {
                        Label(entry?.name ?? "README", systemImage: "info.circle").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        if let entry, canWrite {
                            NavigationLink("编辑") { FileView(api: api, repo: repo, entry: entry, branch: resolved, canWrite: canWrite) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
                if let document {
                    SoftGroupRow("body") {
                        ReadmeDocumentBody(document: document,
                            baseURL: CommunityRules.readingBase(repo, branch: resolved, file: entry?.path ?? "README.md", raw: false),
                            api: api, expanded: expanded, height: $bodyHeight)
                    }
                    if bodyHeight > ReadmeDocumentRules.collapsedHeight || ReadmePreviewRules.needsExpansion(document.source ?? "") {
                        SoftGroupRow("expand") { Button(expanded ? "收起自述文件" : "展开完整自述文件") { expanded.toggle() } }
                    }
                    if expanded && bodyHeight >= ReadmeDocumentRules.inlineHeightLimit {
                        SoftGroupRow("limit") { Text("正文较长，可使用全屏阅读继续查看。").font(.caption).foregroundStyle(.secondary) }
                    }
                    SoftGroupRow("reader") { NavigationLink("全屏阅读") { RepositoryReadmeView(api: api, repo: repo, branch: resolved) } }
                } else if error.isEmpty {
                    SoftGroupRow("loading") { ProgressView("加载自述文件…") }
                }
                if !error.isEmpty {
                    SoftGroupRow("error") { Text(error).font(.caption).foregroundStyle(.secondary) }
                    SoftGroupRow("retry") { Button("重新加载") { revision += 1 } }
                }
            }
        }.task(id: requestID) {
            entry = nil; document = nil; bodyHeight = 180; expanded = false; error = ""
            do {
                let selected = try await api.resolvedBranch(repo, branch: branch)
                let loaded = try await api.repositoryReadmeDocument(repo, branch: selected)
                try Task.checkCancellation(); guard api.isCurrentSession else { return }
                resolved = selected; entry = loaded.entry; document = loaded
            } catch {
                if api.isCurrentSession, !RefreshFailure.isCancellation(error) {
                    self.error = (error as? GitHubAPIError)?.status == 404 ? "此分支没有自述文件，或账号没有读取权限。" : error.localizedDescription
                }
            }
        }
    }
}
