import SwiftUI
import UniformTypeIdentifiers
import UIKit
import Combine

struct ReleaseManagementDestination: View {
    private let build: () -> AnyView
    init(api: GitHub, repo: String, id: Int? = nil) {
        build = { id.map { AnyView(ReleaseDetailView(api: api, repo: repo, id: $0)) } ?? AnyView(ReleaseListView(api: api, repo: repo)) }
    }
    var body: AnyView { build() }
}

@MainActor final class ReleaseScreenState: ObservableObject {
    let api: GitHub
    let repo: String
    let generation = AccountStore.generation
    @Published var busy = false
    @Published var error = ""
    @Published var progress: Double = 0
    @Published var canWrite = false
    @Published var rows: [ReleaseSummary] = []
    @Published var assets: [Asset] = []
    @Published var release: ManagedRelease?
    @Published var saved: SharedFile?
    @Published var more = false
    @Published var listLoaded = false
    @Published var assetMore = false
    private var page = 1
    private var assetPage = 1
    private var task: Task<Void, Never>?
    private var operation = UUID()
    private var accountObserver: AnyCancellable?
    init(api: GitHub, repo: String) {
        self.api = api; self.repo = repo
        accountObserver = NotificationCenter.default.publisher(for: .githubAccountChanged).sink { [weak self] _ in
            self?.cancel(); self?.canWrite = false; self?.rows = []; self?.assets = []; self?.release = nil; self?.saved = nil
        }
    }
    var valid: Bool { generation == AccountStore.generation && api.isCurrentSession }
    func cancel() { operation = UUID(); task?.cancel(); task = nil; busy = false }
    func run(_ work: @escaping () async throws -> Void) {
        guard valid, !busy else { return }
        busy = true; error = ""; progress = 0
        let token = UUID(); operation = token
        task = Task {
            defer { if operation == token { busy = false; task = nil } }
            do { try await work() }
            catch { if valid && operation == token && !RefreshFailure.isCancellation(error) && !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    func check() throws { try Task.checkCancellation(); guard valid else { throw CancellationError() } }
    func access() async throws {
        canWrite = false
        do {
            let info = try await api.managedRepository(repo); try check()
            canWrite = ReleaseManagementRules.canWrite(info.permissions?.push, session: valid)
        } catch {
            try check() // Cancellation/session changes propagate; permission failures remain read-only.
        }
    }
    func list(reset: Bool) {
        run {
            if reset { self.page = 1; self.rows = []; try await self.access() }
            let p = self.page
            let batch = try await self.api.managedReleases(self.repo, page: p); try self.check()
            self.rows = ReleaseManagementRules.merged(self.rows, batch)
            self.listLoaded = true
            self.more = ReleaseManagementRules.more(count: batch.count, page: p); self.page = p + 1
        }
    }
    func detail(_ id: Int) {
        run { try await self.access(); try await self.reload(id) }
    }
    func reload(_ id: Int) async throws {
        let r = try await api.managedRelease(repo, id: id); try check()
        release = r; assets = []; assetPage = 1
        try await nextAssets(id)
    }
    func nextAssets(_ id: Int) async throws {
        let p = assetPage
        let batch = try await api.managedAssets(repo, id: id, page: p); try check()
        assets = ReleaseManagementRules.merged(assets, batch)
        assetMore = ReleaseManagementRules.more(count: batch.count, page: p); assetPage = p + 1
    }
    func download(_ asset: Asset) {
        run {
            try await DownloadStore.shared.requireAuthorization(); try self.check()
            DownloadStore.shared.begin(); defer { DownloadStore.shared.end() }
            let temporary = try await self.api.downloadManagedAsset(self.repo, asset: asset) { p in
                Task { @MainActor in if self.valid && self.busy { self.progress = p } }
            }
            defer { try? FileManager.default.removeItem(at: temporary.deletingLastPathComponent()) }
            try self.check()
            let file = try DownloadStore.shared.persist(temporary, session: self.generation)
            try self.check(); self.saved = SharedFile(url: file)
        }
    }
}

struct ReleaseListView: View {
    @StateObject private var state: ReleaseScreenState
    @State private var creating = false
    init(api: GitHub, repo: String) { _state = StateObject(wrappedValue: ReleaseScreenState(api: api, repo: repo)) }
    var body: some View {
        List {
            Text(state.repo).font(.caption)
            Text("每页 20 条，最多 1,000 条；不自动下载或预览附件。Latest 无可靠证据时不标记。").font(.caption).foregroundColor(.secondary)
            ForEach(state.rows) { row in
                NavigationLink { ReleaseManagementDestination(api: state.api, repo: state.repo, id: row.id) } label: {
                    VStack(alignment: .leading) {
                        Text(row.title).lineLimit(2)
                        Text(row.tag_name + " · " + String(row.date.prefix(10))).font(.caption)
                        if row.draft { Text("草稿").font(.caption) }
                        if row.prerelease { Text("预发行").font(.caption) }
                    }
                }
            }
            if state.more { Button("加载下一页") { state.list(reset: false) }.disabled(state.busy) }
            if state.rows.isEmpty && !state.busy { Text(state.listLoaded && state.error.isEmpty ? "暂无发行版" : "尚未成功加载发行版，可手动刷新。") }
            if state.canWrite { Button("新建发行版（默认草稿）") { creating = true }.disabled(state.busy) }
            releaseStatus(state)
        }
        .navigationTitle("发行版")
        .toolbar { Button("刷新") { state.list(reset: true) }.disabled(state.busy) }
        .task { if state.rows.isEmpty { state.list(reset: true) } }
        .onDisappear { state.cancel() }
        .sheet(isPresented: $creating, onDismiss: { state.list(reset: true) }) {
            ReleaseEditorView(api: state.api, repo: state.repo, original: nil)
        }
    }
}

private struct ReleaseDeleteTarget: Identifiable {
    let id = UUID()
    let repo: String
    let generation: UUID
    let release: ManagedRelease
    let asset: Asset?
}
struct ReleaseDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var state: ReleaseScreenState
    let id: Int
    @State private var expanded = false
    @State private var editing = false
    @State private var picking = false
    @State private var uploading: URL?
    @State private var deleteTarget: ReleaseDeleteTarget?
    @State private var secondDelete = false
    @State private var confirmation = ""
    @State private var copied = false
    init(api: GitHub, repo: String, id: Int) {
        self.id = id; _state = StateObject(wrappedValue: ReleaseScreenState(api: api, repo: repo))
    }
    var body: some View {
        List {
            if let r = state.release {
                Section {
                    Text(r.title); Text(r.tag_name + " · " + String(r.date.prefix(10))).font(.caption)
                    Text(r.draft ? "草稿" : (r.prerelease ? "预发行" : "已发布"))
                    DisclosureGroup("发布说明", isExpanded: $expanded) {
                        if expanded { Text(ReleaseManagementRules.displayBody(r.body ?? "")).textSelection(.enabled)
                            if (r.body ?? "").count > ReleaseManagementRules.displayBodyLimit { Text("显示已限额；完整正文保留，编辑不截断。请在 GitHub 查看全文。").font(.caption) }
                        }
                    }
                }
                Section("附件（独立分页，每页20）") {
                    ForEach(state.assets) { asset in
                        VStack(alignment: .leading) {
                            Text(asset.name).lineLimit(2)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(asset.size), countStyle: .file)).font(.caption)
                            Button("下载并保存") { state.download(asset) }.disabled(state.busy)
                            if let link = ReleaseManagementRules.browserDownloadURL(asset.browser_download_url, repo: state.repo) {
                                Button("复制下载链接") { UIPasteboard.general.url = link; copied = true }
                            }
                            Text("公开附件可直接在浏览器下载；私有仓库需浏览器登录有权限账号。链接不含 Token；草稿公开前可能无法下载。").font(.caption).foregroundColor(.secondary)
                            if state.canWrite { Button("删除附件", role: .destructive) { prepareDelete(r, asset: asset) }.disabled(state.busy) }
                        }
                    }
                    if state.assetMore { Button("加载更多附件") { state.run { try await state.nextAssets(id) } }.disabled(state.busy) }
                }
                if state.canWrite {
                    Section("管理") {
                        Button("编辑发行版") { editing = true }.disabled(state.busy || !ReleaseManagementRules.editable(r.body ?? ""))
                        if !ReleaseManagementRules.editable(r.body ?? "") { Text("正文超过128 KiB，禁止本地编辑，避免截断保存；请在 GitHub 编辑。") }
                        if r.draft { Button("发布草稿（在编辑表单确认）") { editing = true }.disabled(state.busy) }
                        Button("上传附件") { picking = true }.disabled(state.busy)
                        Button("删除发行版（不删除 git 标签）", role: .destructive) { prepareDelete(r, asset: nil) }.disabled(state.busy)
                    }
                }
            }
            releaseStatus(state)
        }
        .navigationTitle("发行版详情")
        .alert("下载链接已复制", isPresented: $copied) { Button("好", role: .cancel) {} }
        .toolbar { Button("刷新") { state.detail(id) }.disabled(state.busy) }
        .task { if state.release == nil { state.detail(id) } }
        .onDisappear { state.cancel() }
        .sheet(item: $state.saved) { ShareSheet(url: $0.url) }
        .sheet(isPresented: $editing, onDismiss: { state.detail(id) }) {
            if let r = state.release { ReleaseEditorView(api: state.api, repo: state.repo, original: r) }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let file): uploading = file
            case .failure(let error): if !RefreshFailure.isCancellation(error) { state.error = error.localizedDescription }
            }
        }
        .alert("确认上传附件", isPresented: Binding(get: { uploading != nil }, set: { if !$0 { uploading = nil } })) {
            Button("取消", role: .cancel) { uploading = nil }
            Button("确认上传") { if let file = uploading, let r = state.release { upload(file, to: r) }; uploading = nil }
        } message: {
            Text("目标：\(state.repo) #\(id)\n附件：\(uploading?.lastPathComponent ?? "")\n单附件小于2 GiB；同名不覆盖。已公开发行版会立即受到影响。请保持前台。")
        }
        .alert("第一次确认删除", isPresented: Binding(get: { deleteTarget != nil && !secondDelete }, set: { _ in })) {
            Button("取消", role: .cancel) { deleteTarget = nil }
            Button("继续", role: .destructive) { confirmation = ""; secondDelete = true }
        } message: { Text(deleteDescription) }
        .sheet(isPresented: $secondDelete, onDismiss: { deleteTarget = nil }) {
            NavigationStack {
                Form {
                    Text(deleteDescription)
                    Text("第二次确认：输入 DELETE。固定仓库/发行版/附件 ID，切换账号后禁止执行。删除发行版不会删除 git 标签。")
                    TextField("DELETE", text: $confirmation).textInputAutocapitalization(.never)
                    Button("永久删除", role: .destructive) { performDelete() }.disabled(confirmation != "DELETE")
                }.navigationTitle("最终确认").toolbar { Button("取消") { secondDelete = false } }
            }
        }
    }
    private var deleteDescription: String {
        guard let target = deleteTarget else { return "" }
        return "\(target.repo) · Release #\(target.release.id) · \(target.release.tag_name)\n" + (target.asset.map { "附件 #\($0.id) · \($0.name)" } ?? "整个发行版及附件；不删 git 标签")
    }
    private func prepareDelete(_ r: ManagedRelease, asset: Asset?) {
        deleteTarget = ReleaseDeleteTarget(repo: state.repo, generation: state.generation, release: r, asset: asset)
    }
    private func performDelete() {
        guard let target = deleteTarget, confirmation == "DELETE", target.repo == state.repo, target.generation == AccountStore.generation else { secondDelete = false; return }
        secondDelete = false
        state.run {
            try await state.api.deleteManagedRelease(target.repo, original: target.release, asset: target.asset)
            try state.check()
            ReleaseManagementChanges.changed(api: state.api, repo: target.repo)
            if target.asset == nil { dismiss() } else { try await state.reload(id) }
        }
    }
    private func upload(_ file: URL, to r: ManagedRelease) {
        state.run {
            guard file.startAccessingSecurityScopedResource() else { throw AppError(text: "文件未授权，请重选。") }
            defer { file.stopAccessingSecurityScopedResource() }
            _ = try await state.api.uploadManagedAsset(state.repo, original: r, file: file) { p in
                Task { @MainActor in if state.valid && state.busy { state.progress = p } }
            }
            try state.check(); try await state.reload(id)
        }
    }
}

