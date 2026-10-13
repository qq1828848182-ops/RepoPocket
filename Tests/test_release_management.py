"""Production pure Swift fixtures run on macOS; static contracts run everywhere."""
from pathlib import Path
import shutil, subprocess, tempfile, unittest
ROOT = Path(__file__).resolve().parents[1]

class ReleaseManagementTests(unittest.TestCase):
    def test_root_lazy_navigation_and_bounded_apis(self):
        api = (ROOT/'RepoPocket/GitHub.swift').read_text()
        added = api.split('// These bounded endpoints',1)[1]
        ui = (ROOT/'RepoPocket/ReleaseManagementUI.swift').read_text()
        app = (ROOT/'RepoPocket/RepoPocketApp.swift').read_text().split('struct BrowserView:',1)[1].split('struct FileView:',1)[0]
        self.assertIn('if path.isEmpty {', app)
        self.assertEqual(app.count('ReleaseManagementDestination(api: api, repo: repo)'),1)
        load = app.split('private func load() async',1)[1].split('private func deleteRemote',1)[0]
        self.assertNotIn('managedReleases', load)
        self.assertNotIn('managedAssets', load)
        for token in ['Task.detached', 'ensureActiveAccount()', 'Task.checkCancellation()', 'perPage: Int = 20', 'ReleaseAPIRedirectPolicy()', 'current == original', 'permissions?.push', 'ReleaseManagementRules.pageLimit', 'session.upload(for: r, fromFile: file', 'checkedAll', 'ReleaseManagementRules.duplicate']:
            self.assertIn(token,added)
        self.assertNotIn('/git/refs', added)
        self.assertNotIn('upload_url', added)
        self.assertIn('perPage: 1', added)
        self.assertIn('struct Presence: Decodable { let id: Int }', added)
        self.assertIn('releasePresence.exists && api.isCurrentSession', app)
        self.assertIn('if path.isEmpty && canWrite', app)
        self.assertIn('暂无发行版', ui)
        self.assertIn('canWrite = false', ui)
        self.assertIn('复制下载链接', ui)
        self.assertIn('UIPasteboard.general.url = link', ui)
        self.assertIn('asset.browser_download_url, repo: state.repo', ui)
        for token in ['private let build: () -> AnyView', 'var body: AnyView { build() }', 'ForEach(state.rows)', 'ForEach(state.assets)', '.onDisappear { state.cancel() }', 'generation == AccountStore.generation', 'confirmation == "DELETE"', 'target.repo == state.repo', 'target.generation == AccountStore.generation', 'DownloadStore.shared.persist', 'state.saved', 'state.download(asset)', 'DisclosureGroup', 'if expanded', 'original: r', 'RefreshFailure.isCancellation', '默认草稿', '不删除 git 标签', '同名不覆盖', '已公开发行版会立即受到影响']:
            self.assertIn(token,ui)
        self.assertNotIn('AsyncImage',ui)
        transfers=(ROOT/'RepoPocket/ReleaseTransfers.swift').read_text()
        self.assertIn('ReleaseAssetRedirectPolicy()',transfers)
        self.assertIn('completionHandler(nil)',transfers)
        models=(ROOT/'RepoPocket/ReleaseManagement.swift').read_text()
        self.assertNotIn('let assets:',models)
        summary=models.split('struct ReleaseSummary:',1)[1].split('struct ReleaseForm',1)[0]
        self.assertNotIn('let body:',summary)

    def test_commit_patch_scope_and_ui(self):
        view=(ROOT/'RepoPocket/CommitPatchView.swift').read_text()
        desktop=(ROOT/'RepoPocket/DesktopViews.swift').read_text()
        self.assertIn('CommitPatchDestination(file: f)',desktop)
        self.assertNotIn('Text(f.preview)',desktop)
        for token in ['LazyVStack(alignment: .leading', '.topLeading', 'row.old', 'row.new', 'row.marker', 'Color.green.opacity(0.12)', 'Color.red.opacity(0.12)', 'whitespace = true', '原始 patch', '长行自动换行', '不是完整文件', '不代表没有改动', 'Task.detached', 'withTaskCancellationHandler', 'worker.cancel()', 'try Task.checkCancellation()']:
            self.assertIn(token,view)
        self.assertNotIn('api.',view)
        self.assertNotIn('before',view)
        self.assertNotIn('after',view)

    @unittest.skipUnless(shutil.which('swiftc'), 'production Swift executes in macOS CI; no local Swift compiler')
    def test_production_models_parser_budget_and_cancellation(self):
        source=(ROOT/'RepoPocket/ReleaseManagement.swift').read_text()+(ROOT/'RepoPocket/CommitPatch.swift').read_text()+r'''
struct AppError: LocalizedError { let text: String; var errorDescription: String? { text } }
struct Item: Identifiable { let id: Int }
@main struct Run {
 static func main() async throws {
  precondition(!ReleaseManagementRules.canWrite(nil, session:true))
  precondition(!ReleaseManagementRules.canWrite(false, session:true))
  precondition(!ReleaseManagementRules.canWrite(true, session:false))
  precondition(ReleaseManagementRules.canWrite(true, session:true))
  precondition(!ReleaseManagementRules.validPage(0) && !ReleaseManagementRules.validPage(51))
  precondition(ReleaseManagementRules.more(count:20,page:1))
  precondition(!ReleaseManagementRules.more(count:19,page:1) && !ReleaseManagementRules.more(count:20,page:50))
  let merged=ReleaseManagementRules.merged([Item(id:1)], [Item(id:1),Item(id:2),Item(id:2)])
  precondition(merged.map(\.id) == [1,2])
  let large = (0..<10_000).map { Item(id:$0) }
  let deduped = ReleaseManagementRules.merged(large, large)
  precondition(deduped.count == 10_000)
  do { _ = try JSONDecoder().decode(ReleaseSummary.self,from:Data("{broken".utf8)); preconditionFailure("invalid JSON accepted") } catch {}
  precondition(!ReleaseManagementRules.validAsset(size:ReleaseManagementRules.assetLimit,name:"a"))
  precondition(ReleaseManagementRules.validAsset(size:ReleaseManagementRules.assetLimit-1,name:"中文😀.zip"))
  for name in ["", "..", ".", "a/b", "a\\b", "a\nb"] { precondition(!ReleaseManagementRules.validAsset(size:1,name:name)) }
  precondition(ReleaseManagementRules.duplicate(name:"test.zip",names:["test.zip"]))
  precondition(!ReleaseManagementRules.duplicate(name:"new.zip",names:["test.zip"]))
  let link="https://github.com/o/r/releases/download/v1/test.zip"
  precondition(ReleaseManagementRules.browserDownloadURL(link,repo:"o/r") != nil)
  for bad in ["https://evil.com/o/r/releases/download/v1/a", "https://api.github.com/repos/o/r/releases/assets/1", "https://github.com/x/r/releases/download/v1/a", link+"?token=secret", "http://github.com/o/r/releases/download/v1/a", "https://token@github.com/o/r/releases/download/v1/a", link+"#fragment"] { precondition(ReleaseManagementRules.browserDownloadURL(bad,repo:"o/r") == nil) }
  let huge=String(repeating:"中文😀", count:20_000)
  precondition(!ReleaseManagementRules.editable(huge))
  precondition(ReleaseManagementRules.displayBody(huge).count == ReleaseManagementRules.displayBodyLimit)
  let json = #"{"id":7,"tag_name":"v1","name":"Title","draft":true,"prerelease":false,"created_at":"2026-10-13","updated_at":"now","body":"完整正文","assets":[{"unknown":"ignored"}]}"#
  let summary = try JSONDecoder().decode(ReleaseSummary.self, from: Data(json.utf8))
  let detail = try JSONDecoder().decode(ManagedRelease.self, from: Data(json.utf8))
  precondition(summary.id==7 && detail.body=="完整正文" && detail.draft)
  precondition(ReleaseForm(detail).body==detail.body)
  let patch = "@@ -10,2 +20,2 @@ func\n-old😀\n+新中文\n context\n\\ No newline at end of file"
  let parsed=try CommitPatchParser.parse(patch)
  precondition(parsed.rows.count==5 && !parsed.malformed)
  precondition(parsed.rows[1].old==10 && parsed.rows[1].new==nil)
  precondition(parsed.rows[2].old==nil && parsed.rows[2].new==20)
  precondition(parsed.rows[3].old==11 && parsed.rows[3].new==21)
  precondition(parsed.rows[4].text=="文件末尾没有换行")
  precondition(parsed.rows[0].text.contains("区块") && !parsed.rows[0].text.contains("@@"))
  let insertion=try CommitPatchParser.parse("@@ -0,0 +1,1 @@\n+你好😀")
  precondition(insertion.rows[1].new==1 && !insertion.malformed)
  let malformed=try CommitPatchParser.parse("@@ broken\n+something")
  precondition(malformed.malformed && malformed.rows[1].old==nil)
  let incomplete=try CommitPatchParser.parse("@@ -1,2 +1,2 @@\n context")
  precondition(incomplete.malformed)
  let enormous=try CommitPatchParser.parse("@@ -0,0 +1,1 @@\n+"+String(repeating:"😀",count:300_000))
  precondition(enormous.limited && enormous.rows.count<=CommitPatchParser.rowLimit)
  precondition(enormous.rows[1].text.count<=CommitPatchParser.lineLimit)
  precondition(CommitPatchParser.visible("a b\tc",whitespace:true).contains("·"))
  precondition(CommitPatchParser.visible("a b\tc",whitespace:false)=="a b\tc")
  let t=Task { try await Task.sleep(nanoseconds: 5_000_000_000); return try CommitPatchParser.parse(patch) }
  t.cancel()
  do { _ = try await t.value; preconditionFailure("cancel must not succeed") } catch is CancellationError {} catch { preconditionFailure("wrong cancellation") }
  print("PASS production release budgets, permissions, page dedup, duplicate naming, full body and commit patch numbering/unicode/malformed/budget/cancellation")
 }
}
'''
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'main.swift'; p.write_text(source)
            subprocess.run(['swiftc','-parse-as-library',str(p),'-o',d+'/tests'],check=True)
            subprocess.run([d+'/tests'],check=True)

if __name__=='__main__': unittest.main()
