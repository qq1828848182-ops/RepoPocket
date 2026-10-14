import SwiftUI

struct CollaborationListView: View {
    @ObservedObject var api: GitHub
    let repo: String
    let kind: CollaborationKind
    @StateObject private var store = CommunityPageStore<CollaborationItem>()
    @State private var state = "open"
    private var visible: [CollaborationItem] { store.items.filter { kind == .pulls || $0.pull_request == nil } }
    var body: some View {
        List {
            Picker("状态", selection: $state) {
                Text("开放").tag("open"); Text("已关闭").tag("closed"); Text("全部").tag("all")
            }.pickerStyle(.segmented)
            ForEach(visible) { item in
                NavigationLink { CollaborationDetailView(api: api, repo: repo, kind: kind, number: item.number) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title).font(.headline)
                        Text("#\(item.number) · \(item.user?.login ?? "未知作者") · \(item.draft == true ? "草稿" : item.state)")
                            .font(.caption).foregroundStyle(.secondary)
                        if let date = item.updated_at { Text(date).font(.caption2).foregroundStyle(.secondary) }
                    }.padding(.vertical, 4)
                }
            }
            if store.loaded && visible.isEmpty && store.error.isEmpty { Text("当前页没有符合条件的 \(kind.title)" + (store.more ? "，可继续加载。" : "。")) }
            CommunityPageFooter(store: store, next: { load() })
            if let url = CommunityRules.repositoryURL(repo, suffix: "/" + kind.rawValue) { Link("在 GitHub 打开", destination: url) }
        }.navigationTitle(kind.title).adaptiveWorkspaceLayout()
        .toolbar { Button("刷新") { load(reset: true) }.disabled(store.busy) }
        .onChange(of: state) { _ in load(reset: true) }
        .task { if !store.loaded { load() } }
        .onDisappear { store.cancel() }
    }
    private func load(reset: Bool = false) {
        let requested = state
        store.load(reset: reset, api: api) { try await api.collaborationItems(repo, kind: kind, state: requested, page: $0) }
    }
}

