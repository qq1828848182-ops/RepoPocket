"""Exercise production read API routing, optional GitHub payloads, pagination
isolation, readme bounds, encoded filters and OAuth validation without a network."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('swiftc'), 'production Swift tests run on macOS CI')
class CommunityTests(unittest.TestCase):
    def test_production_community(self):
        source = (ROOT/'RepoPocket/GitHub.swift').read_text()
        models = source[source.index('struct User: Decodable'):source.index('struct Release: Decodable')]
        oauth = (ROOT/'RepoPocket/DeviceOAuth.swift').read_text().split('final class DeviceOAuthRedirectPolicy')[0]
        program = '''import Foundation
import Combine
struct AppError: Error { let text: String }
enum RefreshFailure { static func isCancellation(_ error: Error) -> Bool { error is CancellationError } }
@MainActor final class GitHub {
 var isCurrentSession = true
 var calls: [(String, [URLQueryItem])] = []
 var payload = Data("[]".utf8)
 static func component(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: .alphanumerics)! }
 static func repoPath(_ repo: String) throws -> String { "/repos/" + (try RepositoryInput.parse(repo)) }
 func communityRead(_ path: String, query: [URLQueryItem]) async throws -> Data {
   calls.append((path, query)); return payload
 }
}
'''+models+'\n'+(ROOT/'RepoPocket/RepositoryInput.swift').read_text()+'\n'+(ROOT/'RepoPocket/DesktopModels.swift').read_text()+'\n'+(ROOT/'RepoPocket/RepositorySearchRules.swift').read_text()+'\n'+(ROOT/'RepoPocket/CommunityModels.swift').read_text()+'\n'+(ROOT/'RepoPocket/CommunityAPI.swift').read_text()+'\n'+(ROOT/'RepoPocket/CommunityPaging.swift').read_text()+'\n'+oauth+r'''
struct Row: Identifiable { let id: Int }
enum SampleError: Error { case offline }
@main struct Run {
 @MainActor static func drain(_ store: CommunityPageStore<Row>) async { while store.busy { await Task.yield() } }
 @MainActor static func main() async throws {
   let decoder = JSONDecoder()
   let api = GitHub()
   let minimal = Data(#"{"id":1,"number":2,"title":"例子","state":"open","html_url":"https://github.com/o/r/issues/2"}"#.utf8)
   let issue = try decoder.decode(CollaborationItem.self, from: minimal)
   precondition(issue.user == nil && issue.body == nil && issue.pull_request == nil)
   api.payload = Data(("[" + String(decoding:minimal,as:UTF8.self) + "]").utf8)
   let issues = try await api.collaborationItems("o/r", kind: .issues, state: "all", page: 2)
   precondition(issues.count == 1 && api.calls.last!.0 == "/repos/o/r/issues")
   precondition(api.calls.last!.1.contains { $0.name == "page" && $0.value == "2" })
   do { _ = try await api.collaborationItems("o/r", kind:.issues,state:"bad",page:1); preconditionFailure() } catch {}
   do { _ = try CommunityRules.page(11); preconditionFailure() } catch {}
   api.payload = Data("[]".utf8)
   _ = try await api.collaborationComments("o/r", number: 2, stream: .conversation, page: 1)
   precondition(api.calls.last!.0 == "/repos/o/r/issues/2/comments")
   _ = try await api.collaborationComments("o/r", number: 2, stream: .reviews, page: 1)
   precondition(api.calls.last!.0 == "/repos/o/r/pulls/2/reviews")
   _ = try await api.collaborationComments("o/r", number: 2, stream: .inline, page: 1)
   precondition(api.calls.last!.0 == "/repos/o/r/pulls/2/comments")
   _ = try await api.pullFiles("o/r", number: 2, page: 1)
   precondition(api.calls.last!.0 == "/repos/o/r/pulls/2/files")
   do { _ = try await api.pullFiles("o/r", number: -1, page:1); preconditionFailure() } catch {}
   let readme = Entry(name:"README.md",path:"docs/README.md",type:"file",sha:"abc",size:3,download_url:nil,content:Data("中文".utf8).base64EncodedString(),encoding:"base64")
   precondition(try CommunityRules.readmeText(readme) == "中文")
   let binary = Entry(name:"README.md",path:"README.md",type:"file",sha:"x",size:2,download_url:nil,content:Data([0,1]).base64EncodedString(),encoding:"base64")
   do { _ = try CommunityRules.readmeText(binary); preconditionFailure() } catch {}
   let huge = Entry(name:"README.md",path:"README.md",type:"file",sha:"x",size:999999,download_url:nil,content:"YQ==",encoding:"base64")
   do { _ = try CommunityRules.readmeText(huge); preconditionFailure() } catch {}
   for url in ["javascript:alert(1)","file:///tmp/x","http://github.com","https://user:password@github.com"] {
     precondition(CommunityRules.webURL(url) == nil)
   }
   let options = RepositorySearchOptions(language:"C++",sort:.stars,ascending:true)
   let endpoint = RepositorySearchRules.endpoint(kind:.repositories,query:"a&b 中文",page:2,options:options)
   let params = URLComponents(url:endpoint,resolvingAgainstBaseURL:false)!.queryItems!
   precondition(params.first!.value == "a&b 中文 language:\"C++\"")
   precondition(params.contains { $0.name == "order" && $0.value == "asc" })
   let userEndpoint = RepositorySearchRules.endpoint(kind:.users,query:"name",page:1,options:options)
   precondition(!userEndpoint.absoluteString.contains("language") && !userEndpoint.absoluteString.contains("sort="))
   precondition(try DeviceOAuthRules.clientID(" abc_123 ") == "abc_123")
   for invalid in ["", "a b", "bad&client", "中文"] {
     do { _ = try DeviceOAuthRules.clientID(invalid); preconditionFailure() } catch {}
   }
   let form = String(decoding:DeviceOAuthRules.form(["code":"a+b&?中文"]),as:UTF8.self)
   precondition(form.contains("%2B") && form.contains("%26") && !form.contains("中文"))
   let code = DeviceAuthorization(device_code:"private",user_code:"AB-CD",verification_uri:"https://github.com/login/device",expires_in:900,interval:5)
   precondition(try DeviceOAuthRules.validate(code).host == "github.com")
   let phish = DeviceAuthorization(device_code:"private",user_code:"AB-CD",verification_uri:"https://example.com/login/device",expires_in:900,interval:5)
   do { _ = try DeviceOAuthRules.validate(phish); preconditionFailure() } catch {}
   let store = CommunityPageStore<Row>()
   var pages: [Int] = []
   store.load(api:api) { pages.append($0); return (0..<30).map { Row(id:$0) } }
   await drain(store); precondition(store.items.count == 30 && store.more)
   store.load(api:api) { pages.append($0); throw SampleError.offline }
   await drain(store); precondition(store.items.count == 30 && !store.error.isEmpty && store.more)
   store.load(api:api) { pages.append($0); return [Row(id:29),Row(id:30),Row(id:30)] }
   await drain(store); precondition(pages == [1,2,2] && store.items.count == 31 && !store.more && store.error.isEmpty)
   var continuation: CheckedContinuation<[Row], Never>?
   store.load(reset:true,api:api) { _ in await withCheckedContinuation { continuation = $0 } }
   while continuation == nil { await Task.yield() }
   store.cancel()
   store.load(reset:true,api:api) { _ in [Row(id:99)] }
   await drain(store); continuation!.resume(returning:[Row(id:1)])
   for _ in 0..<10 { await Task.yield() }
   precondition(store.items.map { $0.id } == [99])
   store.load(reset:true,api:api) { _ in api.isCurrentSession=false; return [Row(id:100)] }
   await drain(store); precondition(store.items.isEmpty)
   api.isCurrentSession=true
   for page in 1...10 {
     store.load(reset:page==1,api:api) { p in (0..<30).map { Row(id:p*100+$0) } }
     await drain(store)
   }
   precondition(store.items.count == 300 && store.limited && !store.more)
   print("PASS production community API routing, optional payloads, README limits, filter encoding, OAuth validation, pagination retry/dedup/cancel/account isolation/bounds")
 }
}
'''
        # Throwing expressions cannot be evaluated by precondition's nonthrowing autoclosure.
        program = program.replace('precondition(try CommunityRules.readmeText(readme) == "中文")', 'let read = try CommunityRules.readmeText(readme); precondition(read == "中文")')
        program = program.replace('precondition(try DeviceOAuthRules.clientID(" abc_123 ") == "abc_123")', 'let client = try DeviceOAuthRules.clientID(" abc_123 "); precondition(client == "abc_123")')
        program = program.replace('precondition(try DeviceOAuthRules.validate(code).host == "github.com")', 'let verification = try DeviceOAuthRules.validate(code); precondition(verification.host == "github.com")')
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'main.swift'
            path.write_text(program)
            executable = str(Path(folder)/'tests')
            subprocess.run(['swiftc', '-parse-as-library', str(path), '-o', executable], check=True)
            subprocess.run([executable], check=True, timeout=30)


if __name__ == '__main__':
    unittest.main()
