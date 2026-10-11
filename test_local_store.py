import subprocess, tempfile
from pathlib import Path
source = Path('RepoPocket/WorkspaceView.swift').read_text()
core = source[source.index('struct LocalSnapshot:'):source.index('\nstruct WorkspaceView:')]
remote = Path('RepoPocket/WorkspaceRemote.swift').read_text().replace('import Foundation','').replace('import CryptoKit','')
tests = r'''
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root); try? fm.removeItem(at: LocalStore.metadata(root)); try? fm.removeItem(at: LocalStore.bindingURL(root)) }
func put(_ p: String, _ text: String) throws {
 let u = root.appendingPathComponent(p)
 try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
 try Data(text.utf8).write(to: u)
}
try put("a.txt", "abc")
try put("gone.txt", "deleted")
try put(".github/ci.yml", "hidden")
try put(".git/config", "ignored")
let first = try LocalStore.snapshot(root)
precondition(first.hashes["a.txt"] == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
precondition(first.hashes[".github/ci.yml"] != nil && first.hashes[".git/config"] == nil)
try JSONEncoder().encode(first).write(to: LocalStore.metadata(root), options: .atomic)
try put("a.txt", "changed")
try put("new.txt", "added")
try fm.removeItem(at: root.appendingPathComponent("gone.txt"))
let c = try LocalStore.changes([root])
precondition(c.count == 3)
precondition(c.contains { $0.kind == "新增" } && c.contains { $0.kind == "删除" } && c.contains { $0.kind == "修改" })
var binding = WorkspaceBinding(repo: "test/test", branch: "main", head: "h1", tree: "t1", modes: [:], snapshot: first)
let current = try LocalStore.snapshot(root)
try LocalStore.finish(root, binding: binding, snapshot: current, paths: ["a.txt"])
let partial = try LocalStore.binding(root)
precondition(partial.snapshot.hashes["a.txt"] == current.hashes["a.txt"])
precondition(partial.snapshot.hashes["gone.txt"] == first.hashes["gone.txt"] && partial.snapshot.hashes["new.txt"] == nil)
try Data(repeating: 65, count: 11 * 1024 * 1024).write(to: root.appendingPathComponent("big.bin"))
let big = try LocalStore.snapshot(root)
precondition(big.hashes["big.bin"] != nil && big.texts["big.bin"] == nil)
var refused = false
do { _ = try LocalStore.prepare(root, paths: ["big.bin"], expected: big) } catch { refused = true }
precondition(refused)
for path in ["../escape", "/absolute", "a//b", "a\\b", "a/./b"] {
 refused = false
 do { _ = try LocalStore.prepare(root, paths: [path], expected: big) } catch { refused = true }
 precondition(refused, path)
}
try fm.createSymbolicLink(atPath: root.appendingPathComponent("link").path, withDestinationPath: "/etc/passwd")
refused = false
do { _ = try LocalStore.snapshot(root) } catch { refused = true }
precondition(refused)
try fm.removeItem(at: root.appendingPathComponent("link"))
// Exhaustive three-way presence/content matrix: absent, value A, value B.
let values: [String?] = [nil, "A", "B"]
var matrixCount = 0
for b in values { for l in values { for r in values {
 var base = LocalSnapshot(); var local = LocalSnapshot(); var remote = LocalSnapshot()
 base.hashes["file"] = b; local.hashes["file"] = l; remote.hashes["file"] = r
 let conflict = l != b && r != b && l != r
 precondition(!WorkspaceMerge.conflicts(base: base, local: local, remote: remote).isEmpty == conflict)
 if conflict {
  precondition(WorkspaceMerge.remotePaths(base: base, local: local, remote: remote, choices: ["file": false]).isEmpty)
  precondition(WorkspaceMerge.remotePaths(base: base, local: local, remote: remote, choices: ["file": true]) == ["file"])
 } else {
  precondition(WorkspaceMerge.remotePaths(base: base, local: local, remote: remote, choices: [:]).contains("file") == (l == b && (b != nil || l != nil || r != nil)))
 }
 matrixCount += 1
}}}
// Real filesystem pull: preserve edited local file while applying remote addition/deletion.
let checkout = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let downloaded = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try fm.createDirectory(at: checkout, withIntermediateDirectories: true)
try fm.createDirectory(at: downloaded, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: checkout); try? fm.removeItem(at: downloaded); try? fm.removeItem(at: LocalStore.bindingURL(checkout)) }
try Data("old".utf8).write(to: checkout.appendingPathComponent("local"))
try Data("remove".utf8).write(to: checkout.appendingPathComponent("gone"))
binding.snapshot = try LocalStore.snapshot(checkout)
try LocalStore.saveBinding(binding, folder: checkout)
try Data("edit".utf8).write(to: checkout.appendingPathComponent("local"))
try Data("old".utf8).write(to: downloaded.appendingPathComponent("local"))
try Data("new".utf8).write(to: downloaded.appendingPathComponent("added"))
var latest = binding; latest.head = "h2"; latest.snapshot = try LocalStore.snapshot(downloaded)
let local = try LocalStore.snapshot(checkout)
let pull = WorkspacePull(binding: latest, local: local, remoteFolder: downloaded, conflicts: [])
try LocalStore.applyPull(pull, folder: checkout, original: binding, choices: [:])
let merged = try LocalStore.snapshot(checkout)
precondition(merged.texts["local"] == "edit" && merged.texts["added"] == "new" && merged.hashes["gone"] == nil)
precondition(try LocalStore.binding(checkout).snapshot.hashes == latest.snapshot.hashes)
refused = false
do { try LocalStore.applyPull(pull, folder: checkout, original: binding, choices: [:]) } catch { refused = true }
precondition(refused)
print("PASS: 27 three-way matrix cases; both conflict choices; staged filesystem merge; stale apply rejection; selective baseline; SHA256; scan add/modify/delete; hidden/.git; 11MiB rejection; symlink; unsafe paths")
'''
# Swift precondition autoclosures do not throw.
tests = tests.replace('precondition(try LocalStore.binding(checkout).snapshot.hashes == latest.snapshot.hashes)', 'let saved = try LocalStore.binding(checkout)\nprecondition(saved.snapshot.hashes == latest.snapshot.hashes)')
with tempfile.TemporaryDirectory() as d:
 p = Path(d) / 'tests.swift'
 p.write_text('import Foundation\nimport CryptoKit\nstruct AppError: LocalizedError { let text: String; var errorDescription: String? { text } }\n'+core+remote+tests)
 subprocess.run(['swift', str(p)], check=True)
