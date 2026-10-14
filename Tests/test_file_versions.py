"""Exercise production editor operations with an in-memory remote; no GitHub writes."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / 'RepoPocket/RepoPocketApp.swift').read_text(encoding='utf-8')
API = (ROOT / 'RepoPocket/GitHub.swift').read_text(encoding='utf-8')


class FileVersionTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('swiftc'), 'Swift operation fixtures run in macOS CI')
    def test_editor_operations_against_concurrent_remote(self):
        editor = APP.split('struct FileView: View {', 1)[1].split('struct SettingsView:', 1)[0]
        save = '    private func save()' + editor.split('    private func save()', 1)[1].split('    private func download()', 1)[0]
        commit = '    func commit(' + API.split('    func commit(', 1)[1].split('    func delete(', 1)[0]
        source = r'''
import Foundation
struct AppError: LocalizedError { let text: String; var errorDescription: String? { text } }
enum RefreshFailure { static func isCancellation(_ error: Error) -> Bool { error is CancellationError } }
struct Entry { let sha: String; let type: String; let name: String; let path: String }
@MainActor final class FakeGitHub {
    var message = ""
    var isCurrentSession = true
    var remoteSHA = "initial"
    var gets = 0
    var deletes = 0
    var puts = 0
    var failRead = false
    static func repoPath(_ name: String) throws -> String { "/repos/" + name }
    static func filePath(_ name: String) throws -> String { name }
    func decoded<T: Decodable>(_ type: T.Type, _ path: String, method: String, object: [String: Any]) async throws -> T {
        guard object["sha"] as? String == remoteSHA else { throw AppError(text: "conflict") }
        puts += 1
        remoteSHA = "saved-\(puts)"
        return try JSONDecoder().decode(T.self, from: Data("{\"content\":{\"sha\":\"\(remoteSHA)\"}}".utf8))
    }
    func file(_ repo: String, path: String, branch: String) async throws -> Entry {
        gets += 1
        if failRead { throw AppError(text: "read failed") }
        return Entry(sha: remoteSHA, type: "file", name: "a.txt", path: path)
    }
    func delete(_ repo: String, entry: Entry, message: String, branch: String) async throws {
        guard entry.sha == remoteSHA else { throw AppError(text: "conflict") }
        deletes += 1
    }
''' + commit + r'''
}
@MainActor final class Editor {
    let api = FakeGitHub()
    let repo = "owner/repo", branch = "main"
    let entry = Entry(sha: "initial", type: "file", name: "a.txt", path: "a.txt")
    var text = "my edit", loadedText = "original", currentSHA = "initial"
    var commitMessage = "Edit"
    var busy = false, deleted = false
''' + save + r'''
    func exercise() async throws {
        // Saving must succeed even if a follow-up GET would fail.
        api.failRead = true
        await save()
        precondition(api.puts == 1 && api.gets == 0)
        precondition(currentSHA == "saved-1" && loadedText == "my edit" && !busy)
        // Another author updates after our save. We must not adopt their SHA.
        api.remoteSHA = "other-author"; text = "second edit"
        await save()
        precondition(api.puts == 1 && currentSHA == "saved-1" && loadedText == "my edit")
        api.failRead = false
        await remove()
        precondition(api.deletes == 0 && !deleted && !busy)
        // Reloading/confirming the actual version allows a deliberate deletion.
        currentSHA = "other-author"
        await remove()
        precondition(api.deletes == 1 && deleted)
        // Without loading text, protect the version shown in the original listing.
        let unopened = Editor(); unopened.currentSHA = ""; unopened.api.remoteSHA = "new-content"
        await unopened.remove()
        precondition(unopened.api.deletes == 0 && !unopened.deleted)
        for (expected, actual, isFile) in [("", "x", true), ("x", "x", false)] {
            do { try FileVersionRules.requireUnchanged(expectedSHA: expected, actualSHA: actual, isFile: isFile); preconditionFailure("unsafe delete") } catch { }
        }
        print("PASS production save/delete: response SHA, no follow-up GET, conflict preservation, stale-delete refusal and deliberate delete")
    }
}
@main struct Run { static func main() async throws { try await Editor().exercise() } }
'''
        source += (ROOT / 'RepoPocket/FileVersionRules.swift').read_text(encoding='utf-8')
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'main.swift'
            path.write_text(source, encoding='utf-8')
            binary = str(Path(folder) / 'test')
            subprocess.run(['swiftc', '-parse-as-library', str(path), '-o', binary], check=True)
            subprocess.run([binary], check=True)

    def test_reload_requires_discard_confirmation(self):
        editor = APP.split('struct FileView: View {', 1)[1].split('struct SettingsView:', 1)[0]
        self.assertIn('if editable && text != loadedText { confirmReload = true }', editor)
        self.assertIn('isPresented: $confirmReload', editor)
        self.assertIn('丢弃修改并重新加载', editor)
        self.assertIn('.frame(minHeight: 260).disabled(busy)', editor)


if __name__ == '__main__':
    unittest.main()
