from pathlib import Path
import unittest, shutil, tempfile, subprocess
ROOT = Path(__file__).resolve().parents[1]
class ForkStatusTests(unittest.TestCase):
    def test_existing_fork_state_is_discovered_and_shared(self):
        api = (ROOT/'RepoPocket/GitHub.swift').read_text()
        menu = (ROOT/'RepoPocket/RepositoryForkMenu.swift').read_text()
        self.assertIn('func existingFork(', api)
        self.assertIn('affiliations: [OWNER]', api)
        self.assertIn('let source: RepositoryReference?', api)
        self.assertIn('RepositoryForkRules.matches', api)
        self.assertIn('networkCount == directCount', api)
        self.assertIn('Date().timeIntervalSince(date) < 300', api)
        self.assertNotIn('return try await pending.value', api)
        self.assertIn('复刻或定位已有复刻', menu)
        self.assertIn('forkNames[', menu)
        self.assertIn('已复刻', menu)
        self.assertIn('.task(id: name + "\\n" + String(refreshID))', menu)
        self.assertIn('await state.check(name, api: api)', menu)
        self.assertNotIn('scenePhase', menu)
    @unittest.skipUnless(shutil.which('swiftc'), 'Production fork lookup mocks run on macOS CI')
    def test_production_lookup_network_free(self):
        api = (ROOT/'RepoPocket/GitHub.swift').read_text()
        methods = '    func existingFork(' + api.split('    func existingFork(',1)[1].split('    func createRepository(',1)[0]
        rules = (ROOT/'RepoPocket/RepositoryForkMenu.swift').read_text().split('struct RepositoryForkTarget:',1)[0].replace('import SwiftUI','import Foundation')
        source = r'''
import Foundation
struct AppError: LocalizedError { let text: String; var errorDescription: String? { text } }
struct GitHubAPIError: Error { let status: Int }
enum RepositoryHomeSection { case owned }
struct RepositoryReference: Decodable { let full_name: String }
struct Repository: Decodable {
 let full_name: String
 var fork: Bool?
 var parent: RepositoryReference?
 var source: RepositoryReference?
}
@MainActor final class GitHub {
 var login = "me", current = true
 var forkNames: [String: String] = [:]
 var forkChecks: [String: Task<String?, Error>] = [:]
 var forkCheckIDs: [String: UUID] = [:]
 var forkCheckedAt: [String: Date] = [:]
 var collectionCache: [RepositoryHomeSection: [Repository]] = [:]
 var fixtures: [String: Repository] = [:], reads: [String] = []
 var graphCalls = 0, posts = 0, switchOnRead = false
 var holdReads = false
 var readGate: CheckedContinuation<Void, Never>?
 var graph = #"{"data":{"root":{"forkCount":0,"direct":{"totalCount":0},"forks":{"nodes":[]}},"target":{"forks":{"nodes":[]}}}}"#
 func requireStarSession() throws { try ensureActiveAccount() }
 func ensureActiveAccount() throws { if !current { throw AppError(text: "stale") } }
 func identify() async throws { try ensureActiveAccount() }
 static func repoPath(_ name: String) throws -> String { "/repos/" + (try RepositoryInput.parse(name)) }
 func repository(_ name: String) async throws -> Repository {
  reads.append(name)
  if holdReads { await withCheckedContinuation { readGate = $0 } } else { await Task.yield() }
  if switchOnRead { current = false }
  try ensureActiveAccount()
  guard let result = fixtures[name.lowercased()] else { throw GitHubAPIError(status: 404) }
  return result
 }
 func decoded<T: Decodable>(_ type: T.Type, _ path: String, method: String, object: [String: Any]) async throws -> T {
  try ensureActiveAccount()
  if path == "/graphql" { graphCalls += 1; return try JSONDecoder().decode(type, from: Data(graph.utf8)) }
  precondition(path == "/repos/up/tool/forks" && method == "POST")
  posts += 1
  return try JSONDecoder().decode(type, from: Data(#"{"full_name":"me/tool","fork":true}"#.utf8))
 }
''' + methods + "}\n"
        source += (ROOT/'RepoPocket/RepositoryInput.swift').read_text()
        source += (ROOT/'RepoPocket/RepositorySafetyRules.swift').read_text().split('enum UpdateNoticeRules')[0]
        source += rules + r'''
@main struct Harness {
 @MainActor static func main() async throws {
  let upstream = Repository(full_name: "up/tool")
  let fork = Repository(full_name: "me/tool", fork: true, parent: RepositoryReference(full_name: "up/tool"))
  let api = GitHub()
  api.fixtures = ["up/tool": upstream, "me/tool": fork]
  let found = try await api.existingFork("UP/tool")
  precondition(found == "me/tool" && api.posts == 0 && api.graphCalls == 0)
  let reads = api.reads.count
  _ = try await api.existingFork("up/TOOL")
  precondition(api.reads.count == reads)
  api.collectionCache[.owned] = [fork]
  api.forkCheckedAt["up/tool"] = Date().addingTimeInterval(-301)
  let refreshedPositive = try await api.existingFork("up/tool")
  precondition(refreshedPositive == "me/tool" && api.reads.count > reads)
  // Cancelling the first waiter cannot stop a second waiter publishing shared state.
  let shared = GitHub(); shared.fixtures = ["up/tool": upstream, "me/tool": fork]
  shared.holdReads = true
  let firstWaiter = Task { try await shared.existingFork("up/tool") }
  while shared.readGate == nil { await Task.yield() }
  var secondStarted = false
  let secondWaiter = Task { secondStarted = true; return try await shared.existingFork("up/tool") }
  while !secondStarted { await Task.yield() }
  firstWaiter.cancel()
  shared.holdReads = false
  shared.readGate?.resume(); shared.readGate = nil
  _ = try? await firstWaiter.value
  let sharedResult = try await secondWaiter.value
  precondition(sharedResult == "me/tool" && shared.forkNames["up/tool"] == "me/tool")
  // A same-named unrelated repository must not be claimed as a fork.
  let other = GitHub()
  other.fixtures = ["up/tool": upstream, "me/tool": Repository(full_name: "me/tool")]
  precondition(try await other.existingFork("up/tool") == nil)
  precondition(other.forkNames.isEmpty && other.graphCalls == 1)
  // Renamed fork discovery survives a fresh API/session object.
  let renamed = GitHub()
  renamed.fixtures = ["up/tool": upstream, "me/renamed": Repository(full_name: "me/renamed", fork: true, source: RepositoryReference(full_name: "up/tool"))]
  renamed.graph = #"{"data":{"root":{"forks":{"nodes":[{"nameWithOwner":"me/renamed"}]}},"target":{"forks":{"nodes":[]}}}}"#
  precondition(try await renamed.existingFork("up/tool") == "me/renamed")
  precondition(renamed.graphCalls == 1 && renamed.posts == 0)
  // A GraphQL HTTP-200 permission/error payload stays unknown, without negative cache.
  let denied = GitHub(); denied.fixtures = ["up/tool": upstream]
  denied.graph = #"{"data":null,"errors":[{"message":"Resource not accessible"}]}"#
  do { _ = try await denied.existingFork("up/tool"); fatalError("silently accepted lookup error") } catch {}
  precondition(denied.forkNames.isEmpty && denied.forkCheckedAt.isEmpty && denied.posts == 0)
  // Direct-forks filtering cannot rule out my renamed second-generation fork.
  // A/root -> B/tool -> me/renamed: no direct owner hit is an unknown result.
  let indirect = GitHub(); indirect.fixtures = ["up/tool": upstream]
  indirect.graph = #"{"data":{"root":{"forkCount":2,"direct":{"totalCount":1},"forks":{"nodes":[]}},"target":{"forks":{"nodes":[]}}}}"#
  do { _ = try await indirect.existingFork("up/tool"); fatalError("accepted incomplete network as no fork") } catch {}
  precondition(indirect.forkNames.isEmpty && indirect.forkCheckedAt.isEmpty && indirect.graphCalls == 1 && indirect.posts == 0)
  // Only validated ownership plus parent/source metadata can seed renamed matches.
  let cached = GitHub(); cached.fixtures = ["up/tool": upstream]
  cached.collectionCache[.owned] = [Repository(full_name: "me/renamed", fork: true, parent: RepositoryReference(full_name: "UP/TOOL"))]
  precondition(try await cached.existingFork("up/tool") == "me/renamed")
  precondition(cached.reads.count == 1 && cached.graphCalls == 0)
  precondition(!RepositoryForkRules.matches(Repository(full_name: "other/tool", fork: true, parent: RepositoryReference(full_name: "up/tool")), upstream: upstream, login: "me"))
  // Account switch during the network await must publish nothing.
  let stale = GitHub(); stale.fixtures = ["up/tool": upstream]; stale.switchOnRead = true
  do { _ = try await stale.existingFork("up/tool"); fatalError("accepted stale session") } catch {}
  precondition(stale.forkNames.isEmpty && stale.forkCheckedAt.isEmpty)
  let own = GitHub()
  precondition(try await own.existingFork("ME/tool") == nil && own.reads.isEmpty)
  // Accepted POST immediately records fork status without a follow-up read/poll.
  let posted = GitHub()
  _ = try await posted.fork("up/tool")
  precondition(posted.forkNames["up/tool"] == "me/tool" && posted.posts == 1 && posted.reads.isEmpty)
  print("PASS existing, renamed, unrelated name, permission error, account switch, own repository and POST propagation; no real HTTP")
 }
}
'''
        # Swift precondition uses a non-async/non-throwing autoclosure.
        import re
        counter = 0
        def evaluated(match):
            nonlocal counter
            counter += 1
            return 'let value%d = try await %s\n  precondition(value%d%s)' % (counter, match[1], counter, match[2])
        source = re.sub(r'precondition\(try await (\w+\.existingFork\("[^"\n]+"\))(.*)\)', evaluated, source)
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'Harness.swift'; path.write_text(source)
            subprocess.run(['swiftc', '-parse-as-library', str(path), '-o', folder+'/test'], check=True)
            subprocess.run([folder+'/test'], check=True)

if __name__ == '__main__': unittest.main()
