import SwiftUI

struct CommunityProfileSection: View {
    @ObservedObject var api: GitHub
    let login: String
    let avatar: String?
    @State private var profile: CommunityProfile?
    @State private var error = ""
    @State private var revision = 0
    var body: some View {
        Section("用户资料") {
            HStack(alignment: .top) {
                GitHubAvatar(url: profile?.avatar_url ?? avatar, size: 56)
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile?.name ?? login).font(.headline)
                    Text("@" + login).font(.subheadline).foregroundStyle(.secondary)
                    if let bio = profile?.bio, !bio.isEmpty { Text(bio).textSelection(.enabled) }
                }
            }
            if let profile {
                if let count = profile.public_repos { Text("\(count) 个公开仓库").font(.caption) }
                if let count = profile.followers { Text("\(count) 位关注者 · 正在关注 \(profile.following ?? 0) 人").font(.caption) }
                if let company = profile.company, !company.isEmpty { Label(company, systemImage: "building.2") }
                if let location = profile.location, !location.isEmpty { Label(location, systemImage: "mappin") }
                if let url = CommunityRules.webURL(profile.blog) { Link("个人网站", destination: url) }
            }
            NavigationLink("公开活动") { CommunityEventsView(api: api, login: login) }
            if let url = CommunityRules.webURL("https://github.com/" + GitHub.component(login) + "?tab=overview") {
                Link("贡献日历与完整资料", destination: url)
            }
            if !error.isEmpty { Text(error).font(.caption); Button("重试资料加载") { revision += 1 } }
        }.task(id: revision) {
            error = ""
            do {
                let value = try await api.communityProfile(login)
                try Task.checkCancellation(); guard api.isCurrentSession else { return }; profile = value
            } catch { if api.isCurrentSession, !RefreshFailure.isCancellation(error) { self.error = "资料加载失败，仓库浏览仍可使用。" } }
        }
    }
}

