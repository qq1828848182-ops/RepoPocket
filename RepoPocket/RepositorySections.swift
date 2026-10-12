import SwiftUI

/// Two stable identities, also used by navigation and accessibility.
enum RepositoryHomeSection: String, CaseIterable, Identifiable {
    case owned, starred

    var id: String { rawValue }
    var title: String {
        switch self {
        case .owned: return "我的仓库"
        case .starred: return "已加星标"
        }
    }
    var systemImage: String {
        switch self {
        case .owned: return "folder"
        case .starred: return "star"
        }
    }
}

/// A single List row owns the complete outline. Never round individual rows or
/// animate the height/shape: the header and icon remain mounted when collapsed.
struct RepositorySectionContainer<Content: View>: View {
    let section: RepositoryHomeSection
    @Binding var expanded: Bool
    private let content: Content

    init(section: RepositoryHomeSection, expanded: Binding<Bool>,
         @ViewBuilder content: () -> Content) {
        self.section = section
        self._expanded = expanded
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: section.systemImage)
                        .frame(width: 24)
                        .foregroundStyle(Color.accentColor)
                    Text(section.title).font(.headline)
                    Spacer(minLength: 8)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(section.title)
            .accessibilityValue(expanded ? "已展开" : "已收起")
            .accessibilityHint(expanded ? "轻点收起" : "轻点展开")

            if expanded {
                Divider().padding(.horizontal, 16)
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
        // Suppress ancestor implicit animations too, including Reduce Motion.
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

/// Native repository list; browsing and Fork reuse existing guarded APIs.
struct RepositoryCollectionView: View {
    @ObservedObject var api: GitHub
    let section: RepositoryHomeSection
    @State private var repositories: [Repository] = []
    @State private var busy = false
    @State private var loaded = false
    @State private var refreshing = false
    @State private var pendingFork: Repository?

    var body: some View {
        List {
            if busy && repositories.isEmpty && !refreshing {
                ProgressView().frame(maxWidth: .infinity)
            } else if loaded && repositories.isEmpty {
                Text(section == .owned ? "暂无仓库" : "暂无已加星标仓库")
                    .foregroundStyle(.secondary)
            } else if !loaded && !busy {
                Text("请登录后刷新").foregroundStyle(.secondary)
            }
            ForEach(repositories) { repository in
                NavigationLink {
                    BrowserView(api: api, repo: repository.full_name, path: "",
                                branch: repository.default_branch ?? "")
                } label: {
                    RepositoryCard(repository: repository, account: api.login)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !isOwn(repository) {
                        Button("复刻") { pendingFork = repository }
                            .tint(.accentColor).disabled(busy)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(section.title)
        .adaptiveWorkspaceLayout()
        .toolbar { Button("刷新") { Task { await load() } }.disabled(busy) }
        .refreshable { refreshing = true; defer { refreshing = false }; await load() }
        .task { if !loaded && !CredentialStore.read().isEmpty { await load() } }
        .confirmationDialog("复刻到我的仓库？", isPresented: Binding(
            get: { pendingFork != nil },
            set: { if !$0 { pendingFork = nil } }
        ), titleVisibility: .visible) {
            if let repository = pendingFork {
                Button("复刻") {
                    pendingFork = nil
                    Task { await fork(repository) }
                }
            }
            Button("取消", role: .cancel) { pendingFork = nil }
        } message: {
            Text(pendingFork?.full_name ?? "")
        }
    }

    private func isOwn(_ repository: Repository) -> Bool {
        let owner = repository.full_name.split(separator: "/").first.map(String.init) ?? ""
        return !api.login.isEmpty && owner.caseInsensitiveCompare(api.login) == .orderedSame
    }

    private func load() async {
        guard !busy else { return }
        let generation = AccountStore.generation
        busy = true
        defer { busy = false }
        do {
            try await api.identify()
            let result: [Repository]
            switch section {
            case .owned:
                let allRepositories = try await api.repositories()
                result = allRepositories.filter { repository in
                    let owner = repository.full_name.split(separator: "/").first.map(String.init) ?? ""
                    return owner.caseInsensitiveCompare(api.login) == .orderedSame
                }
            case .starred:
                result = try await api.starredRepositories()
            }
            try Task.checkCancellation()
            guard generation == AccountStore.generation else { return }
            repositories = result
            loaded = true
        } catch {
            if !RefreshFailure.isCancellation(error) { api.message = error.localizedDescription }
        }
    }

    private func fork(_ repository: Repository) async {
        guard !busy else { return }
        let generation = AccountStore.generation
        busy = true
        defer { busy = false }
        do {
            let result = try await api.fork(repository.full_name)
            try Task.checkCancellation()
            guard generation == AccountStore.generation else { return }
            api.message = "已复刻：\(result.full_name)。GitHub 可能需要片刻准备内容。"
        } catch {
            if !RefreshFailure.isCancellation(error) { api.message = error.localizedDescription }
        }
    }
}
