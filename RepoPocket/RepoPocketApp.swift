import SwiftUI
import UIKit

@main
struct RepoPocketApp: App {
    @State private var accountID = AccountStore.generation
    @StateObject private var selectionStore = WorkspaceSelectionStore()
    var body: some Scene {
        WindowGroup {
            AccountRootView().id(accountID)
                .environmentObject(selectionStore)
                .onReceive(NotificationCenter.default.publisher(for: .githubAccountChanged)) { _ in
                    accountID = AccountStore.generation
                }
        }
    }
}

struct AccountRootView: View {
    @StateObject private var api = GitHub()
    var body: some View {
            TabView {
                RepositoriesView(api: api).tabItem { Label("仓库", systemImage: "shippingbox") }
                WorkspaceView(api: api).tabItem { Label("本地", systemImage: "folder.badge.gearshape") }
                UploadView(api: api).tabItem { Label("提交 / 发布", systemImage: "arrow.up.doc") }
                SettingsView(api: api).tabItem { Label("设置", systemImage: "gear") }
            }
            .alert("提示", isPresented: Binding(get: { !api.message.isEmpty }, set: { if !$0 { api.message = "" } })) {
                Button("好", role: .cancel) { api.message = "" }
            } message: { Text(api.message) }
            .modifier(UpdatePrompt())
    }
}

