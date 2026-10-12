"""Network-free production deletion gates and settings contracts. No HTTP requests."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

api = Path('RepoPocket/GitHub.swift').read_text()
core = Path('RepoPocket/RepositoryDeletion.swift').read_text()
ui = Path('RepoPocket/RepositoryDeletionView.swift').read_text()
app = Path('RepoPocket/RepoPocketApp.swift').read_text()

class DeletionTests(unittest.TestCase):
    def test_production_wiring(self):
        self.assertIn('repositoryInfo?.permissions?.admin != true', app)
        self.assertIn('confirmation != repository.full_name', ui)
        self.assertIn('interactiveDismissDisabled(busy)', ui)
        self.assertIn('guard !busy else { return }', ui)
        self.assertIn('context: api.deletionContext(repositoryInfo)', app)
        self.assertIn('try self.ensureActiveAccount()', api)
        self.assertIn('statusCode == 204', api)
        self.assertIn('delete_repo', core)
        self.assertIn('Administration: write', core)
        self.assertIn('let permissions: Permissions?', api)
        deletion = api[api.index('    func deleteRepository'):api.index('    private func ensureActiveAccount')]
        self.assertIn('method: "DELETE"', deletion)
        self.assertNotIn('FileManager', deletion + core + ui)
        self.assertNotIn('Section("已保存账号")', app)
        self.assertIn('账号管理：切换、添加或移除本机账号', app)
        self.assertIn('.refreshable { await refreshProfile() }', app)
        self.assertIn('不会删除 GitHub 账号、远端仓库或本地工作区', app)
        self.assertIn('AccountStore.activate(account.id)', app)
        self.assertIn('AccountStore.remove(account.id)', app)

    @unittest.skipUnless(shutil.which('swiftc'), 'requires macOS Actions Swift compiler')
    def test_mocked_production_orchestration(self):
        models = api[api.index('struct User:'):api.index('struct Entry:')]
        source = 'import Foundation\n' + api[api.index('struct AppError:'):api.index('struct GitHubAPIError:')] + models + core.replace('import Foundation', '') + r'''
@main struct Tests {
    static func main() async throws {
        let generation = UUID()
        let target = RepositoryDeletionContext(accountID: "alice", generation: generation, repositoryID: 7, fullName: "alice/tool")
        func repository(_ id: Int = 7, _ name: String = "alice/tool", _ admin: String = "true") throws -> Repository {
            let json = "{\"id\":\(id),\"full_name\":\"\(name)\",\"name\":\"tool\",\"html_url\":\"https://github.com/alice/tool\",\"permissions\":{\"admin\":\(admin)}}"
            return try JSONDecoder().decode(Repository.self, from: Data(json.utf8))
        }
        let fresh = try repository()
        // Exact confirmation: no trimming, partial names, case folding or blank bypass.
        for bad in ["", "tool", "bob/tool", "Alice/tool", " alice/tool", "alice/tool "] {
            var calls = 0
            do {
                _ = try await RepositoryDeletion.execute(context: target, confirmation: bad, current: { target }, fetch: { calls += 1; return fresh }, remove: { calls += 100 })
                preconditionFailure("confirmation bypass")
            } catch { precondition(calls == 0) }
        }
        // Account, generation (including switch away-and-back), and selected repo changes.
        for changed in [
            RepositoryDeletionContext(accountID: "bob", generation: generation, repositoryID: 7, fullName: "alice/tool"),
            RepositoryDeletionContext(accountID: "alice", generation: UUID(), repositoryID: 7, fullName: "alice/tool"),
            RepositoryDeletionContext(accountID: "alice", generation: generation, repositoryID: 8, fullName: "alice/tool"),
            RepositoryDeletionContext(accountID: "alice", generation: generation, repositoryID: 7, fullName: "alice/other")
        ] {
            var calls = 0
            do {
                _ = try await RepositoryDeletion.execute(context: target, confirmation: target.fullName, current: { changed }, fetch: { calls += 1; return fresh }, remove: { calls += 100 })
                preconditionFailure("isolation bypass")
            } catch { precondition(calls == 0) }
            var current = target
            do {
                _ = try await RepositoryDeletion.execute(context: target, confirmation: target.fullName, current: { current }, fetch: { current = changed; return fresh }, remove: { calls += 100 })
                preconditionFailure("post-await isolation bypass")
            } catch { precondition(calls == 0) }
        }
        // API repo identity and admin permission must be freshly checked.
        for denied in [try repository(8), try repository(7, "alice/renamed"), try repository(7, "alice/tool", "false"), try repository(7, "alice/tool", "null")] {
            var deletes = 0
            do {
                _ = try await RepositoryDeletion.execute(context: target, confirmation: target.fullName, current: { target }, fetch: { denied }, remove: { deletes += 1 })
                preconditionFailure("API identity/admin bypass")
            } catch { precondition(deletes == 0) }
        }
        var deletes = 0
        let result = try await RepositoryDeletion.execute(context: target, confirmation: target.fullName, current: { target }, fetch: { fresh }, remove: { deletes += 1 })
        precondition(deletes == 1 && result.contains("已删除远端仓库") && result.contains("本地工作区未删除"))
        // Failure must not manufacture success; mocks include permission, missing repo and transport errors.
        for text in ["403 " + RepositoryDeletion.permissionHelp, "404 missing repo", "network failure"] {
            do {
                _ = try await RepositoryDeletion.execute(context: target, confirmation: target.fullName, current: { target }, fetch: { fresh }, remove: { throw AppError(text: text) })
                preconditionFailure("failure swallowed")
            } catch { precondition(error.localizedDescription == text) }
        }
        do {
            _ = try await RepositoryDeletion.execute(context: target, confirmation: target.fullName, current: { target }, fetch: { throw AppError(text: "GET failed") }, remove: { preconditionFailure("DELETE after GET failure") })
            preconditionFailure("GET failure swallowed")
        } catch { precondition(error.localizedDescription == "GET failed") }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await RepositoryDeletion.execute(context: target, confirmation: target.fullName, current: { target }, fetch: { preconditionFailure("GET after cancel") }, remove: { preconditionFailure("DELETE after cancel") })
                preconditionFailure("cancel ignored")
            } catch { precondition(error is CancellationError) }
        }
        await cancelled.value
        print("PASS: exact confirmation, account/generation/repo isolation, fresh admin/identity, success, 403/404/network/GET errors, cancellation; zero real HTTP")
    }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'main.swift'
            path.write_text(source)
            executable = str(Path(directory) / 'tests')
            subprocess.run(['swiftc', '-parse-as-library', str(path), '-o', executable], check=True)
            subprocess.run([executable], check=True)

if __name__ == '__main__':
    unittest.main()
