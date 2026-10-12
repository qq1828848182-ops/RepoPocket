"""Network-free production UpdateChecker lifecycle regressions (macOS Swift)."""
from pathlib import Path
import unittest, tempfile, subprocess, shutil
feature = Path('RepoPocket/UpdateFeature.swift').read_text()

class NoticeTests(unittest.TestCase):
    def test_source_contracts(self):
        self.assertIn('6_000_000_000', feature)
        self.assertIn('noticeTask?.cancel()', feature)
        self.assertIn('!Task.isCancelled', feature)
        self.assertIn('.onDisappear { if share == nil { checker.leavePage() } }', feature)
        self.assertIn('self.generation == token', feature)
        self.assertNotIn('（build', feature)
        self.assertNotIn('CFBundleVersion', Path('RepoPocket/RepoPocketApp.swift').read_text())
        download = feature.split('    func download() {', 1)[1].split('final class UpdateDownloadDelegate', 1)[0]
        self.assertIn('clearNotice()', download)
        self.assertNotIn('showTransient(', download.split('downloading = true', 1)[1])
        self.assertIn('guard self.generation == token else { throw CancellationError() }', download)
        self.assertIn('defer { if self.generation == token', download)

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift available on Actions')
    def test_production_checker_with_mock_api(self):
        checker = feature.split('@MainActor final class UpdateChecker', 1)[1].split('    func download() {', 1)[0]
        checker = '@MainActor final class UpdateChecker' + checker + '\n}\n'
        rules = Path('RepoPocket/AppUpdateRules.swift').read_text()
        source = '''import Foundation
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
protocol ObservableObject {}
final class UpdateDownloadDelegate: NSObject {}
struct AppError: Error, LocalizedError { let text: String; var errorDescription: String? { text } }
@MainActor final class GitHub {
    let delay: UInt64
    let failure: String
    init(_ failure: String, delay: UInt64 = 0) { self.failure = failure; self.delay = delay }
    func officialAppUpdateData() async throws -> Data {
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        throw AppError(text: failure)
    }
}
''' + rules + checker + '''
@main struct Tests {
 @MainActor static func main() async throws {
    let checker = UpdateChecker()
    await checker.check(api: GitHub("first"))
    precondition(checker.message == "检查失败，请稍后重试")
    try await Task.sleep(nanoseconds: 6_200_000_000)
    precondition(checker.message.isEmpty)
    await checker.check(api: GitHub("速率旧消息"))
    try await Task.sleep(nanoseconds: 200_000_000)
    await checker.check(api: GitHub("凭据新消息"))
    try await Task.sleep(nanoseconds: 5_900_000_000)
    precondition(checker.message == "登录已失效，请更新凭据")
    checker.leavePage()
    precondition(checker.message.isEmpty && !checker.checking && !checker.downloading && checker.release == nil)
    let late = Task { await checker.check(api: GitHub("late", delay: 200_000_000)) }
    try await Task.sleep(nanoseconds: 50_000_000)
    checker.leavePage()
    await checker.check(api: GitHub("current"))
    await late.value
    precondition(checker.message == "检查失败，请稍后重试" && !checker.checking)
    checker.downloading = true
    try await Task.sleep(nanoseconds: 6_200_000_000)
    precondition(checker.message == "检查失败，请稍后重试")
    checker.cancelDownload()
    precondition(!checker.downloading && checker.message == "已取消下载。")
    checker.leavePage()
    precondition(checker.message.isEmpty)
    print("PASS production checker mocks: six-second expiry, new-message immunity, leave/reenter, stale request rejection, download timer protection, cancel/reset")
 }
}
'''
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'notice.swift'; path.write_text(source)
            subprocess.run(['swiftc', '-parse-as-library', str(path), '-o', d + '/test'], check=True)
            subprocess.run([d + '/test'], check=True)

if __name__ == '__main__': unittest.main()