struct SharedFile: Identifiable { let id = UUID(); let url: URL }
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct RepositoriesView: View {
    @ObservedObject var api: GitHub
    @State private var repos: [Repository] = []
    @State private var loaded = false
    @State private var refreshing = false
    @State private var input = ""
    @State private var busy = false
    @State private var newName = ""
    @State private var isPrivate = true
    @State private var showCreate = false
    var body: some View {
        NavigationStack {
            List {
                Section("直接打开仓库") {
                    TextField("用户名/仓库名", text: $input).textInputAutocapitalization(.never).autocorrectionDisabled().softGroupedRow(top: true)
                    NavigationLink("浏览") { BrowserView(api: api, repo: input, path: "", branch: "") }.disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).softGroupedRow()
                    Button("Fork 到我的账号") { Task { await fork() } }.disabled(busy || isOwnRepository || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).softGroupedRow(bottom: !isOwnRepository)
                    if isOwnRepository {
                        Text("自己的仓库无需 Fork，直接浏览或上传。").font(.caption).foregroundColor(.secondary).softGroupedRow(bottom: true)
                    }
                }
                Section("我的仓库") {
                    if busy && repos.isEmpty && !refreshing {
                        LoadingRows().softGroupedRow(top: true, bottom: true)
                    }
                    if repos.isEmpty && !busy {
                        Text(api.login.isEmpty ? "请先到设置登录。" : "点刷新加载仓库。")
                            .font(.caption).foregroundColor(.secondary)
                            .softGroupedRow(top: true, bottom: true)
                    }
                    ForEach(repos) { repo in
                        NavigationLink { BrowserView(api: api, repo: repo.full_name, path: "", branch: repo.default_branch ?? "") } label: {
                            RepositoryCard(repository: repo, account: api.login)
                        }.softGroupedRow(top: repo.id == repos.first?.id, bottom: repo.id == repos.last?.id)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("RepoPocket")
            .adaptiveWorkspaceLayout()
            .toolbar {
                Button { showCreate = true } label: { Image(systemName: "plus") }.accessibilityLabel("新建仓库")
                Button("刷新") { Task { await refresh() } }.disabled(busy)
            }
            .refreshable { refreshing = true; await refresh(); refreshing = false }
            .task { if !loaded && !CredentialStore.read().isEmpty { await refresh() } }
            .sheet(isPresented: $showCreate) {
                NavigationStack {
                    Form {
                        TextField("新仓库名", text: $newName).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Toggle("私有仓库", isOn: $isPrivate)
                        Text("在你的 GitHub 账号下创建，包含初始 README。不会覆盖现有仓库。").font(.caption)
                        Button("创建仓库") { Task { await create() } }.disabled(busy || newName.isEmpty)
                    }.navigationTitle("新建仓库").adaptiveWorkspaceLayout().toolbar { Button("关闭") { showCreate = false } }
                }
            }
        }
    }
    private var isOwnRepository: Bool {
        guard !api.login.isEmpty else { return false }
        let owner = input.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/").first.map(String.init) ?? ""
        return owner.caseInsensitiveCompare(api.login) == .orderedSame
    }
    private func refresh() async {
        guard !busy else { return }
        let generation = AccountStore.generation
        busy = true; defer { busy = false }
        do {
            try await api.identify()
            let result = try await api.repositories()
            try Task.checkCancellation()
            guard generation == AccountStore.generation else { return }
            repos = result; loaded = true
        } catch { if !RefreshFailure.isCancellation(error) { api.message = error.localizedDescription } }
    }
    private func fork() async {
        busy = true; defer { busy = false }
        do { let repo = try await api.fork(input); api.message = "已创建或找到 Fork：\(repo.full_name)。GitHub 可能需要片刻准备内容。"; repos = try await api.repositories() }
        catch { if !RefreshFailure.isCancellation(error) { api.message = error.localizedDescription } }
    }
    private func create() async {
        busy = true; defer { busy = false }
        do { let r = try await api.createRepository(name: newName, isPrivate: isPrivate); input = r.full_name; showCreate = false; api.message = "已创建 \(r.full_name)"; repos = try await api.repositories() }
        catch { if !RefreshFailure.isCancellation(error) { api.message = error.localizedDescription } }
    }
}

struct BrowserView: View {
    @ObservedObject var api: GitHub
    let repo: String
    let path: String
    let branch: String
    @State private var selectedBranch = ""
    @State private var showBranches = false
    private var activeBranch: String { selectedBranch.isEmpty ? branch : selectedBranch }
    @State private var entries: [Entry] = []
    @State private var loaded = false
    @State private var refreshing = false
    @State private var busy = false
    @State private var share: SharedFile?
    @State private var showUpload = false
    @State private var debEntry: Entry?
    @State private var metadataEntry: Entry?
    @State private var deleteEntry: Entry?
    @State private var deleting = false
    @State private var deleteAccount = ""
    @State private var deleteGeneration = UUID()
    @State private var deleteBranch = ""
    var body: some View {
        List {
            Section { Text(repo).font(.headline); Label("访问账号：" + (api.login.isEmpty ? (AccountStore.accounts.first { $0.id == api.accountID }?.login ?? "待验证") : api.login), systemImage: "person.crop.circle").font(.caption).foregroundColor(.secondary); if !activeBranch.isEmpty { Text("分支：" + activeBranch).font(.caption) } }
            if busy && entries.isEmpty && !refreshing { LoadingRows() }
            if entries.isEmpty && !busy {
                Label("此目录没有文件", systemImage: "folder").foregroundColor(.secondary).padding(.vertical)
            }
            ForEach(entries) { e in
                if e.type == "dir" {
                    NavigationLink { BrowserView(api: api, repo: repo, path: e.path, branch: activeBranch) } label: { Label(e.name, systemImage: "folder") }
                        .softGroupedRow(top: e.id == entries.first?.id, bottom: e.id == entries.last?.id)
                } else if e.type == "file" {
                    HStack {
                        NavigationLink { FileView(api: api, repo: repo, entry: e, branch: activeBranch) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: e.name.lowercased().hasSuffix(".deb") ? "shippingbox.fill" : "doc.text.fill")
                                    .font(.title3).foregroundColor(.accentColor)
                                    .frame(width: 40, height: 44)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.045), lineWidth: 0.5)
                    }
                                VStack(alignment: .leading, spacing: 4) { Text(e.name); Text(ByteCountFormatter.string(fromByteCount: Int64(e.size ?? 0), countStyle: .file)).font(.caption).monospacedDigit().foregroundColor(.secondary) }
                            }.padding(.vertical, 6)
                        }
                        if e.name.lowercased().hasSuffix(".deb") {
                            Menu { Button("编辑包信息") { debEntry = e } } label: { Image(systemName: "ellipsis").padding(8) }.accessibilityLabel("更多操作：" + e.name)
                        } else if e.name.lowercased().hasSuffix(".dylib") {
                            Menu { Button("编辑插件信息") { metadataEntry = e } } label: { Image(systemName: "ellipsis").padding(8) }.accessibilityLabel("更多操作：" + e.name)
                        }
                    }
                    .softGroupedRow(top: e.id == entries.first?.id, bottom: e.id == entries.last?.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("删除", role: .destructive) {
                            deleteAccount = api.accountID; deleteGeneration = AccountStore.generation
                            deleteBranch = activeBranch; deleteEntry = e
                        }.disabled(deleting || busy || activeBranch.isEmpty)
                    }
                } else { Text(e.name + " (" + e.type + ")").softGroupedRow(top: e.id == entries.first?.id, bottom: e.id == entries.last?.id) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(path.isEmpty ? "仓库文件" : (path as NSString).lastPathComponent)
        .adaptiveWorkspaceLayout()
        .refreshable { refreshing = true; await load(); refreshing = false }
        .toolbar {
            Button("上传") { showUpload = true }.disabled(busy)
            Menu {
                Button("切换 / 创建分支") { showBranches = true }
                NavigationLink("提交历史") { HistoryView(api: api, repo: repo, branch: activeBranch) }
                Button("下载整个仓库 ZIP") { Task { await zip() } }
                Button("刷新目录") { Task { await load() } }
            } label: { Image(systemName: "ellipsis.circle") }.disabled(busy)
        }
        .task { if !loaded { await load() } }
        .sheet(isPresented: $showBranches) {
            BranchPickerView(api: api, repo: repo, current: activeBranch) { chosen in
                selectedBranch = chosen; loaded = false; Task { await load() }
            }
        }
        .sheet(isPresented: $showUpload, onDismiss: { Task { await load() } }) {
            UploadView(api: api, initialRepo: repo, directory: path, initialBranch: activeBranch, openedFromFolder: true)
        }
        .sheet(item: $share) { ShareSheet(url: $0.url) }
        .sheet(item: $metadataEntry) { entry in TrollMetadataView(api: api, repo: repo, entry: entry, branch: activeBranch) }
        .sheet(item: $debEntry) { entry in DebEditorView(api: api, remote: (repo, entry, activeBranch)) }
        .confirmationDialog("永久删除仓库中的文件？", isPresented: Binding(get: { deleteEntry != nil }, set: { if !$0 { deleteEntry = nil } }), titleVisibility: .visible) {
            Button("确认删除", role: .destructive) { if let entry = deleteEntry, !deleting {
                let account = deleteAccount, generation = deleteGeneration, branch = deleteBranch
                deleting = true
                Task { await deleteRemote(entry, account: account, generation: generation, branch: branch) }
            } }
            Button("取消", role: .cancel) { deleteEntry = nil }
        } message: { Text(deleteEntry?.path ?? "") }
    }
    private func load() async {
        guard !busy else { return }
        let generation = AccountStore.generation
        let requestedBranch = activeBranch
        busy = true; defer { busy = false }
        do {
            let resolved = requestedBranch.isEmpty ? try await api.resolvedBranch(repo, branch: "") : requestedBranch
            let result = try await api.contents(repo, path: path, branch: resolved)
            try Task.checkCancellation()
            guard generation == AccountStore.generation, activeBranch == requestedBranch else { return }
            selectedBranch = resolved; entries = result; loaded = true
        } catch { if !RefreshFailure.isCancellation(error) { api.message = error.localizedDescription } }
    }
    private func deleteRemote(_ entry: Entry, account: String, generation: UUID, branch: String) async {
        defer { deleting = false; deleteEntry = nil }
        do {
            guard api.accountID == account, AccountStore.generation == generation,
                  activeBranch == branch, !branch.isEmpty,
                  entries.contains(where: { $0.path == entry.path && $0.sha == entry.sha }) else {
                throw AppError(text: "账号、分支或列表已变化，请刷新后重试")
            }
            let fresh = try await api.file(repo, path: entry.path, branch: branch)
            guard fresh.type == "file", fresh.sha == entry.sha,
                  api.accountID == account, AccountStore.generation == generation, activeBranch == branch else {
                throw AppError(text: "远端文件已变化，拒绝删除新内容；请刷新后重试")
            }
            try Task.checkCancellation()
            // GitHub DELETE uses the originally confirmed SHA, never the refreshed one.
            try await api.delete(repo, entry: entry, message: "Delete \(entry.name) via RepoPocket", branch: branch)
            entries.removeAll { $0.path == entry.path && $0.sha == entry.sha }
            api.message = "已删除并提交：\(entry.name)"
        } catch { if !RefreshFailure.isCancellation(error) { api.message = error.localizedDescription } }
    }
    private func zip() async {
        busy = true; defer { busy = false }
        do { share = SharedFile(url: try await api.downloadZIP(repo, branch: activeBranch)) }
        catch { if !RefreshFailure.isCancellation(error) { api.message = error.localizedDescription } }
    }
}

