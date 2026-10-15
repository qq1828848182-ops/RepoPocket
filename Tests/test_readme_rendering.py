"""README production decoding/transport regression; fixtures never contact GitHub."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ReadmeRenderingTests(unittest.TestCase):
    def test_web_content_has_no_authenticated_session_and_only_isolated_height_messages(self):
        view = (ROOT / 'RepoPocket/ReadmeHTMLView.swift').read_text()
        self.assertIn('websiteDataStore = .nonPersistent()', view)
        self.assertIn('allowsContentJavaScript = false', view)
        self.assertNotIn('Authorization', view)
        self.assertIn('contentWorld: .defaultClient', view)
        self.assertIn('message.frameInfo.isMainFrame', view)
        self.assertIn('message.body as? NSNumber', view)
        self.assertIn('removeScriptMessageHandler', view)
        self.assertNotIn('change.newValue', view)
        self.assertIn('ReadingLinkDestination(url:', view)
        self.assertIn('CommunityRules.webURL(url.absoluteString)', view)

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift regression runs on macOS')
    def test_production_readme_formats_and_html_transport(self):
        api = (ROOT / 'RepoPocket/GitHub.swift').read_text()
        models = api[api.index('struct User: Decodable'):api.index('struct Release: Decodable')]
        gateway = api[api.index('    func communityReadmeHTML('):api.index('    // Native collaboration transport')]
        source = r'''
import Foundation
struct AppError: LocalizedError { let text:String; var errorDescription:String? {text} }
enum RefreshFailure { static func isCancellation(_ error:Error)->Bool { error is CancellationError } }
final class Fixture: URLProtocol {
 static let lock=NSLock(); static var seen:[URLRequest]=[]; static var status=200
 static var payload=Data("<h1>README</h1><img alt='version' src='https://img.shields.io/badge/version-1-blue.svg'>".utf8)
 override class func canInit(with request:URLRequest)->Bool {true}
 override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
 override func startLoading() {
   Self.lock.lock(); Self.seen.append(request); let status=Self.status;let bytes=Self.payload;Self.lock.unlock()
   client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
   client?.urlProtocol(self,didLoad:bytes);client?.urlProtocolDidFinishLoading(self)
 }
 override func stopLoading() {}
 static func count()->Int {lock.lock();defer{lock.unlock()};return seen.count}
}
@MainActor final class GitHub {
 let session:URLSession
 var active=true
 var entry=Entry(name:"README.rst",path:"README.rst",type:"file",sha:"x",size:7,download_url:nil,content:Data("Title\n=".utf8).base64EncodedString(),encoding:"base64")
 init(){let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[Fixture.self];session=URLSession(configuration:config)}
 var isCurrentSession:Bool {active}
 func ensureActiveAccount() throws {guard active else {throw CancellationError()}}
 static func repoPath(_ repo:String)throws->String {"/repos/" + (try RepositoryInput.parse(repo))}
 func url(_ path:String,query:[URLQueryItem]=[])throws->URL {
   var u=URLComponents(string:"https://api.github.com"+path)!;u.queryItems=query;return u.url!
 }
 func request(_ url:URL)throws->URLRequest {try ensureActiveAccount();var r=URLRequest(url:url);r.setValue("Bearer fixture-only",forHTTPHeaderField:"Authorization");return r}
 func check(_ data:Data,_ response:URLResponse)throws {try ensureActiveAccount();guard let h=response as? HTTPURLResponse,(200..<300).contains(h.statusCode) else {throw AppError(text:"denied")}}
 func repositoryReadme(_ repo:String,branch:String)async throws->Entry {try ensureActiveAccount();try Task.checkCancellation();return entry}
GATEWAY
}
'''.replace('GATEWAY', gateway)
        source += '\n' + models
        for name in ['RepositoryInput.swift', 'OfficialUpdateRedirectPolicy.swift', 'ReadmeDocument.swift']:
            source += '\n' + (ROOT / 'RepoPocket' / name).read_text()
        source += r'''
@main struct Run {
 @MainActor static func main()async throws {
   func entry(_ name:String,_ bytes:Data,size:Int?=nil,encoding:String="base64")->Entry {
     Entry(name:name,path:name,type:"file",sha:"x",size:size ?? bytes.count,download_url:nil,content:bytes.base64EncodedString(),encoding:encoding)
   }
   for name in ["README.md","README.rst","README.adoc","README.txt","README.html","README"] {
     let value=try ReadmeDocumentRules.source(entry(name,Data("Hello 世界".utf8)));precondition(value=="Hello 世界")
   }
   let utf16=Data([0xff,0xfe])+"中文".data(using:.utf16LittleEndian)!
   let value16=try ReadmeDocumentRules.source(entry("README.txt",utf16));precondition(value16=="中文")
   let utf32=Data([0,0,0xfe,0xff])+"中文".data(using:.utf32BigEndian)!
   let value32=try ReadmeDocumentRules.source(entry("README",utf32));precondition(value32=="中文")
   for bad in [entry("README",Data([0,1,2])),entry("README",Data([0xff])),entry("README",Data(),size:1048577),entry("README",Data([65]),encoding:"none")] {
     do {_ = try ReadmeDocumentRules.source(bad);preconditionFailure()}catch{}
   }
   for bytes in [Data([0]),Data([0xff]),Data(repeating:65,count:2097153)] {
     do {_ = try ReadmeDocumentRules.renderedHTML(bytes);preconditionFailure()}catch{}
   }
   let fragment="<img src='data:image/svg+xml;base64,PHN2Zy8+'><details><summary>更多</summary>正文</details>"
   let document=ReadmeDocumentRules.document(fragment)
   precondition(document.contains(fragment) && document.contains("script-src 'none'") && document.contains("img-src https: data:"))
   precondition(document.contains("display: flow-root") && document.contains("<main id=\"repopocket-readme\">"))
   precondition(ReadmeDocumentRules.heightObserver.contains("getBoundingClientRect().height") && !ReadmeDocumentRules.heightObserver.contains("scrollHeight"))
   let base=URL(string:"https://github.com/owner/repo/blob/main/README.rst")!
   precondition(ReadmeDocumentRules.isLocalAnchor(URL(string:base.absoluteString+"#title")!,base:base))
   precondition(!ReadmeDocumentRules.isLocalAnchor(URL(string:"https://example.com/#title")!,base:base))
   let api=GitHub();defer{api.session.invalidateAndCancel()}
   let loaded=try await api.repositoryReadmeDocument("owner/repo",branch:"feature/#x")
   precondition(loaded.entry.name=="README.rst" && loaded.source=="Title\n=" && loaded.html!.contains("shields.io"))
   Fixture.lock.lock();let request=Fixture.seen.last!;Fixture.lock.unlock()
   precondition(request.httpMethod=="GET" && request.url!.host=="api.github.com" && request.url!.path=="/repos/owner/repo/readme")
   precondition(request.value(forHTTPHeaderField:"Accept")=="application/vnd.github.html+json")
   precondition(request.value(forHTTPHeaderField:"Authorization")=="Bearer fixture-only")
   precondition(URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!.first!.value=="feature/#x")
   Fixture.status=403
   let fallback=try await api.repositoryReadmeDocument("owner/repo",branch:"main")
   precondition(fallback.html==nil && fallback.source=="Title\n=")
   api.entry=entry("README",Data([0,1,2]))
   do {_ = try await api.repositoryReadmeDocument("owner/repo",branch:"main");preconditionFailure()}catch{}
   api.entry=entry("README",Data(),size:1048577);let beforeLarge=Fixture.count()
   do {_ = try await api.repositoryReadmeDocument("owner/repo",branch:"main");preconditionFailure()}catch{}
   precondition(Fixture.count()==beforeLarge)
   api.active=false;let beforeInactive=Fixture.count()
   do {_ = try await api.communityReadmeHTML("owner/repo",branch:"main");preconditionFailure()}catch{}
   precondition(Fixture.count()==beforeInactive)
   api.active=true
   let cancelled=Task { @MainActor in
     withUnsafeCurrentTask {$0?.cancel()}
     do {_ = try await api.communityReadmeHTML("owner/repo",branch:"main");preconditionFailure()}catch{}
   }
   await cancelled.value;precondition(Fixture.count()==beforeInactive)
   print("PASS production README: no extension filter, UTF text decoding, binary/size rejection, HTML GET/ref/Accept, text fallback, inactive and cancelled requests blocked. No live requests.")
 }
}
'''
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'main.swift'
            path.write_text(source)
            executable = str(Path(folder) / 'test')
            subprocess.run(['swiftc', '-parse-as-library', str(path), '-o', executable], check=True)
            subprocess.run([executable], check=True, timeout=30)


if __name__ == '__main__':
    unittest.main()
