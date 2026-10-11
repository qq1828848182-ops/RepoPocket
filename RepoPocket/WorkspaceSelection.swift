import Foundation

// Process-only UI state. Never contains credentials and is never serialized.
struct WorkspaceSelectionScope: Hashable {
    let accountID: String
    let workspace: String
    let repository: String
    let branch: String
    init(accountID: String, folder: URL, repository: String, branch: String) {
        self.accountID = accountID
        workspace = folder.resolvingSymlinksInPath().standardizedFileURL.path
        self.repository = repository.lowercased()
        self.branch = branch
    }
}

struct WorkspaceSelectionSession {
    private var selections: [WorkspaceSelectionScope: Set<String>] = [:]
    private var folders: [String: URL] = [:]
    func selected(in scope: WorkspaceSelectionScope) -> Set<String> { selections[scope] ?? [] }
    mutating func toggle(_ path: String, in scope: WorkspaceSelectionScope) {
        if selections[scope, default: []].contains(path) { selections[scope]?.remove(path) }
        else { selections[scope, default: []].insert(path) }
    }
    // Only call after a complete, validated scan. Deletions are valid change paths.
    mutating func scanSucceeded(_ availableChanges: Set<String>, in scope: WorkspaceSelectionScope) {
        selections[scope] = selected(in: scope).intersection(availableChanges)
    }
    mutating func commitSucceeded(_ committed: Set<String>, in scope: WorkspaceSelectionScope) {
        selections[scope] = selected(in: scope).subtracting(committed)
    }
    mutating func remember(_ folder: URL?, accountID: String) { folders[accountID] = folder }
    func rememberedFolder(accountID: String) -> URL? { folders[accountID] }
}

enum RefreshFailure {
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let e = error as NSError
        return e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled
    }
}