struct FileView: View {
    @ObservedObject var api: GitHub
    let repo: String
    let entry: Entry
    let branch: String
    @State private var text = ""
    @State private var currentSHA = ""
    @State private var editable = false
    @State private var busy = false
    @State private var commitMessage = "Update file via RepoPocket"
    @State private var share: SharedFile?
    @State private var showMetadata = false
    @State private var showDeb = false
    @State private var confirmSave = false
    @State private var confirmDelete = false
    @State private var deleted = false
    var body: some View {
        Form {
            Section("文件") {
                Label(entry.name, systemImage: entry.name.lowercased().hasSuffix(".deb") ? "shippingbox.fill" : "doc.text.fill")
                    .font(.headline).foregroundColor(.primary).padding(.vertical, 4).softGroupedRow(top: true)
                LabeledContent("路径") { Text(entry.path).textSelection(.enabled) }
                LabeledContent("仓库", value: repo)
                LabeledContent("分支", value: branch.isEmpty ? "默认分支" : branch).softGroupedRow(bottom: true)
            }
            Section {
                if entry.name.lowercased().hasSuffix(".deb") { Button("编辑包信息") { showDeb = true }.disabled(busy || deleted) }
                if entry.name.lowercased().hasSuffix(".dylib") { Button("编辑插件信息") { showMetadata = true }.disabled(busy || deleted) }
                Button("下载 / 存到文件") { Task { await download() } }.disabled(busy || deleted)
                Button("加载文本（最多 1 MiB）") { Task { await read() } }.disabled(busy || deleted)
                if busy { ProgressView() }
            }
            if editable && !deleted {
                Section("编辑") { TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(minHeight: 260).softGroupedRow(top: true, bottom: true) }
                Section("提交") {
                    TextField("提交说明", text: $commitMessage).softGroupedRow(top: true)
                    Button("提交文本修改") { confirmSave = true }.disabled(busy).softGroupedRow(bottom: true)
                }
            }
            Section { Button("删除仓库里的此文件", role: .destructive) { confirmDelete = true }.disabled(busy || deleted).softGroupedRow(top: true, bottom: true) }
            if deleted { Text("文件已删除，请返回目录刷新。") }
        }
        .navigationTitle(entry.name)
        .adaptiveWorkspaceLayout()
        .sheet(item: $share) { ShareSheet(url: $0.url) }
        .sheet(isPresented: $showDeb) { DebEditorView(api: api, remote: (repo, entry, branch)) }
        .sheet(isPresented: $showMetadata) { TrollMetadataView(api: api, repo: repo, entry: entry, branch: branch) }
        .confirmationDialog("把修改提交到 \(repo)？", isPresented: $confirmSave, titleVisibility: .visible) {
            Button("确认提交") { Task { await save() } }
        }
        .confirmationDialog("永久删除仓库中的 \(entry.name)？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("确认删除", role: .destructive) { Task { await remove() } }
        }
    }
    private func read() async {
        busy = true; defer { busy = false }
        do {
            guard (entry.size ?? Int.max) <= 1024 * 1024 else { throw AppError(text: "编辑器只加载 1 MiB 内文本；其他文件可下载或替换上传。") }
            let f = try await api.file(repo, path: entry.path, branch: branch)
            guard f.encoding == "base64", let s = f.content,
                  let bytes = Data(base64Encoded: s, options: .ignoreUnknownCharacters), !bytes.contains(0),
                  let t = String(data: bytes, encoding: .utf8) else { throw AppError(text: "不是支持的 UTF-8 文本，不会强行编辑二进制文件。") }
            text = t; currentSHA = f.sha; editable = true
        } catch { if !RefreshFailure.isCancellation(error) { api.message = error.localizedDescription } }
    }
    private func save() async {
        busy = true; defer { busy = false }
        do {
            try await api.commit(repo, path: entry.path, bytes: Data(text.utf8), sha: currentSHA, message: commitMessage, branch: branch)
            currentSHA = try await api.file(repo, path: entry.path, branch: branch).sha
            api.message = "修改已提交到 GitHub。"
        } catch { if !RefreshFailure.isCancellation(error) { api.message = error.localizedDescription } }
    }
    private func remove() async {
        busy = true; defer { busy = false }
        do {
            let fresh = try await api.file(repo, path: entry.path, branch: branch)
            try await api.delete(repo, entry: fresh, message: "Delete \(entry.name) via RepoPocket", branch: branch)
            deleted = true; api.message = "删除已提交。"
        } catch { if !RefreshFailure.isCancellation(error) { api.message = error.localizedDescription } }
    }
    private func download() async {
        busy = true; defer { busy = false }
        do { share = SharedFile(url: try await api.downloadFile(repo, entry: entry, branch: branch)) }
        catch { if !RefreshFailure.isCancellation(error) { api.message = error.localizedDescription } }
    }
}

