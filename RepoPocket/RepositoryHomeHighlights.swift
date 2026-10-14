import SwiftUI

struct RepositoryHomeHighlights: View {
    @ObservedObject var api: GitHub
    let repo: String
    @State private var release: ManagedRelease?
    @State private var run: WorkflowRun?
    @State private var releaseLoading = true
    @State private var runLoading = true
    @State private var releaseError = ""
    @State private var runError = ""
    @State private var releaseRevision = 0
    @State private var runRevision = 0
    private var runStatus: String {
        guard let run else { return "暂无运行记录" }
        switch run.conclusion ?? run.status {
        case "success": return "成功"
        case "failure", "timed_out": return "失败"
        case "cancelled": return "已取消"
        case "in_progress": return "运行中"
        case "queued", "waiting", "requested", "pending": return "等待运行"
        case "skipped": return "已跳过"
        default: return run.conclusion ?? run.status
        }
    }
    var body: some View {
        Section("发行版") {
            SoftGroupRows {
                if let release {
                    SoftGroupRow("latest") {
                        NavigationLink { ReleaseManagementDestination(api: api, repo: repo, id: release.id) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("最新正式发行版", systemImage: "shippingbox").font(.caption).foregroundStyle(.secondary)
                                Text(release.title).font(.headline)
                                Text(release.tag_name + " · " + String(release.date.prefix(10))).font(.caption).foregroundStyle(.secondary)
                                Text("查看说明与下载附件").font(.caption).foregroundStyle(.tint)
                            }.padding(.vertical, 4)
                        }
                    }
                } else if releaseLoading { SoftGroupRow("loading") { ProgressView("读取最新发行版…") } }
                else if releaseError.isEmpty { SoftGroupRow("empty") { Text("暂无正式发行版").foregroundStyle(.secondary) } }
                if !releaseError.isEmpty { SoftGroupRow("error") { Text(releaseError).font(.caption) } }
                SoftGroupRow("all") { NavigationLink("全部发行版") { ReleaseManagementDestination(api: api, repo: repo) } }
                SoftGroupRow("refresh") { Button(releaseError.isEmpty ? "刷新发行版" : "重试读取发行版") { releaseRevision += 1 }.disabled(releaseLoading) }
            }
        }.onReceive(NotificationCenter.default.publisher(for: .releaseManagementChanged)) { notice in
            if notice.userInfo?["repo"] as? String == repo,
               notice.userInfo?["generation"] as? UUID == AccountStore.generation { releaseRevision += 1 }
        }.task(id: releaseRevision) {
            releaseLoading = true; releaseError = ""; release = nil
            defer { releaseLoading = false }
            do {
                let data = try await api.communityRead(GitHub.repoPath(repo) + "/releases/latest")
                let value = try JSONDecoder().decode(ManagedRelease.self, from: data)
                try Task.checkCancellation(); guard api.isCurrentSession else { return }
                release = value
            } catch {
                if api.isCurrentSession, !RefreshFailure.isCancellation(error) {
                    releaseError = (error as? GitHubAPIError)?.status == 404 ? "未找到正式发行版，或当前账号没有读取权限。" : error.localizedDescription
                }
            }
        }
        Section("最近一次 Actions · 所有分支") {
            SoftGroupRows {
                if let run {
                    SoftGroupRow("latest") {
                        NavigationLink { WorkflowRunView(api: api, repo: repo, run: run) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                WorkflowStatusBadge(status: run.status, conclusion: run.conclusion)
                                Text(run.display_title ?? run.name ?? "Workflow").font(.headline).lineLimit(2)
                                Text("#\(run.run_number) · \(run.head_branch ?? "—") · \(String(run.created_at.prefix(10)))").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }
                    }
                } else if runLoading { SoftGroupRow("loading") { ProgressView("读取最近运行…") } }
                else if runError.isEmpty { SoftGroupRow("empty") { Text("暂无运行记录").foregroundStyle(.secondary) } }
                if !runError.isEmpty { SoftGroupRow("error") { Text(runError).font(.caption) } }
                SoftGroupRow("all") { NavigationLink("全部运行") { WorkflowRunsView(api: api, repo: repo, branch: "") } }
                SoftGroupRow("refresh") { Button(runError.isEmpty ? "刷新运行状态" : "重试读取运行") { runRevision += 1 }.disabled(runLoading) }
            }
        }.onReceive(NotificationCenter.default.publisher(for: .workflowRunDeleted)) { notice in
            if notice.userInfo?["repo"] as? String == repo,
               notice.userInfo?["generation"] as? UUID == AccountStore.generation { runRevision += 1 }
        }.task(id: runRevision) {
            runLoading = true; runError = ""; run = nil
            defer { runLoading = false }
            do {
                let values = try await api.workflowRuns(repo, branch: "", page: 1)
                try Task.checkCancellation(); guard api.isCurrentSession else { return }
                run = values.first
            } catch { if api.isCurrentSession, !RefreshFailure.isCancellation(error) { runError = error.localizedDescription } }
        }
    }
}
