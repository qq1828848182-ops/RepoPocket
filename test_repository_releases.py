"""Execute production release models/state with offline mocks on the Apple CI runner."""
from pathlib import Path
import shutil, subprocess, tempfile, unittest
R = Path(__file__).parent
API = (R/'RepoPocket/GitHub.swift').read_text()
STATE = (R/'RepoPocket/RepositoryReleases.swift').read_text()
UI = (R/'RepoPocket/RepositoryReleaseUI.swift').read_text()

class ReleasesTests(unittest.TestCase):
    def test_integration_security_and_version(self):
        app=(R/'RepoPocket/RepoPocketApp.swift').read_text()
        self.assertLess(app.index('RepositoryReleaseSection(api:'), app.index('if busy && entries.isEmpty'))
        self.assertIn('if path.isEmpty { RepositoryReleaseSection',app)
        self.assertIn('.task(id: repo)',app)
        self.assertIn('releases.reset()',app)
        self.assertIn('if let recent = state.recent', UI)
        self.assertIn('ForEach(release.assets)', UI)
        self.assertIn('ShareSheet(url:',UI)
        self.assertIn('download.cancel()',UI)
        self.assertIn('download.reset()',UI)
        self.assertIn('Text(verbatim: noteChunks[index])',UI)
        self.assertNotIn('ISO8601DateFormatter()', UI)
        self.assertIn('decodePage(bytes)',API)
        self.assertNotIn('while true',STATE)
        self.assertIn('state.cancelPage()',UI)
        self.assertNotIn('Link(',UI)
        latest=API.split('func repositoryLatestRelease(',1)[1].split('func downloadReleaseAsset(',1)[0]
        self.assertIn('"/releases/latest"',latest)
        self.assertIn('_ = try await repository(repo)',latest)
        self.assertIn('error.status == 404',latest)
        page=API.split('func repositoryReleasePage(',1)[1].split('func repositoryLatestRelease(',1)[0]
        self.assertIn('rel=\\"next\\"',page)
        self.assertIn('String(page)',page)
        asset=API.split('func downloadReleaseAsset(',1)[1].split('func downloadAsset(',1)[0]
        self.assertIn('"/releases/assets/"',asset)
        self.assertIn('application/octet-stream',asset)
        self.assertIn('return try await download(r,',asset)
        self.assertNotIn('URL(string: asset.browser_download_url)',asset)
        self.assertIn('DownloadStore.shared.persist(temporary, session: generation)',STATE)
        self.assertIn('DownloadStore.shared.requireAuthorization()',STATE)
        self.assertIn('temporary.deletingLastPathComponent()',STATE)
        self.assertIn('CURRENT_PROJECT_VERSION: "18"',(R/'project.yml').read_text())

    @unittest.skipUnless(shutil.which('swiftc'), 'Production Swift tests execute on macOS CI')
    def test_production_decoding_state_cancel_identity_and_redirects(self):
        models=API[API.index('struct Release:'):API.index('struct GitHubMessage:')]
        policy=(R/'RepoPocket/ReleaseAssetRedirectPolicy.swift').read_text()
        state=STATE.replace('import Combine','')
        harness=r'''
import Foundation
protocol ObservableObject {}
@propertyWrapper struct Published<T> { var wrappedValue: T }
struct AppError: LocalizedError { let text: String; var errorDescription: String? { text } }
enum AccountStore { static var generation = UUID() }
@MainActor final class DownloadStore {
 static let shared = DownloadStore()
 var label = "mock/RepoPocket", operations = 0, persisted = 0, allowed = true
 func requireAuthorization() async throws { if !allowed { throw CancellationError() } }
 func begin() { operations += 1 }
 func end() { operations -= 1 }
 func persist(_ file: URL, session: UUID) throws -> URL {
  precondition(session == AccountStore.generation && !Task.isCancelled)
  persisted += 1; return file
 }
}
@MainActor final class GitHub {
 var isCurrentSession = true
 var pages: [ReleasePage] = []
 var latest: Release?
 var failed = false, slow = false, switchDuring = false, slowDownload = false
 var slowLatest = false
 var calls: [Int] = [], downloadTargets: [String] = []
 func repositoryLatestRelease(_ repo: String) async throws -> Release? {
  while slowLatest { try await Task.sleep(nanoseconds: 1_000_000) }
  if failed { throw AppError(text: "403") }; return latest
 }
 func repositoryReleasePage(_ repo: String, page: Int) async throws -> ReleasePage {
  calls.append(page)
  if slow { try await Task.sleep(nanoseconds: 50_000_000) }
  if switchDuring { AccountStore.generation = UUID(); isCurrentSession = false }
  if failed { throw AppError(text: "403") }
  return pages[page-1]
 }
 func downloadReleaseAsset(_ repo: String, asset: Asset, progress: @escaping (Double)->Void) async throws -> URL {
  downloadTargets.append(repo + ":" + String(asset.id)); progress(0.5)
  while slowDownload { try await Task.sleep(nanoseconds: 1_000_000) }
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let file=folder.appendingPathComponent(asset.name)
  try Data("mock".utf8).write(to: file); return file
 }
}
func JSONEncoderFixture(_ release: Release) throws -> Data {
 try JSONSerialization.data(withJSONObject:["id":release.id,"tag_name":release.tag_name,"draft":false,"upload_url":"u","html_url":"h","assets":[],"published_at":release.published_at!])
}
func release(_ id: Int, draft: Bool = false, pre: Bool = false, date: String? = "2026-10-12T10:00:00Z") throws -> Release {
 let object: [String:Any] = ["id":id,"tag_name":"v\(id)","name":"Version \(id)","draft":draft,"prerelease":pre,"published_at":date as Any? ?? NSNull(),"body":"Full\nnotes **raw**", "upload_url":"https://uploads.github.com/repos/o/r/releases/\(id)/assets{?name}","html_url":"https://github.com/o/r/releases/tag/v\(id)","assets":[["id":id,"name":"file\(id).ipa","size":4,"browser_download_url":"https://evil.invalid/steal"]]]
 return try JSONDecoder().decode(Release.self, from: JSONSerialization.data(withJSONObject: object))
}
@MainActor func waitUntil(_ condition: @MainActor () -> Bool) async throws {
 for _ in 0..<2000 {
  if condition() { return }
  try await Task.sleep(nanoseconds:1_000_000)
 }
 preconditionFailure("Mock state did not complete within bounded wait")
}
@main struct Tests {
 @MainActor static func main() async throws {
  let official=try release(1, date:"2026-10-01T10:00:00Z"), preview=try release(2, pre:true), draft=try release(3,draft:true), unpublished=try release(4,date:nil)
  precondition(official.body == "Full\nnotes **raw**" && official.assets[0].size == 4)
  let legacy=try JSONDecoder().decode(Release.self,from:Data(#"{"id":8,"tag_name":"v8","draft":false,"upload_url":"u","html_url":"h","assets":[]}"#.utf8))
  precondition(legacy.prerelease == nil && legacy.body == nil && legacy.published_at == nil)
  precondition(RepositoryReleaseRules.published([official,preview,draft,unpublished]).count == 2)
  precondition(RepositoryReleaseRules.newest([official,preview,draft])?.id == 2)
  precondition(RepositoryReleaseRules.isLatest(official,latestID:1))
  precondition(!RepositoryReleaseRules.isLatest(preview,latestID:2))
  let api=GitHub(), state=RepositoryReleaseState()
  api.pages=[ReleasePage(values:[official,draft],hasNext:true),ReleasePage(values:[official,preview,unpublished],hasNext:false)]
  api.latest=official
  api.slowLatest=true
  await state.load(api:api,repo:"o/r")
  precondition(state.count == nil && state.recent?.id == 1 && state.latestID == nil && api.calls == [1])
  precondition(state.history.map(\.id) == [1])
  for _ in 0..<200 { await state.load(api:api,repo:"o/r") }
  precondition(api.calls == [1])
  api.slowLatest=false
  try await waitUntil { state.latestID == 1 }
  api.slow=true
  for _ in 0..<200 { state.more(api:api,repo:"o/r") }
  try await waitUntil { !state.paging }
  precondition(api.calls == [1,2] && state.history.map(\.id) == [1,2] && state.count == 2 && !state.hasNext)
  api.slow=false
  api.latest=nil; api.pages=[ReleasePage(values:[],hasNext:false)]
  await state.load(api:api,repo:"o/tags-only")
  precondition(state.count == 0 && state.error == nil && state.recent == nil && state.latestID == nil)
  api.failed=true; await state.load(api:api,repo:"o/private")
  precondition(state.count == nil && state.error != nil)
  api.failed=false; api.pages=[ReleasePage(values:[preview],hasNext:false)]
  await state.load(api:api,repo:"o/private",retry:true)
  precondition(state.count == 1 && state.latestID == nil && state.recent?.prerelease == true)
  api.slow=true
  let old=Task { await state.load(api:api,repo:"o/old") }
  try await Task.sleep(nanoseconds:5_000_000)
  await state.load(api:api,repo:"o/new")
  await old.value; precondition(state.count == 1 && state.error == nil)
  api.switchDuring=true; await state.load(api:api,repo:"o/stale")
  precondition(state.count == nil && state.recent == nil)
  api.switchDuring=false; api.isCurrentSession=true; api.slow=false
  // 1000 available pages never trigger summary enumeration or automatic history preload.
  api.pages=Array(repeating:ReleasePage(values:[official],hasNext:true),count:1000)
  api.calls=[]; await state.load(api:api,repo:"o/huge")
  precondition(api.calls == [1] && state.count == nil)
  for _ in 0..<100 { await state.load(api:api,repo:"o/huge") }
  precondition(api.calls == [1])
  api.slow=true
  state.more(api:api,repo:"o/huge")
  try await waitUntil { api.calls.count == 2 }
  state.cancelPage()
  try await Task.sleep(nanoseconds:60_000_000)
  precondition(state.history.count == 1 && !state.paging)
  state.more(api:api,repo:"o/huge")
  try await waitUntil { !state.paging }
  precondition(api.calls == [1,2,2] && state.history.count == 1)
  api.failed=true; state.more(api:api,repo:"o/huge")
  try await waitUntil { !state.paging }
  let requests=api.calls.count
  for _ in 0..<100 { state.more(api:api,repo:"o/huge") }
  precondition(api.calls.count == requests && state.historyError != nil)
  api.failed=false; state.more(api:api,repo:"o/huge",retry:true)
  try await waitUntil { !state.paging }
  precondition(state.historyError == nil && state.history.count == 1)
  let cancelled=Task { await state.load(api:api,repo:"o/cancel") }
  try await Task.sleep(nanoseconds:5_000_000); cancelled.cancel(); await cancelled.value
  precondition(!state.loading && state.history.isEmpty)
  let processor=RepositoryReleaseProcessing.shared
  let prepared=try await processor.decodeLatest(try JSONEncoderFixture(official))
  precondition(prepared.displayDate != nil)
  let longNotes=String(repeating:"汉🙂**raw**\n",count:20000)
  let chunks=try await processor.notes(longNotes)
  precondition(chunks.joined() == longNotes && chunks.allSatisfy { $0.count <= 2048 })
  api.slow=false
  let downloader=RepositoryAssetDownload(), store=DownloadStore.shared
  api.slowDownload=true
  downloader.start(api:api,repo:"o/old",asset:official.assets[0])
  try await waitUntil { api.downloadTargets.count == 1 }; downloader.cancel()
  try await waitUntil { store.operations == 0 }
  precondition(store.persisted == 0 && store.operations == 0 && downloader.saved == nil)
  downloader.start(api:api,repo:"o/stale",asset:preview.assets[0])
  try await waitUntil { api.downloadTargets.count == 2 }; AccountStore.generation=UUID()
  api.slowDownload=false
  try await waitUntil { downloader.activeID == nil && store.operations == 0 }
  precondition(store.persisted == 0 && downloader.saved == nil && store.operations == 0)
  downloader.start(api:api,repo:"o/new",asset:preview.assets[0])
  try await waitUntil { downloader.activeID == nil }
  precondition(store.persisted == 1 && downloader.saved != nil && store.operations == 0)
  precondition(api.downloadTargets.last == "o/new:2")
  store.allowed=false; downloader.start(api:api,repo:"o/new",asset:official.assets[0])
  try await Task.sleep(nanoseconds:10_000_000)
  precondition(store.persisted == 1 && downloader.activeID == nil)
  let policy=ReleaseAssetRedirectPolicy(), session=URLSession(configuration:.ephemeral), task=session.dataTask(with:URL(string:"https://api.github.com")!)
  let response=HTTPURLResponse(url:URL(string:"https://api.github.com")!,statusCode:302,httpVersion:nil,headerFields:nil)!
  for host in ["api.github.com","github.com","release-assets.githubusercontent.com","objects.githubusercontent.com"] {
   var req=URLRequest(url:URL(string:"https://\(host)/asset")!); req.setValue("secret",forHTTPHeaderField:"Authorization"); req.setValue("secret",forHTTPHeaderField:"Cookie")
   var redirected:URLRequest?
   policy.urlSession(session,task:task,willPerformHTTPRedirection:response,newRequest:req) { redirected=$0 }
   precondition(redirected != nil && redirected?.value(forHTTPHeaderField:"Authorization") == nil && redirected?.value(forHTTPHeaderField:"Cookie") == nil)
  }
  for address in ["http://github.com/a","https://github.com.evil.invalid/a","https://evil.invalid/a","https://user:pass@github.com/a","https://github.com:8443/a"] {
   var accepted=true
   policy.urlSession(session,task:task,willPerformHTTPRedirection:response,newRequest:URLRequest(url:URL(string:address)!)) { accepted = $0 != nil }
   precondition(!accepted)
  }
  session.invalidateAndCancel()
  print("PASS production releases: decoding, multi-page draft exclusion, latest/preview, zero/errors, retry, old identity, session changes, cancel, shared guards, hostile URLs and token stripping")
 }
}
'''
        with tempfile.TemporaryDirectory() as folder:
            src=Path(folder)/'Tests.swift'; src.write_text(models+'\n'+policy+'\n'+state+'\n'+harness)
            exe=str(Path(folder)/'tests')
            subprocess.run(['swiftc','-parse-as-library',str(src),'-o',exe],check=True)
            subprocess.run([exe],check=True)

if __name__=='__main__': unittest.main()