struct CommunityPageFooter<Item: Identifiable>: View where Item.ID: Hashable {
    @ObservedObject var store: CommunityPageStore<Item>
    let next: () -> Void
    var body: some View {
        Section {
            if store.busy { ProgressView("加载中…") }
            if !store.error.isEmpty { Text(store.error).font(.caption).textSelection(.enabled) }
            if store.more { Button(store.error.isEmpty ? "加载更多" : "重试") { next() }.disabled(store.busy) }
            if store.limited { Text("已显示前 300 条，请在 GitHub 查看更多。").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct CollaborationDetailView: View {
    @ObservedObject var api: GitHub
    let repo: String
    let kind: CollaborationKind
    let number: Int
    @State private var item: CollaborationItem?
    @State private var error = ""
    @State private var busy = false
    @State private var revision = 0
    var body: some View {
        List {
            if let item {
                Section {
                    Text(item.title).font(.title3.bold()).textSelection(.enabled)
                    Text("#\(number) · \(item.merged == true ? "已合并" : item.state) · \(item.user?.login ?? "未知作者")").font(.caption)
                    if let labels = item.labels, !labels.isEmpty { Text(labels.map { $0.name }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                    if let head = item.head, let base = item.base { Text(head.ref + " → " + base.ref).font(.caption).textSelection(.enabled) }
                    if let count = item.changed_files { Text("\(count) 个文件 · +\(item.additions ?? 0) / −\(item.deletions ?? 0)").font(.caption) }
                }
                Section("正文") { CommunityMarkdown(text: item.body ?? "暂无正文", baseURL: CommunityRules.repositoryURL(repo)) }
                Section {
                    NavigationLink("讨论评论") { DiscussionView(api: api, repo: repo, number: number, stream: .conversation) }
                    if kind == .pulls {
                        NavigationLink("审查记录") { DiscussionView(api: api, repo: repo, number: number, stream: .reviews) }
                        NavigationLink("行内评论") { DiscussionView(api: api, repo: repo, number: number, stream: .inline) }
                        NavigationLink("变更文件与差异") { PullFilesView(api: api, repo: repo, number: number) }
                    }
                    if let url = CommunityRules.webURL(item.html_url) { Link("在 GitHub 操作 / 回复", destination: url) }
                }
            }
            if busy { ProgressView("加载详情…") }
            if !error.isEmpty { Text(error); Button("重试") { revision += 1 } }
        }.navigationTitle("\(kind.title) #\(number)").adaptiveWorkspaceLayout()
        .toolbar { Button("刷新") { revision += 1 }.disabled(busy) }
        .task(id: revision) { await load() }
    }
    private func load() async {
        busy = true; error = ""; defer { busy = false }
        do {
            let value = try await api.collaborationDetail(repo, kind: kind, number: number)
            try Task.checkCancellation(); guard api.isCurrentSession else { return }; item = value
        } catch { if api.isCurrentSession, !RefreshFailure.isCancellation(error) { self.error = error.localizedDescription } }
    }
}

struct DiscussionView: View {
    @ObservedObject var api: GitHub
    let repo: String
    let number: Int
    let stream: DiscussionStream
    @StateObject private var store = CommunityPageStore<CollaborationComment>()
    var body: some View {
        List {
            ForEach(store.items) { comment in
                Section {
                    HStack { GitHubAvatar(url: comment.user?.avatar_url, size: 28); Text(comment.user?.login ?? "已删除用户").font(.headline) }
                    if let state = comment.state { Text(state).font(.caption).foregroundStyle(.secondary) }
                    if let date = comment.created_at { Text(date).font(.caption2).foregroundStyle(.secondary) }
                    if let path = comment.path { Text(path + (comment.line.map { ":\($0)" } ?? "")).font(.caption).textSelection(.enabled) }
                    CommunityMarkdown(text: comment.body.flatMap { $0.isEmpty ? nil : $0 } ?? "无文字内容", baseURL: CommunityRules.repositoryURL(repo))
                    if let url = CommunityRules.webURL(comment.html_url) { Link("在 GitHub 打开", destination: url) }
                }
            }
            if store.loaded && store.items.isEmpty { Text("暂无记录") }
            CommunityPageFooter(store: store, next: { load() })
        }.navigationTitle(stream.title).adaptiveWorkspaceLayout()
        .toolbar { Button("刷新") { load(reset: true) }.disabled(store.busy) }
        .task { if !store.loaded { load() } }.onDisappear { store.cancel() }
    }
    private func load(reset: Bool = false) {
        store.load(reset: reset, api: api) { try await api.collaborationComments(repo, number: number, stream: stream, page: $0) }
    }
}

struct PullFilesView: View {
    @ObservedObject var api: GitHub
    let repo: String
    let number: Int
    @StateObject private var store = CommunityPageStore<DesktopCommit.File>()
    var body: some View {
        List {
            ForEach(store.items) { file in
                NavigationLink { CommitPatchDestination(file: file, pullRequest: true) } label: {
                    VStack(alignment: .leading) {
                        Text(file.filename)
                        Text("\(file.status) · +\(file.additions) / −\(file.deletions)").font(.caption).foregroundStyle(.secondary)
                        if let previous = file.previous_filename { Text("原路径：" + previous).font(.caption) }
                    }
                }
            }
            if store.loaded && store.items.isEmpty { Text("暂无变更文件") }
            CommunityPageFooter(store: store, next: { load() })
            Text("二进制或部分大文件没有文本 patch；不代表没有变化。").font(.caption).foregroundStyle(.secondary)
            if let url = CommunityRules.repositoryURL(repo, suffix: "/pull/\(number)/files") { Link("在 GitHub 查看完整差异", destination: url) }
        }.navigationTitle("PR 变更文件").adaptiveWorkspaceLayout()
        .task { if !store.loaded { load() } }.onDisappear { store.cancel() }
    }
    private func load() { store.load(api: api) { try await api.pullFiles(repo, number: number, page: $0) } }
}