struct SettingsView: View {
    @ObservedObject var api: GitHub
    @State private var pendingRemoval: GitHubAccount?
    @State private var token = ""
    @State private var busy = false
    @EnvironmentObject private var updateChecker: UpdateChecker
    var body: some View {
        NavigationStack {
            Form {
                Section("已保存账号") {
                    if AccountStore.accounts.isEmpty { Text("尚无已验证账号").foregroundColor(.secondary).softGroupedRow(top: true, bottom: true) }
                    ForEach(AccountStore.accounts) { account in
                        HStack {
                            GitHubAvatar(url: account.avatarURL, size: 32)
                            VStack(alignment: .leading) {
                                Text(account.login)
                                if account.id == api.accountID { Text("当前账号").font(.caption).foregroundColor(.secondary) }
                            }
                            Spacer()
                            if account.id != api.accountID {
                                Button("切换") { AccountStore.activate(account.id) }.disabled(busy)
                            }
                            Button(role: .destructive) { pendingRemoval = account } label: { Image(systemName: "trash") }
                                .disabled(busy).accessibilityLabel("移除 " + account.login)
                        }.softGroupedRow(top: account.id == AccountStore.accounts.first?.id, bottom: account.id == AccountStore.accounts.last?.id)
                    }
                }
                Section("添加 / 更新 GitHub 账号") {
                    SecureField("粘贴你自己的 Token", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled().softGroupedRow(top: true)
                    Button("验证并安全保存") { Task { await verify() } }.disabled(busy || token.isEmpty).softGroupedRow()
                    if busy { ProgressView().softGroupedRow() }
                    Link("在 GitHub 创建 Token", destination: URL(string: "https://github.com/settings/tokens")!).softGroupedRow(bottom: true)
                }
                Section("安全") {
                    Text("每个账号的 Token 独立保存于本机钥匙串。切换账号会关闭旧页面，防止将旧仓库操作提交给新账号。账号资料不含 Token。").softGroupedRow(top: true, bottom: true)
                }
                Section {
                    Button(updateChecker.checking ? "检查中…" : "检查应用更新") { Task { await updateChecker.check() } }.disabled(updateChecker.checking)
                    Text("RepoPocket 1.0.1（build 6）· iOS 16+").foregroundColor(.secondary).softGroupedRow(top: true, bottom: true)
                }
            }.formStyle(.grouped).navigationTitle("设置").adaptiveWorkspaceLayout()
            .task { if !CredentialStore.read().isEmpty { try? await api.identify() } }
            .confirmationDialog("移除此账号及本机 Token？", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }), titleVisibility: .visible) {
                Button("移除", role: .destructive) {
                    if let account = pendingRemoval { AccountStore.remove(account.id) }
                    pendingRemoval = nil
                }
            }
        }
    }
    private func verify() async {
        busy = true; defer { busy = false }
        do { let credential = token; token = ""; try await api.addAccount(token: credential) }
        catch { if !RefreshFailure.isCancellation(error) { api.message = error.localizedDescription } }
    }
}
