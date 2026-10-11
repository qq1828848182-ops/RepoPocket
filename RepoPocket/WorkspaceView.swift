import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

struct LocalSnapshot: Codable {
    var hashes: [String: String] = [:]
    var texts: [String: String] = [:]
}
struct LocalChange: Identifiable {
    var id: String { path }
    let path: String
    let kind: String
    let before: String?
    let after: String?
    var relativePath: String { path.split(separator: "/").dropFirst().joined(separator: "/") }
}

enum LocalStore {
    static func root() throws -> URL {
        let fm = FileManager.default
        let url = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Repositories", isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func metadata(_ folder: URL) throws -> URL {
        let fm = FileManager.default
        let url = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("LocalBaselines", isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url.appendingPathComponent(folder.lastPathComponent + ".json")
    }
    static func snapshot(_ directory: URL) throws -> LocalSnapshot {
        guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw AppError(text: "工作区根目录不能是符号链接") }
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let fm = FileManager.default
        var snapshot = LocalSnapshot()
        var failure: Error?
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], errorHandler: { _, error in failure = error; return false }) else { throw AppError(text: "无法扫描工作目录") }
        for case let url as URL in enumerator {
            if url.lastPathComponent == ".git" { enumerator.skipDescendants(); continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants(); throw AppError(text: "不支持符号链接：" + url.lastPathComponent) }
            guard values.isRegularFile == true else { continue }
            let components = url.standardizedFileURL.pathComponents
            let base = root.pathComponents
            guard Array(components.prefix(base.count)) == base else { throw AppError(text: "扫描路径越界") }
            let path = components.dropFirst(base.count).joined(separator: "/")
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            var small = Data()
            var total = 0
            while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
                hasher.update(data: chunk); total += chunk.count
                if total <= 64 * 1024 { small.append(chunk) }
            }
            snapshot.hashes[path] = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            if total <= 64 * 1024, !small.contains(0), let text = String(data: small, encoding: .utf8) { snapshot.texts[path] = text }
        }
        if let failure = failure { throw failure }
        return snapshot
    }
    static func changes(_ folders: [URL]) throws -> [LocalChange] {
        var result: [LocalChange] = []
        for folder in folders {
            let baseline = try (try? binding(folder).snapshot) ?? JSONDecoder().decode(LocalSnapshot.self, from: Data(contentsOf: metadata(folder)))
            let current = try snapshot(folder)
            for path in Set(baseline.hashes.keys).union(current.hashes.keys).sorted() where baseline.hashes[path] != current.hashes[path] {
                result.append(LocalChange(path: folder.lastPathComponent + "/" + path, kind: baseline.hashes[path] == nil ? "新增" : (current.hashes[path] == nil ? "删除" : "修改"), before: baseline.texts[path], after: current.texts[path]))
            }
        }
        return result
    }
    static func removeWorkspace(_ folder: URL) throws {
        let fm = FileManager.default
        let base = try root().standardizedFileURL
        guard folder.standardizedFileURL.deletingLastPathComponent() == base,
              folder.lastPathComponent != "." && !folder.lastPathComponent.hasPrefix(".delete-") else {
            throw AppError(text: "拒绝删除工作区目录外的路径")
        }
        guard try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory == true,
              try folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw AppError(text: "工作区目录无效") }
        let meta = try metadata(folder), remote = try bindingURL(folder)
        guard fm.fileExists(atPath: meta.path) else { throw AppError(text: "基线不存在，拒绝删除") }
        let quarantine = base.appendingPathComponent(".delete-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: quarantine, withIntermediateDirectories: false)
        let savedFolder = quarantine.appendingPathComponent("workspace", isDirectory: true)
        let savedMeta = quarantine.appendingPathComponent("baseline.json")
        let savedRemote = quarantine.appendingPathComponent("binding.remote")
        do {
            try fm.moveItem(at: folder, to: savedFolder)
            try fm.moveItem(at: meta, to: savedMeta)
            if fm.fileExists(atPath: remote.path) { try fm.moveItem(at: remote, to: savedRemote) }
        } catch {
            do {
                if fm.fileExists(atPath: savedRemote.path) { try fm.moveItem(at: savedRemote, to: remote) }
                if fm.fileExists(atPath: savedMeta.path) { try fm.moveItem(at: savedMeta, to: meta) }
                if fm.fileExists(atPath: savedFolder.path) { try fm.moveItem(at: savedFolder, to: folder) }
                try fm.removeItem(at: quarantine)
            } catch { throw AppError(text: "删除准备失败且恢复不完整，数据留在 \(quarantine.path)，请勿清理：\(error.localizedDescription)") }
            throw error
        }
        do { try fm.removeItem(at: quarantine) }
        catch { throw AppError(text: "清理未完成；剩余数据位于 \(quarantine.path)，请手动确认后处理：\(error.localizedDescription)") }
    }
    static func importFolder(_ source: URL) throws -> URL {
        let fm = FileManager.default
        guard try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory == true,
              try source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw AppError(text: "请选择真实文件夹；ZIP 请使用单独的 ZIP 导入按钮")
        }
        // Validate before copying so rejected links cannot be followed by a provider.
        _ = try snapshot(source)
        let base = try root()
        // Always use a fresh directory: never overwrite a previous local checkout.
        let destination = base.appendingPathComponent(source.lastPathComponent + "-" + String(UUID().uuidString.prefix(8)), isDirectory: true)
        do {
            try fm.copyItem(at: source, to: destination)
            let baseline = try snapshot(destination)
            try JSONEncoder().encode(baseline).write(to: metadata(destination), options: .atomic)
            return destination
        } catch { try? fm.removeItem(at: destination); throw error }
    }
}

