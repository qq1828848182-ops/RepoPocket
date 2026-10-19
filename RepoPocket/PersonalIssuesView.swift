import SwiftUI

struct PersonalIssuesSection: View {
    @ObservedObject var api: GitHub
    @ObservedObject var store: CommunityPageStore<CollaborationItem>
    var body: some View {
        Section("议题") {
            SoftGroupRows {
                for item in store.items.prefix(3) {
                    if let repo = PersonalIssueRules.repository(item) {
                        SoftGroupRow(String(item.id)) {
                            NavigationLink { CollaborationDetailView(api: api, repo: repo, kind: .issues, number: item.number) }
                            label: { PersonalIssueRow(item: item, repo: repo) }
                            .accessibilityIdentifier("home-issue-\(item.number)")
                        }
                    }
                }
                if store.busy && store.items.isEmpty { SoftGroupRow("loading") { ProgressView("加载相关议题…") } }
                if store.loaded && store.items.isEmpty { SoftGroupRow("empty") { Text("暂无相关议题").foregroundStyle(.secondary) } }
                if !store.error.isEmpty {
                    SoftGroupRow("error") { Text(store.error).font(.caption).foregroundStyle(.secondary) }
                    SoftGroupRow("retry") { Button("重试议题") { load() }.disabled(store.busy) }
                }
                SoftGroupRow("all") {
                    NavigationLink { PersonalIssuesView(api: api, login: api.login) }
                    label: { Label("查看全部议题", systemImage: "exclamationmark.circle") }
                    .disabled(api.login.isEmpty).accessibilityIdentifier("home-personal-issues")
                }
            }
        }
    }
    private func load() {
        let login = api.login
        store.load(reset: true, api: api) { try await api.personalIssues(login, filter: .involved, page: $0) }
    }
}

struct PersonalIssueRow: View {
    let item: CollaborationItem
    let repo: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.state == "open" ? "exclamationmark.circle" : "checkmark.circle")
                .foregroundStyle(item.state == "open" ? Color.green : Color.purple).padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(repo + " #\(item.number)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(item.title).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                HStack {
                    Text(item.state == "open" ? "开放" : "已关闭")
                    if let date = item.updated_at { Text(ChinaDate.dateTime(date)).lineLimit(1) }
                    Spacer(minLength: 2)
                    Label("\(item.comments ?? 0)", systemImage: "bubble.right")
                }.font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}

struct PersonalIssuesView: View {
    @ObservedObject var api: GitHub
    let login: String
    @StateObject private var store = CommunityPageStore<CollaborationItem>()
    @State private var filter = PersonalIssueFilter.involved
    @State private var attempted = false
    var body: some View {
        List {
            Section {
                Picker("议题范围", selection: $filter) {
                    ForEach(PersonalIssueFilter.allCases) { Text($0.title).tag($0) }
                }.softGroupedRow(top: true, bottom: true)
            }
            if !store.items.isEmpty {
                Section {
                    SoftGroupRows {
                        for item in store.items {
                            if let repo = PersonalIssueRules.repository(item) {
                                SoftGroupRow(String(item.id)) {
                                    NavigationLink { CollaborationDetailView(api: api, repo: repo, kind: .issues, number: item.number) }
                                    label: { PersonalIssueRow(item: item, repo: repo) }
                                }
                            }
                        }
                    }
                }
            }
            if store.loaded && store.items.isEmpty && store.error.isEmpty {
                Section { Text("没有符合条件的议题").foregroundStyle(.secondary).softGroupedRow(top: true, bottom: true) }
            }
            CommunityPageFooter(store: store, next: { load() })
        }.listStyle(.insetGrouped).navigationTitle("我的议题").adaptiveWorkspaceLayout()
        .toolbar { Button("刷新") { load(reset: true) }.disabled(store.busy) }
        .onChange(of: filter) { _ in load(reset: true) }
        .task { guard !attempted else { return }; attempted = true; load() }
        .onDisappear { if store.busy { attempted = false }; store.cancel() }
    }
    private func load(reset: Bool = false) {
        let requested = filter
        store.load(reset: reset, api: api) { try await api.personalIssues(login, filter: requested, page: $0) }
    }
}
