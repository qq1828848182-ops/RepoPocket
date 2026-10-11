import Foundation

enum GitCoreError: LocalizedError {
    case invalidRepository
    case unavailable
    var errorDescription: String? {
        switch self {
        case .invalidRepository: return "选择的目录不是有效的 Git 仓库。"
        case .unavailable: return "Git 内核尚未完成初始化。"
        }
    }
}

struct LocalGitRepository: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }
    var gitDirectory: URL { url.appendingPathComponent(".git", isDirectory: true) }
    var isValid: Bool { FileManager.default.fileExists(atPath: gitDirectory.path) }
}

/// Stable boundary for the native Git engine. libgit2 is attached behind this
/// actor in the next milestone; UI code should depend on this API only.
@MainActor
final class GitCore: ObservableObject {
    @Published private(set) var repositories: [LocalGitRepository] = []
    @Published private(set) var isBusy = false
    private var scopedURLs = Set<URL>()

    deinit {
        for url in scopedURLs { url.stopAccessingSecurityScopedResource() }
    }

    func importRepository(_ url: URL) throws {
        guard url.startAccessingSecurityScopedResource() else { throw GitCoreError.invalidRepository }
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) else {
            url.stopAccessingSecurityScopedResource()
            throw GitCoreError.invalidRepository
        }
        if !repositories.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            repositories.append(LocalGitRepository(url: url))
            scopedURLs.insert(url)
        } else {
            url.stopAccessingSecurityScopedResource()
        }
    }

    func remove(_ repository: LocalGitRepository) {
        repositories.removeAll { $0.id == repository.id }
        if let scoped = scopedURLs.first(where: { $0.standardizedFileURL == repository.url.standardizedFileURL }) {
            scoped.stopAccessingSecurityScopedResource()
            scopedURLs.remove(scoped)
        }
    }
}
