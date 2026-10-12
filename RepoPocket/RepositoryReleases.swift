import Foundation
import Combine

struct ReleasePage {
    let values: [Release]
    let hasNext: Bool
}
enum RepositoryReleaseRules {
    static func published(_ values: [Release]) -> [Release] { values.filter { !$0.draft && $0.published_at != nil } }
    static func newest(_ values: [Release]) -> Release? { published(values).max { ($0.published_at ?? "") < ($1.published_at ?? "") } }
    static func isLatest(_ release: Release, latestID: Int?) -> Bool { !release.draft && release.prerelease != true && release.id == latestID }
}

@MainActor final class RepositoryReleaseState: ObservableObject {
    @Published var count: Int?
    @Published var recent: Release?
    @Published var latestID: Int?
    @Published var error: String?
    @Published var loading = false
    @Published var history: [Release] = []
    @Published var hasNext = true
    @Published var historyError: String?
    @Published var paging = false
    private var page = 1
    private var identity = UUID()
    private var target: String?
    private var summaryTask: Task<Void, Never>?
    private var pageTask: Task<Void, Never>?
    func cancel() { identity = UUID(); summaryTask?.cancel(); pageTask?.cancel(); loading = false; paging = false }
    func reset() { cancel(); target = nil; count = nil; recent = nil; latestID = nil; error = nil; history = []; page = 1; hasNext = true; historyError = nil }
    private func matches(_ token: UUID, _ generation: UUID, _ repo: String, _ api: GitHub) -> Bool {
        token == identity && generation == AccountStore.generation && target == repo && api.isCurrentSession && !Task.isCancelled
    }
    func load(api: GitHub, repo: String, retry: Bool = false) async {
        if target == repo && !retry && (count != nil || loading || error != nil) { return }
        reset(); target = repo; loading = true
        let token = identity, generation = AccountStore.generation
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                // A latest 404 is only empty after repository access is independently verified.
                let latest = try await api.repositoryLatestRelease(repo)
                var total = 0, newest: Release?, seen = Set<Int>(), number = 1
                while true {
                    try Task.checkCancellation()
                    let result = try await api.repositoryReleasePage(repo, page: number)
                    guard self.matches(token, generation, repo, api) else { return }
                    for release in RepositoryReleaseRules.published(result.values) where seen.insert(release.id).inserted {
                        total += 1
                        if newest == nil || (release.published_at ?? "") > (newest?.published_at ?? "") { newest = release }
                    }
                    if !result.hasNext { break }
                    number += 1
                }
                guard self.matches(token, generation, repo, api) else { return }
                self.latestID = latest?.id; self.count = total; self.recent = newest; self.loading = false
            } catch {
                guard self.matches(token, generation, repo, api) else { return }
                self.loading = false; self.error = "发行版载入失败，请重试。"; self.count = nil
            }
        }
        summaryTask = task
        await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
    }
    func more(api: GitHub, repo: String) {
        guard !paging, hasNext, target == repo, api.isCurrentSession else { return }
        paging = true; historyError = nil
        let token = identity, generation = AccountStore.generation, number = page
        pageTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await api.repositoryReleasePage(repo, page: number)
                guard self.matches(token, generation, repo, api) else { return }
                var seen = Set(self.history.map(\.id))
                self.history += RepositoryReleaseRules.published(result.values).filter { seen.insert($0.id).inserted }
                self.hasNext = result.hasNext; self.page += 1; self.paging = false
            } catch {
                guard self.matches(token, generation, repo, api) else { return }
                self.paging = false; self.historyError = "历史版本载入失败，请重试。"
            }
        }
    }
}

@MainActor final class RepositoryAssetDownload: ObservableObject {
    @Published var activeID: Int?
    @Published var progress = 0.0
    @Published var message: String?
    @Published var saved: URL?
    private var task: Task<Void, Never>?
    private var identity = UUID()
    func cancel() { identity = UUID(); task?.cancel(); task = nil; activeID = nil; progress = 0; message = "已取消下载。" }
    func reset() { cancel(); saved = nil; message = nil }
    func start(api: GitHub, repo: String, asset: Asset) {
        guard activeID == nil, api.isCurrentSession else { return }
        let token = UUID(), generation = AccountStore.generation
        identity = token; activeID = asset.id; progress = 0; saved = nil; message = nil
        task = Task { [weak self] in
            guard let self else { return }
            func valid() -> Bool { self.identity == token && generation == AccountStore.generation && api.isCurrentSession && !Task.isCancelled }
            defer { if self.identity == token { self.activeID = nil; self.task = nil } }
            do {
                try await DownloadStore.shared.requireAuthorization()
                guard valid() else { throw CancellationError() }
                DownloadStore.shared.begin(); defer { DownloadStore.shared.end() }
                let temporary = try await api.downloadReleaseAsset(repo, asset: asset) { value in
                    Task { @MainActor [weak self] in
                        guard let self, self.identity == token, generation == AccountStore.generation, api.isCurrentSession else { return }
                        self.progress = value
                    }
                }
                defer { try? FileManager.default.removeItem(at: temporary.deletingLastPathComponent()) }
                guard valid() else { throw CancellationError() }
                let file = try DownloadStore.shared.persist(temporary, session: generation)
                guard valid() else { return }
                self.saved = file; self.message = "已保存到 " + DownloadStore.shared.label + "；可通过系统分享选择应用，不会自动安装。"
            } catch {
                guard self.identity == token, generation == AccountStore.generation, api.isCurrentSession else { return }
                self.message = (error is CancellationError || (error as? URLError)?.code == .cancelled) ? "已取消下载。" : error.localizedDescription
            }
        }
    }
}
