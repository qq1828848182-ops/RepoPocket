import Foundation
import Combine

struct ReleasePage: Sendable {
    let values: [Release]
    let hasNext: Bool
}
enum RepositoryReleaseRules {
    static func published(_ values: [Release]) -> [Release] { values.filter { !$0.draft && $0.published_at != nil } }
    static func newest(_ values: [Release]) -> Release? { published(values).max { ($0.published_at ?? "") < ($1.published_at ?? "") } }
    static func isLatest(_ release: Release, latestID: Int?) -> Bool { !release.draft && release.prerelease != true && release.id == latestID }
}

// Actor-owned decoding/formatting runs off MainActor; no detached task captures GitHub/session state.
actor RepositoryReleaseProcessing {
    static let shared = RepositoryReleaseProcessing()
    private let dates = ISO8601DateFormatter()
    func decodePage(_ bytes: Data) throws -> [Release] {
        try Task.checkCancellation()
        return try JSONDecoder().decode([Release].self, from: bytes)
            .filter { !$0.draft && $0.published_at != nil }.map { prepare($0) }
    }
    func decodeLatest(_ bytes: Data) throws -> Release {
        try Task.checkCancellation()
        return prepare(try JSONDecoder().decode(Release.self, from: bytes))
    }
    private func prepare(_ value: Release) -> Release {
        var value = value
        value.displayDate = value.published_at.flatMap { dates.date(from: $0) }
        return value
    }
    func notes(_ text: String) throws -> [String] {
        var chunks: [String] = [], start = text.startIndex
        while start < text.endIndex {
            try Task.checkCancellation()
            let end = text.index(start, offsetBy: 2048, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(String(text[start..<end])); start = end
        }
        return chunks
    }
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
    private var seen = Set<Int>()
    private var identity = UUID()
    private var pageIdentity = UUID()
    private var target: String?
    private var summaryTask: Task<Void, Never>?
    private var latestTask: Task<Void, Never>?
    private var pageTask: Task<Void, Never>?
    func cancelPage() { pageIdentity = UUID(); pageTask?.cancel(); pageTask = nil; paging = false }
    func cancel() { identity = UUID(); summaryTask?.cancel(); latestTask?.cancel(); cancelPage(); loading = false }
    func reset() { cancel(); target = nil; count = nil; recent = nil; latestID = nil; error = nil; history = []; seen = []; page = 1; hasNext = true; historyError = nil }
    private func matches(_ token: UUID, _ generation: UUID, _ repo: String, _ api: GitHub) -> Bool {
        token == identity && generation == AccountStore.generation && target == repo && api.isCurrentSession && !Task.isCancelled
    }
    private func accept(_ result: ReleasePage) {
        // One bounded page per user action; retain IDs and page cursor to avoid duplicate work on appear.
        let added = RepositoryReleaseRules.published(result.values).filter { seen.insert($0.id).inserted }
        history += added
        if let newest = RepositoryReleaseRules.newest(added), recent == nil || (newest.published_at ?? "") > (recent?.published_at ?? "") { recent = newest }
        hasNext = result.hasNext; page += 1
        count = hasNext ? nil : history.count // Never label a partial count as an exact total.
    }
    func load(api: GitHub, repo: String, retry: Bool = false) async {
        if target == repo && !retry { return }
        reset(); target = repo; loading = true
        let token = identity, generation = AccountStore.generation
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await api.repositoryReleasePage(repo, page: 1)
                guard self.matches(token, generation, repo, api) else { return }
                self.accept(result); self.loading = false
                // Latest is optional badge metadata, never a dependency of root navigation/first page.
                self.latestTask = Task { [weak self] in
                    do {
                        let latest = try await api.repositoryLatestRelease(repo)
                        guard let self, self.matches(token, generation, repo, api) else { return }
                        self.latestID = latest?.id
                    } catch { /* First-page navigation remains usable if badge metadata fails. */ }
                }
            } catch {
                guard self.matches(token, generation, repo, api) else { return }
                self.loading = false; self.error = "发行版载入失败，请重试。"; self.count = nil
            }
        }
        summaryTask = task
        await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
        if identity == token && task.isCancelled { reset() }
    }
    func more(api: GitHub, repo: String, retry: Bool = false) {
        guard !loading, !paging, hasNext, target == repo, api.isCurrentSession,
              historyError == nil || retry else { return }
        paging = true; historyError = nil
        let token = identity, generation = AccountStore.generation, number = page, pagingToken = UUID()
        pageIdentity = pagingToken
        pageTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.pageIdentity == pagingToken { self.paging = false; self.pageTask = nil } }
            do {
                let result = try await api.repositoryReleasePage(repo, page: number)
                guard self.pageIdentity == pagingToken, self.matches(token, generation, repo, api) else { return }
                self.accept(result)
            } catch {
                guard self.pageIdentity == pagingToken, self.matches(token, generation, repo, api) else { return }
                self.historyError = "历史版本载入失败，请重试。"
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
            @MainActor func valid() -> Bool { self.identity == token && generation == AccountStore.generation && api.isCurrentSession && !Task.isCancelled }
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
