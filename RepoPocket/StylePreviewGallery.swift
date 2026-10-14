#if DEBUG
import SwiftUI

/// Simulator-only fixed data: no credentials, no network or remote writes.
struct StylePreviewGallery: View {
    @StateObject private var api = GitHub()
    @State private var expanded = false
    private var account: Bool { ProcessInfo.processInfo.arguments.contains("-account-preview") }
    private let sample = "# RepoPocket\n\n适用于 iOS 16 的 GitHub 客户端。\n\n- 原生代码浏览\n- Issue 与 PR\n- Actions 与发行版\n\n" + String(repeating: "支持在 App 内浏览与管理仓库。\n\n", count: 30)
    var body: some View {
        NavigationStack {
            List {
                if account {
                    Section("账号") {
                        HStack { Image(systemName: "person.crop.circle.fill").font(.largeTitle); Text("wm0104"); Spacer(); Image(systemName: "checkmark"); Image(systemName: "trash").foregroundStyle(.red) }.softGroupedRow(top: true, bottom: true)
                    }
                    Section {
                        SoftGroupRows {
                            SoftGroupRow("oauth") { NavigationLink("使用 GitHub 浏览器授权") { Text("授权页面") } }
                            SoftGroupRow("token") { NavigationLink("添加 / 更新 GitHub 账号") { Text("Token 页面") } }
                            SoftGroupRow("notice") { Text("仅移除本机凭据，不会删除 GitHub 账号、远端仓库或本地工作区。").font(.caption) }
                        }
                    }
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("wm0104").font(.subheadline).foregroundStyle(.secondary)
                            Text("RepoPocket").font(.headline)
                            Text("GitHub 仓库管理客户端").font(.subheadline).foregroundStyle(.secondary)
                            HStack { Label("13", systemImage: "star"); Label("1", systemImage: "tuningfork") }.font(.caption)
                        }.softGroupedRow(top: true, bottom: true)
                    }
                    RepositoryCommunitySection(api: api, repo: "wm0104/RepoPocket", branch: "main", avatar: nil)
                    Section {
                        SoftGroupRows {
                            SoftGroupRow("branch") { HStack { Label("main", systemImage: "arrow.triangle.branch"); Spacer(); Text("更改分支").foregroundStyle(.blue) } }
                            SoftGroupRow("code") { NavigationLink { Text("代码") } label: { RepositoryFeatureLabel(title: "代码", symbol: "chevron.left.forwardslash.chevron.right", color: .gray) } }
                            SoftGroupRow("history") { NavigationLink { Text("提交") } label: { RepositoryFeatureLabel(title: "提交", symbol: "clock.arrow.circlepath", color: .gray) } }
                        }
                    }
                    Section {
                        SoftGroupRows {
                            SoftGroupRow("heading") { Label("README.md", systemImage: "info.circle").font(.subheadline).foregroundStyle(.secondary) }
                            SoftGroupRow("body") { CommunityMarkdown(text: expanded ? sample : ReadmePreviewRules.preview(sample)) }
                            SoftGroupRow("expand") { Button(expanded ? "收起自述文件" : "展开完整自述文件") { expanded.toggle() } }
                        }
                    }
                }
            }.navigationTitle(account ? "账号管理" : "RepoPocket").adaptiveWorkspaceLayout()
        }
    }
}
#endif