struct CommunityEventsView: View {
    @ObservedObject var api: GitHub
    let login: String
    var received = false
    @StateObject private var store = CommunityPageStore<CommunityEvent>()
    var body: some View {
        List {
            ForEach(store.items) { event in
                NavigationLink { BrowserView(api: api, repo: event.repo.name, path: "", branch: "") } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { GitHubAvatar(url: event.actor.avatar_url, size: 24); Text(event.actor.login + " " + event.summary) }
                        Text(event.repo.name).font(.headline)
                        if let date = event.created_at { Text(date).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if store.loaded && store.items.isEmpty { Text("暂无可见活动") }
            CommunityPageFooter(store: store, next: { load() })
            Text("GitHub 活动流可能延迟，且仅提供有限时间内的记录。").font(.caption).foregroundStyle(.secondary)
        }.navigationTitle(received ? "关注动态" : "公开活动").adaptiveWorkspaceLayout()
        .toolbar { Button("刷新") { load(reset: true) }.disabled(store.busy) }
        .task { if !store.loaded { load() } }.onDisappear { store.cancel() }
    }
    private func load(reset: Bool = false) {
        store.load(reset: reset, api: api) { try await api.communityEvents(login, received: received, page: $0) }
    }
}

struct CommunityDiscoveryView: View {
    @ObservedObject var api: GitHub
    @State private var language = ""
    @State private var days = 7
    @StateObject private var store = CommunityPageStore<Repository>()
    var body: some View {
        List {
            Section("近期新建的热门仓库") {
                Picker("时间范围", selection: $days) { Text("一天").tag(1); Text("一周").tag(7); Text("一月").tag(30) }
                Picker("语言", selection: $language) {
                    ForEach(RepositorySearchOptions.languages, id: \.self) { Text($0.isEmpty ? "所有语言" : $0).tag($0) }
                }
                Button("加载 / 刷新") { load(reset: true) }.disabled(store.busy)
                Text("按所选时间内新建仓库的累计 Star 排序；这不是 GitHub Trending 的增长榜。").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(store.items) { repository in
                NavigationLink { BrowserView(api: api, repo: repository.full_name, path: "", branch: repository.default_branch ?? "") } label: {
                    RepositoryCard(repository: repository, account: api.login, api: api)
                }
            }
            if store.loaded && store.items.isEmpty { Text("没有符合条件的仓库") }
            CommunityPageFooter(store: store, next: { load() })
            Section("GitHub 官方榜单") {
                Link("热门仓库 · 每日 / 每周 / 每月", destination: URL(string: "https://github.com/trending")!)
                Link("热门开发者", destination: URL(string: "https://github.com/trending/developers")!)
            }
            if !api.login.isEmpty {
                Section { NavigationLink("关注动态") { CommunityEventsView(api: api, login: api.login, received: true) } }
            }
        }.navigationTitle("发现").adaptiveWorkspaceLayout()
        .onChange(of: language) { _ in load(reset: true) }
        .onChange(of: days) { _ in load(reset: true) }
        .task { if !store.loaded { load() } }.onDisappear { store.cancel() }
    }
    private func load(reset: Bool = false) {
        let requestedDays = days, requestedLanguage = language
        // Anchor the calendar once per request set; never change the query mid-page.
        if reset || dateQuery.isEmpty {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"
            dateQuery = "created:>=" + formatter.string(from: Date().addingTimeInterval(-Double(requestedDays) * 86400))
        }
        let query = dateQuery
        store.load(reset: reset, api: api) { page in
            try await api.searchRepositories(query, page: page, options: .init(language: requestedLanguage, sort: .stars)).items
        }
    }
    @State private var dateQuery = ""
}

struct RepositoryContributorsView: View {
    @ObservedObject var api: GitHub
    let repo: String
    @StateObject private var store = CommunityPageStore<RepositoryContributor>()
    var body: some View {
        List {
            ForEach(store.items) { person in
                NavigationLink { UserRepositoriesView(api: api, user: User(id: nil, login: person.login, avatar_url: person.avatar_url, name: nil, followers: nil, following: nil)) } label: {
                    HStack { GitHubAvatar(url: person.avatar_url); Text(person.login); Spacer(); Text("\(person.contributions) 次提交").font(.caption) }
                }
            }
            if store.loaded && store.items.isEmpty { Text("暂无贡献者") }
            CommunityPageFooter(store: store, next: { load() })
        }.navigationTitle("贡献者").adaptiveWorkspaceLayout()
        .task { if !store.loaded { load() } }.onDisappear { store.cancel() }
    }
    private func load() { store.load(api: api) { try await api.contributors(repo, page: $0) } }
}

struct RepositoryToolsView: View {
    @ObservedObject var api: GitHub
    let repo: String
    @State private var languages: [String: Int] = [:]
    @State private var error = ""
    @State private var revision = 0
    private var ordered: [String] { languages.keys.sorted { languages[$0, default: 0] > languages[$1, default: 0] } }
    var body: some View {
        List {
            Section("代码语言统计") {
                ForEach(ordered, id: \.self) { name in
                    LabeledContent(name, value: ByteCountFormatter.string(fromByteCount: Int64(languages[name, default: 0]), countStyle: .file))
                }
                Text("GitHub Linguist 的语言字节数，不是代码行数。").font(.caption).foregroundStyle(.secondary)
                if !error.isEmpty { Text(error).font(.caption); Button("重试") { revision += 1 } }
            }
            Section("仓库工具") {
                NavigationLink("贡献者") { RepositoryContributorsView(api: api, repo: repo) }
                if let url = CommunityRules.repositoryURL(repo, suffix: "/graphs/contributors") { Link("贡献历史图", destination: url) }
                if let url = CommunityRules.repositoryURL(repo, suffix: "/pulse") { Link("仓库活动统计", destination: url) }
                if let canonical = try? RepositoryInput.parse(repo), let url = URL(string: "https://star-history.com/#" + canonical + "&Date") { Link("Star 历史图（外部网站）", destination: url) }
                Link("代码行数统计（CodeTabs，手动输入公开仓库）", destination: URL(string: "https://codetabs.com/count-loc/count-loc-online.html")!)
                Text("外部工具在浏览器打开，不发送 RepoPocket 中的 Token；服务可用性由对应网站决定。").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("统计与工具").adaptiveWorkspaceLayout()
        .task(id: revision) {
            error = ""
            do {
                let result = try await api.repositoryLanguages(repo)
                try Task.checkCancellation(); guard api.isCurrentSession else { return }; languages = result
            } catch { if api.isCurrentSession, !RefreshFailure.isCancellation(error) { self.error = error.localizedDescription } }
        }
    }
}