struct ReleaseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var state: ReleaseScreenState
    let original: ManagedRelease?
    @State private var form: ReleaseForm
    @State private var confirm = false
    init(api: GitHub, repo: String, original: ManagedRelease?) {
        self.original = original
        _state = StateObject(wrappedValue: ReleaseScreenState(api: api, repo: repo))
        _form = State(initialValue: original.map(ReleaseForm.init) ?? ReleaseForm())
    }
    var body: some View {
        NavigationStack {
            Form {
                Text(state.repo)
                TextField("标题", text: $form.title)
                TextField("标签（已有或新建）", text: $form.tag).textInputAutocapitalization(.never)
                if original == nil { TextField("新标签目标分支（空为默认分支）", text: $form.branch).textInputAutocapitalization(.never) }
                Text("只操作发行版元数据；不移动、强制更新或删除真实 git 标签。")
                TextEditor(text: $form.body).frame(minHeight: 200)
                Toggle("草稿", isOn: $form.draft)
                Toggle("预发行", isOn: $form.prerelease)
                Button("检查并保存") { confirm = true }.disabled(state.busy || !ReleaseManagementRules.editable(form.body))
                releaseStatus(state)
            }.disabled(!state.valid)
            .navigationTitle(original == nil ? "新建发行版" : "编辑发行版")
            .toolbar { Button("关闭") { state.cancel(); dismiss() } }
            .interactiveDismissDisabled(state.busy)
            .onDisappear { state.cancel() }
            .alert("确认保存发行版", isPresented: $confirm) {
                Button("取消", role: .cancel) {}
                Button("确认保存") {
                    let captured = form
                    state.run {
                        _ = try await state.api.saveManagedRelease(state.repo, original: original, form: captured)
                        try state.check()
                        ReleaseManagementChanges.changed(api: state.api, repo: state.repo)
                        dismiss()
                    }
                }
            } message: { Text("\(state.repo) · \(form.tag)\n\(form.draft ? "保存为草稿" : "将公开发行版，正文/附件对外可见")\n保存前重读比较远端；GitHub无原子条件写入保证，检查后仍可能并发变化。") }
        }
    }
}

@MainActor @ViewBuilder private func releaseStatus(_ state: ReleaseScreenState) -> some View {
    if state.busy {
        ProgressView(value: state.progress)
        Text("请保持前台，勿锁屏；取消不显示伪失败。").font(.caption)
        Button("取消当前操作") { state.cancel() }
    }
    if !state.error.isEmpty { Text(state.error).foregroundColor(.red).textSelection(.enabled) }
    if !state.valid { Text("账号已切换，请重新打开此页面。") }
}