struct WorkspaceView: View {
    @ObservedObject var api: GitHub
    @State private var roots: [URL] = []
    @State private var changes: [LocalChange] = []
    @State private var importing = false
    @State private var zip = false
    @State private var busy = false
    @State private var message = ""
    @State private var folder: URL?
    @State private var binding: WorkspaceBinding?
    @State private var repo = ""
    @State private var branch = ""
    @EnvironmentObject private var selectionStore: WorkspaceSelectionStore
    @State private var hasScanned = false
    private var selectionScope: WorkspaceSelectionScope? {
        guard let folder else { return nil }
        return WorkspaceSelectionScope(accountID: api.accountID, folder: folder, repository: binding?.repo ?? "", branch: binding?.branch ?? "")
    }
    private var selected: Set<String> {
        guard let selectionScope else { return [] }
        return selectionStore.session.selected(in: selectionScope)
    }
    @State private var commitMessage = ""
    @State private var scannedSnapshot: LocalSnapshot?
    @State private var confirming = false
    @State private var pull: WorkspacePull?
    @State private var pullChoices: [String: Bool] = [:]
    @State private var resolvingPull = false
    @State private var checkPending: WorkspacePull?
    @State private var pendingDelete: URL?
    @State private var confirmDelete = false
    @State private var confirmDirtyDelete = false
    @State private var deletionIsDirty = false
    @State private var confirmPull = false
    @FocusState private var commitMessageFocused: Bool
    var body: some View {
        NavigationStack {
            List {
                remoteSection
                localSection
                if let folder = folder {
                    bindingSection(folder)
                    changesSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("本地工作区")
            .adaptiveWorkspaceLayout()
            .refreshable { await scan() }
            .scrollDismissesKeyboard(.never)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { commitMessageFocused = false } } }
            .confirmationDialog("检查远端更新？此操作不会修改本地文件；检查完成后仍需确认才会拉取。", isPresented: $confirmPull, titleVisibility: .visible) {
                Button("检查更新") { Task { await checkRemote() } }
                Button("取消", role: .cancel) {}
            }
            .task { if !hasScanned { folder = selectionStore.session.rememberedFolder(accountID: api.accountID); await scan() } }
            .sheet(isPresented: $importing) { WorkspaceDocumentPicker(zip: zip) { urls in Task { await importItems(urls, zip: zip) } } }
            .sheet(isPresented: $resolvingPull, onDismiss: { discardPull() }) { conflictSheet }
            .confirmationDialog("确认提交到 \(binding?.repo ?? "") · \(binding?.branch ?? "")？包含勾选的删除操作。", isPresented: $confirming, titleVisibility: .visible) {
                Button("确认提交 \(selected.count) 项") { Task { await commit() } }
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog("删除本地工作区？不会删除 GitHub 远端。", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("继续删除本地副本", role: .destructive) { inspectDeletion() }
                Button("取消", role: .cancel) { pendingDelete = nil }
            }
            .confirmationDialog(deletionIsDirty ? "此工作区有未提交更改，删除后无法恢复。确定仍要删除？" : "再次确认永久删除此本地工作区及其关联记录？", isPresented: $confirmDirtyDelete, titleVisibility: .visible) {
                Button("永久删除未提交更改与工作区", role: .destructive) { deleteSelected() }
                Button("取消", role: .cancel) { pendingDelete = nil }
            }
            .alert("提示", isPresented: Binding(get: { !message.isEmpty }, set: { if !$0 { message = "" } })) {
                Button("好", role: .cancel) { message = "" }
            } message: { Text(message) }
            .sheet(item: $checkPending, onDismiss: { discardCheck() }) { pending in
                NavigationStack {
                    List {
                        if pending.binding.head == binding?.head { Text("远端无新提交，本地更改保持不变。") }
                        else {
                            Text("下列路径是远端相对当前基线的实际变更；拉取会按三方合并，冲突另行逐项确认。")
                            ForEach(WorkspaceMerge.remoteChanges(base: binding?.snapshot ?? LocalSnapshot(), remote: pending.binding.snapshot), id: \.path) { change in
                                LabeledContent(change.path, value: change.kind)
                            }
                            if WorkspaceMerge.remoteChanges(base: binding?.snapshot ?? LocalSnapshot(), remote: pending.binding.snapshot).isEmpty { Text("提交改变，但文件内容未变。") }
                        }
                    }
                    .navigationTitle("远端更新检查")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("稍后") { discardCheck() } }
                        if pending.binding.head != binding?.head {
                            ToolbarItem(placement: .confirmationAction) { Button("确认拉取") { Task { await pullChecked() } }.disabled(busy) }
                        }
                    }
                }.interactiveDismissDisabled(busy)
            }
        }
    }
    private var remoteSection: some View {
Section("从远端建立工作区") {
                    TextField("用户名/仓库名", text: $repo).textInputAutocapitalization(.never).autocorrectionDisabled().softGroupedRow(top: true)
                    TextField("分支（空白为默认分支）", text: $branch).softGroupedRow()
                    Button("下载远端并建立可靠基线") { Task { await downloadRemote() } }.disabled(busy).softGroupedRow(bottom: true)
                }
    }

    private var localSection: some View {
Section("本地工作目录") {
                    Text("导入副本保存在 Documents/Repositories，可在“文件”App 中修改。目录和 ZIP 使用独立系统选择器。") .font(.caption).softGroupedRow(top: true)
                    Button("导入一个或多个文件夹") { zip = false; importing = true }.disabled(busy).softGroupedRow()
                    Button("导入一个或多个 ZIP") { zip = true; importing = true }.disabled(busy).softGroupedRow()
                    ForEach(roots, id: \.path) { root in
                        Button { folder = root; Task { await scan() } } label: {
                            VStack(alignment: .leading) {
                                Label(root.lastPathComponent, systemImage: folder == root ? "checkmark.circle.fill" : "folder")
                                if let linked = try? LocalStore.binding(root) {
                                    Text(linked.repo + " · " + linked.branch).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.disabled(busy)
                        .softGroupedRow()
                        .swipeActions {
                            Button("删除", role: .destructive) { pendingDelete = root; confirmDelete = true }.disabled(busy)
                        }
                        .contextMenu {
                            Button("删除本地工作区", role: .destructive) { pendingDelete = root; confirmDelete = true }
                        }
                    }
                    Text("包含隐藏文件，仅扫描时忽略 .git；拒绝符号链接。ZIP：最多 20,000 项、单文件 512 MiB、总计 1 GiB。") .font(.caption2).softGroupedRow(bottom: true)
                }
    }

    private func bindingSection(_ folder: URL) -> some View {
Section("关联仓库 / 分支") {
                        Text(folder.lastPathComponent).font(.caption).softGroupedRow(top: true)
                        if let binding = binding {
                            Text(binding.repo + " · " + binding.branch).softGroupedRow()
                            Text("基线 " + String(binding.head.prefix(12))).font(.caption).softGroupedRow()
                            if let d = binding.remoteAuthorDate { Text("最新提交 author：" + d.formatted()).font(.caption).softGroupedRow() }
                            if let d = binding.remoteCommitterDate { Text("最新提交 committer：" + d.formatted()).font(.caption).softGroupedRow() }
                            if let d = binding.lastChecked { Text("上次检查：" + d.formatted()).font(.caption).softGroupedRow() }
                            if let d = binding.lastPulled { Text("上次拉取：" + d.formatted()).font(.caption).softGroupedRow() }
                            Button("检查更新") { commitMessageFocused = false; confirmPull = true }
                                .buttonStyle(.borderless)
                                .disabled(busy).softGroupedRow()
                            Button("删除本地工作区", role: .destructive) { pendingDelete = folder; confirmDelete = true }
                                .buttonStyle(.borderless)
                                .disabled(busy).softGroupedRow(bottom: true)
                        } else {
                            TextField("用户名/仓库名", text: $repo).textInputAutocapitalization(.never).autocorrectionDisabled().softGroupedRow()
                            TextField("分支（空白为默认分支）", text: $branch).textInputAutocapitalization(.never).autocorrectionDisabled().softGroupedRow()
                            Button("验证副本并关联当前远端") { Task { await associate(folder) } }.disabled(busy).softGroupedRow()
                            Text("先导入当前分支的完整副本并关联，再编辑。关联必须逐文件匹配远端 Git blob；不匹配拒绝关联。") .font(.caption).softGroupedRow(bottom: true)
                        }
                    }
    }

    private var changesSection: some View {
Section("本地变更预览 / 勾选提交") {
                        if busy && changes.isEmpty { ProgressView("处理中，请保持前台…").softGroupedRow(top: true) }
                        if changes.isEmpty && !busy { Text("没有变更；在“文件”修改副本后刷新。").softGroupedRow(top: true) }
                        ForEach(changes) { change in
                            HStack {
                                Button {
                                    if let selectionScope { selectionStore.session.toggle(change.path, in: selectionScope) }
                                } label: {
                                    Image(systemName: selected.contains(change.path) ? "checkmark.circle.fill" : "circle")
                                        .frame(width: 44, height: 44).contentShape(Rectangle())
                                }.buttonStyle(.borderless)
                                .accessibilityLabel("勾选 " + change.relativePath)
                                .accessibilityValue(selected.contains(change.path) ? "已勾选" : "未勾选")
                                .disabled(busy || binding == nil)
                                NavigationLink { LocalDiffView(change: change) } label: { VStack(alignment: .leading) { Text(change.relativePath); Text(change.kind).font(.caption) } }
                            }.softGroupedRow(top: change.id == changes.first?.id)
                        }
                        Button("刷新变更") { Task { await scan() } }.disabled(busy).softGroupedRow()
                        Button("拉取更新") { commitMessageFocused = false; confirmPull = true }.disabled(busy || binding == nil).softGroupedRow()
                        TextField("提交说明", text: $commitMessage).focused($commitMessageFocused).softGroupedRow()
                        Button("提交勾选的 \(selected.count) 项变更") { confirming = true }.disabled(busy || binding == nil || selected.isEmpty || commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).softGroupedRow()
                        Text("新增、修改、删除一次原子更新分支。单文件 ≤10 MiB；大文件使用 Release。远端变化拒绝提交，不强推；未勾选项保持本地修改。") .font(.caption).softGroupedRow(bottom: true)
                    }
    }

    private var conflictSheet: some View {
                NavigationStack {
                    List {
                        if let pending = pull, let binding = binding {
                            Text("同文件双改或删除/修改冲突不会自动覆盖。请逐项选择；取消不会改变工作区。二进制或大文本仅显示哈希。")
                            ForEach(pending.conflicts, id: \.self) { path in
                                Section(path) {
                                    Text("基线：" + (binding.snapshot.texts[path] ?? binding.snapshot.hashes[path] ?? "已删除"))
                                    Text("本地：" + (pending.local.texts[path] ?? pending.local.hashes[path] ?? "已删除"))
                                    Text("远端：" + (pending.binding.snapshot.texts[path] ?? pending.binding.snapshot.hashes[path] ?? "已删除"))
                                    Button { pullChoices[path] = false } label: { Label("保留本地", systemImage: pullChoices[path] == false ? "checkmark.circle.fill" : "circle") }
                                    Button { pullChoices[path] = true } label: { Label("采用远端", systemImage: pullChoices[path] == true ? "checkmark.circle.fill" : "circle") }
                                }.font(.system(.caption, design: .monospaced))
                            }
                            Button("安全应用全部选择") { Task { await applyResolvedPull() } }.disabled(busy || pending.conflicts.contains { pullChoices[$0] == nil })
                        }
                    }.navigationTitle("拉取冲突对照")
                        .toolbar { Button("取消") { resolvingPull = false } }
                }.interactiveDismissDisabled(busy)
    }
    @MainActor private func importItems(_ urls: [URL], zip: Bool) async {
        busy = true
        var failures: [String] = []
        for source in urls {
            do {
                let imported = try await Task.detached(priority: .userInitiated) { () throws -> URL in
                    let scoped = source.startAccessingSecurityScopedResource()
                    defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                    var failure: Error?
                    var destination: URL?
                    var coordinationError: NSError?
                    NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { readable in
                        do {
                            if zip {
                                let stage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                                try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
                                defer { try? FileManager.default.removeItem(at: stage) }
                                try WorkspaceZIP.extract(readable, to: stage)
                                let children = try FileManager.default.contentsOfDirectory(at: stage, includingPropertiesForKeys: [.isDirectoryKey])
                                let content = children.count == 1 && (try? children[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? children[0] : stage
                                destination = try LocalStore.importFolder(content)
                            } else { destination = try LocalStore.importFolder(readable) }
                        } catch { failure = error }
                    }
                    if let error = coordinationError { throw error }
                    if let error = failure { throw error }
                    guard let destination = destination else { throw AppError(text: "文件提供器没有返回可读取内容；请先下载到‘我的 iPhone’，或改用 ZIP 导入") }
                    return destination
                }.value
                folder = imported
            } catch { failures.append(source.lastPathComponent + "：" + error.localizedDescription) }
        }
        busy = false
        await scan()
        if !failures.isEmpty { message = "以下项目导入失败（成功项目已保留）：\n" + failures.joined(separator: "\n") + "\n可将目录压缩为 ZIP 后使用 ZIP 导入。" }
    }
    @MainActor private func checkRemote() async {
        guard let folder, let binding else { return }
        busy = true; defer { busy = false }
        do {
            discardCheck()
            let pending = try await api.preparePull(folder, binding: binding)
            var checked = binding
            checked.lastChecked = Date()
            try LocalStore.saveBinding(checked, folder: folder)
            self.binding = checked
            checkPending = pending
        } catch { if !RefreshFailure.isCancellation(error) { message = error.localizedDescription } }
    }
    private func discardCheck() {
        if let pending = checkPending { try? FileManager.default.removeItem(at: pending.remoteFolder) }
        checkPending = nil
    }
    @MainActor private func inspectDeletion() {
        guard let target = pendingDelete else { return }
        do {
            deletionIsDirty = try !LocalStore.changes([target]).isEmpty
            confirmDirtyDelete = true
        } catch { message = "无法确认未提交更改，拒绝删除：" + error.localizedDescription; pendingDelete = nil }
    }
    @MainActor private func deleteSelected() {
        guard let target = pendingDelete, !busy else { return }
        do {
            try LocalStore.removeWorkspace(target)
            if folder == target { folder = nil; binding = nil; discardCheck(); discardPull() }
            pendingDelete = nil
            roots.removeAll { $0 == target }
            Task { await scan() }
        } catch { if !RefreshFailure.isCancellation(error) { message = error.localizedDescription }; pendingDelete = nil }
    }
    @MainActor private func downloadRemote() async {
        busy = true
        do { folder = try await api.downloadWorkspace(repo: repo.trimmingCharacters(in: .whitespacesAndNewlines), branch: branch.trimmingCharacters(in: .whitespacesAndNewlines)) }
        catch { if !RefreshFailure.isCancellation(error) { message = error.localizedDescription } }
        busy = false
        await scan()
    }
    @MainActor private func pullChecked() async {
        guard let pending = checkPending, let folder, let binding else { return }
        checkPending = nil
        await applyPendingPull(pending, folder: folder, binding: binding)
    }
    @MainActor private func pullRemote() async { await checkRemote() }
    @MainActor private func applyPendingPull(_ pending: WorkspacePull, folder: URL, binding: WorkspaceBinding) async {
        busy = true
        do {
            guard try await api.workspaceHead(binding.repo, branch: binding.branch) == pending.binding.head else {
                throw AppError(text: "预览后远端分支已变化，请重新检查")
            }
            pullChoices = [:]
            if pending.conflicts.isEmpty {
                defer { try? FileManager.default.removeItem(at: pending.remoteFolder) }
                try LocalStore.applyPull(pending, folder: folder, original: binding, choices: [:])
                message = "拉取完成；远端基线已更新，未提交本地变更已保留。"
            } else { pull = pending; resolvingPull = true }
        } catch { try? FileManager.default.removeItem(at: pending.remoteFolder); if !RefreshFailure.isCancellation(error) { message = error.localizedDescription } }
        busy = false
        if pull == nil { await scan() }
    }
    @MainActor private func applyResolvedPull() async {
        guard let pull = pull, let folder = folder, let binding = binding else { return }
        busy = true
        do {
            guard try await api.workspaceHead(binding.repo, branch: binding.branch) == pull.binding.head else {
                throw AppError(text: "冲突选择期间远端分支已变化，请重新检查")
            }
            try LocalStore.applyPull(pull, folder: folder, original: binding, choices: pullChoices)
            resolvingPull = false
            discardPull()
            message = "冲突处理完成；采用最新远端作为基线，保留本地的内容仍显示为待提交。"
        } catch { if !RefreshFailure.isCancellation(error) { message = error.localizedDescription } }
        busy = false
        if self.pull == nil { await scan() }
    }
    private func discardPull() {
        if let pull = pull { try? FileManager.default.removeItem(at: pull.remoteFolder) }
        pull = nil; pullChoices = [:]
    }
    @MainActor private func associate(_ folder: URL) async {
        busy = true
        do { binding = try await api.associateWorkspace(folder, repo: repo, branch: branch) }
        catch { if !RefreshFailure.isCancellation(error) { message = error.localizedDescription } }
        busy = false
        await scan()
    }
    @MainActor private func commit() async {
        guard let folder = folder, let binding = binding, let scope = selectionScope, !busy else { return }
        let generation = AccountStore.generation
        let committing = selected
        var succeeded = false
        busy = true
        do {
            let paths = Set(committing.map { String($0.dropFirst(folder.lastPathComponent.count + 1)) })
            guard let scanned = scannedSnapshot else { throw AppError(text: "请先刷新变更") }
            let writes = try await Task.detached { try LocalStore.prepare(folder, paths: paths, expected: scanned) }.value
            let updated = try await api.commitWorkspace(binding, writes: writes, message: commitMessage)
            guard generation == AccountStore.generation, selectionScope == scope else { busy = false; return }
            do { try LocalStore.finish(folder, binding: updated, snapshot: scanned, paths: paths) }
            catch { throw AppError(text: "远端提交已成功，但本地基线保存失败。不要重复提交；请备份修改并重新导入。" + error.localizedDescription) }
            guard generation == AccountStore.generation, selectionScope == scope else { busy = false; return }
            selectionStore.session.commitSucceeded(committing, in: scope)
            succeeded = true
            self.binding = updated; commitMessage = ""; message = "已原子提交 \(writes.count) 项变更：" + updated.head
        } catch { if !RefreshFailure.isCancellation(error) { message = error.localizedDescription } }
        busy = false
        if succeeded { await scan() }
    }
    @MainActor private func scan() async {
        guard !busy else { return }
        let generation = AccountStore.generation
        let requestedFolder = folder
        busy = true; defer { busy = false }
        do {
            // Stage every result; failure cannot publish a partial list or prune selections.
            let result = try await Task.detached(priority: .userInitiated) { () throws -> ([URL], URL?, WorkspaceBinding?, [LocalChange], LocalSnapshot?) in
                let roots = try FileManager.default.contentsOfDirectory(at: LocalStore.root(), includingPropertiesForKeys: [.isDirectoryKey]).filter {
                    (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && FileManager.default.fileExists(atPath: (try? LocalStore.metadata($0).path) ?? "")
                }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                let target = requestedFolder.flatMap { roots.contains($0) ? $0 : nil } ?? roots.first
                guard let target else { return (roots, nil, nil, [], nil) }
                let binding = try? LocalStore.binding(target)
                let before = try LocalStore.snapshot(target)
                let changes = try LocalStore.changes([target])
                let after = try LocalStore.snapshot(target)
                guard before.hashes == after.hashes else { throw AppError(text: "扫描期间文件已变化，请重试") }
                let latestBinding = try? LocalStore.binding(target)
                guard binding?.head == latestBinding?.head, binding?.repo == latestBinding?.repo, binding?.branch == latestBinding?.branch else {
                    throw AppError(text: "扫描期间工作区关联已变化，请重试")
                }
                return (roots, target, binding, changes, after)
            }.value
            try Task.checkCancellation()
            guard generation == AccountStore.generation, api.accountID == AccountStore.activeID, folder == requestedFolder else { return }
            roots = result.0; folder = result.1; binding = result.2
            changes = result.3; scannedSnapshot = result.4; hasScanned = true
            selectionStore.session.remember(folder, accountID: api.accountID)
            if let selectionScope { selectionStore.session.scanSucceeded(Set(changes.map { $0.path }), in: selectionScope) }
        } catch { if !RefreshFailure.isCancellation(error) { message = error.localizedDescription } }
    }
}

struct LocalDiffView: View {
    let change: LocalChange
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(change.kind + " · " + change.path).font(.headline)
                Text("小于等于 64 KiB 的 UTF-8 文本可预览；此处为完整前后对照，不是逐行补丁。") .font(.caption)
                Group {
                    Text("基线文本").font(.headline)
                    Text(change.before ?? "（无文本基线：新增、二进制或超过 64 KiB）")
                    Divider()
                    Text("当前文本").font(.headline)
                    Text(change.after ?? "（无当前文本：已删除、二进制或超过 64 KiB）")
                }.font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
        }.navigationTitle("变更对照")
    }
}
