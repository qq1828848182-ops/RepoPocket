import SwiftUI

struct WorkflowRunsView: View {
    @ObservedObject var api: GitHub
    let repo: String
    let branch: String
    @StateObject private var store = CommunityPageStore<WorkflowRun>()
    @State private var currentBranchOnly = false
    var body: some View {
        List {
            Section { Toggle("仅当前分支", isOn: $currentBranchOnly).disabled(branch.isEmpty).softGroupedRow(top: true, bottom: true) }
            Section {
                SoftGroupRows {
                    for run in store.items {
                        SoftGroupRow(String(run.id)) {
                            NavigationLink { WorkflowRunView(api: api, repo: repo, run: run) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(run.display_title ?? run.name ?? "Workflow").font(.headline)
                                    Text("#\(run.run_number) · \(run.conclusion ?? run.status) · \(run.head_branch ?? "—")").font(.caption).foregroundStyle(.secondary)
                                    Text(run.created_at).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if store.loaded && store.items.isEmpty { SoftGroupRow("empty") { Text("暂无运行记录") } }
                }
            }
            CommunityPageFooter(store: store, next: { load() })
        }.navigationTitle("Actions").adaptiveWorkspaceLayout()
        .toolbar { Button("刷新") { load(reset: true) }.disabled(store.busy) }
        .task { if !store.loaded { load() } }.onChange(of: currentBranchOnly) { _ in load(reset: true) }.onDisappear { store.cancel() }
    }
    private func load(reset: Bool = false) { store.load(reset: reset, api: api) { try await api.workflowRuns(repo, branch: currentBranchOnly ? branch : "", page: $0) } }
}

struct WorkflowRunView: View {
    @ObservedObject var api: GitHub
    let repo: String
    let run: WorkflowRun
    @StateObject private var store = CommunityPageStore<WorkflowJob>()
    @State private var canWrite = false
    @State private var action: CommunityMutation?
    @State private var busy = false
    @State private var message = ""
    var body: some View {
        List {
            Section {
                SoftGroupRows {
                    SoftGroupRow("name") { Text(run.display_title ?? run.name ?? "Workflow").font(.headline) }
                    SoftGroupRow("sha") { Text(run.head_sha).font(.caption).textSelection(.enabled) }
                    SoftGroupRow("artifacts") { NavigationLink("构建产物 / 下载") { WorkflowArtifactsView(api: api, repo: repo, run: run.id) } }
                    for job in store.items {
                        SoftGroupRow("job-\(job.id)") {
                            NavigationLink { WorkflowJobView(api: api, repo: repo, job: job) } label: {
                                VStack(alignment: .leading) { Text(job.name); Text(job.conclusion ?? job.status).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
            CommunityPageFooter(store: store, next: { load() })
            if canWrite {
                Section("运行管理") {
                    SoftGroupRows {
                        SoftGroupRow("rerun") { Button("重新运行此工作流") { action = .rerun(run.id) }.disabled(busy) }
                        SoftGroupRow("cancel") { Button("取消正在进行的运行", role: .destructive) { action = .cancelRun(run.id) }.disabled(busy) }
                        if busy { SoftGroupRow("busy") { ProgressView("提交操作…") } }
                        if !message.isEmpty { SoftGroupRow("result") { Text(message).font(.caption) } }
                    }
                }
            }
        }.navigationTitle("运行 #\(run.run_number)").adaptiveWorkspaceLayout()
        .toolbar { Button("刷新任务") { load(reset: true) }.disabled(store.busy || busy) }
        .task {
            if !store.loaded { load() }
            let access = try? await api.repository(repo)
            guard !Task.isCancelled, api.isCurrentSession else { return }; canWrite = access?.permissions?.push == true
        }.onDisappear { store.cancel() }
        .confirmationDialog("确认操作此工作流运行？", isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } }), titleVisibility: .visible) {
            Button("确认") { if let selected = action { action = nil; Task { await perform(selected) } } }
            Button("取消", role: .cancel) { action = nil }
        } message: { Text(repo + " · #\(run.run_number)。重新运行会消耗该仓库的 Actions 配额，取消会终止当前运行。") }
    }
    private func load(reset: Bool = false) { store.load(reset: reset, api: api) { try await api.workflowJobs(repo, run: run.id, page: $0) } }
    private func perform(_ action: CommunityMutation) async {
        guard !busy else { return }; busy = true; message = ""; defer { busy = false }
        do {
            _ = try await api.communityMutate(repo, action: action)
            guard api.isCurrentSession else { return }; message = "GitHub 已接受操作，请手动刷新运行列表核实新状态。"
        } catch { if api.isCurrentSession, !RefreshFailure.isCancellation(error) { message = error.localizedDescription } }
    }
}

struct WorkflowArtifactsView: View {
    @ObservedObject var api: GitHub
    let repo: String
    let run: Int
    @StateObject private var store = CommunityPageStore<WorkflowArtifact>()
    @State private var downloading = false
    @State private var result = ""
    var body: some View {
        List {
            Section {
                SoftGroupRows {
                    for artifact in store.items {
                        SoftGroupRow(String(artifact.id)) {
                            Button { Task { await download(artifact) } } label: {
                                VStack(alignment: .leading) {
                                    Text(artifact.name)
                                    Text(artifact.expired ? "已过期" : ByteCountFormatter.string(fromByteCount: Int64(artifact.size_in_bytes), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                                }
                            }.disabled(artifact.expired || downloading)
                        }
                    }
                    if store.loaded && store.items.isEmpty { SoftGroupRow("empty") { Text("暂无构建产物") } }
                    if downloading { SoftGroupRow("busy") { ProgressView("下载中，请保持前台…") } }
                    if !result.isEmpty { SoftGroupRow("result") { Text(result).font(.caption) } }
                }
            }
            CommunityPageFooter(store: store, next: { load() })
        }.navigationTitle("构建产物").task { if !store.loaded { load() } }.onDisappear { store.cancel() }
    }
    private func load() {
        store.load(api: api) { page in
            let bytes = try await api.communityRead(GitHub.repoPath(repo) + "/actions/runs/\(run)/artifacts", query: CommunityRules.page(page))
            return try JSONDecoder().decode(WorkflowArtifacts.self, from: bytes).artifacts
        }
    }
    private func download(_ artifact: WorkflowArtifact) async {
        guard !downloading, !artifact.expired else { return }; downloading = true; result = ""; defer { downloading = false }
        do {
            let generation = AccountStore.generation
            try await DownloadStore.shared.requireAuthorization()
            guard api.isCurrentSession else { throw CancellationError() }
            DownloadStore.shared.begin(); defer { DownloadStore.shared.end() }
            let file = try await api.communityArtifact(repo, id: artifact.id, name: artifact.name)
            defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
            _ = try DownloadStore.shared.persist(file, session: generation)
            guard api.isCurrentSession else { throw CancellationError() }; result = "已保存 ZIP 到 " + DownloadStore.shared.label
        } catch { if api.isCurrentSession, !RefreshFailure.isCancellation(error) { result = error.localizedDescription } }
    }
}

struct WorkflowJobView: View {
    @ObservedObject var api: GitHub
    let repo: String
    let job: WorkflowJob
    var body: some View {
        List {
            Section {
                SoftGroupRows {
                    SoftGroupRow("name") { Text(job.name).font(.headline) }
                    SoftGroupRow("state") { Text(job.conclusion ?? job.status) }
                    for step in job.steps ?? [] {
                        SoftGroupRow("step-\(step.number)") { VStack(alignment: .leading) { Text("\(step.number). " + step.name); Text(step.conclusion ?? step.status).font(.caption).foregroundStyle(.secondary) } }
                    }
                    SoftGroupRow("log") { NavigationLink("查看任务日志") { WorkflowLogView(api: api, repo: repo, id: job.id) } }
                }
            }
        }.navigationTitle("任务详情").adaptiveWorkspaceLayout()
    }
}

struct WorkflowLogView: View {
    @ObservedObject var api: GitHub
    let repo: String
    let id: Int
    @State private var log: String?
    @State private var error = ""
    @State private var revision = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                if let log { Text(log).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                else if error.isEmpty { ProgressView("加载日志…") }
                if !error.isEmpty { Text(error); Button("重试") { revision += 1 } }
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
        }.navigationTitle("运行日志")
        .task(id: revision) {
            error = ""
            do {
                let value = try await api.communityJobLog(repo, id: id)
                try Task.checkCancellation(); guard api.isCurrentSession else { return }; log = value
            } catch { if api.isCurrentSession, !RefreshFailure.isCancellation(error) { self.error = error.localizedDescription } }
        }
    }
}
