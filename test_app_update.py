from pathlib import Path
import unittest, tempfile, subprocess, shutil

rules = Path('RepoPocket/AppUpdateRules.swift').read_text()
feature = Path('RepoPocket/UpdateFeature.swift').read_text()

class UpdateTests(unittest.TestCase):
    def test_manual_safe_contract(self):
        self.assertNotIn('.task {', feature)
        self.assertNotIn('Authorization', feature)
        self.assertNotIn('com.opa334.TrollStore://', feature)
        for value in ['apple-magnifier', 'URLQueryItem(name: "url"', 'downloadTask?.cancel()', 'snapshotFileSHA256', 'archive.extract', 'HTTPURLResponse', '其他修改版未验证', 'https://github.com/wm0104/RepoPocket/releases']:
            self.assertIn(value, feature)
        self.assertIn('AppUpdateSection()', Path('RepoPocket/RepoPocketApp.swift').read_text())
    @unittest.skipUnless(shutil.which('swiftc'), 'Swift compiler is available in macOS Actions')
    def test_production_version_and_asset_rules(self):
        api = Path('RepoPocket/GitHub.swift').read_text()
        source = 'import Foundation\n' + api[api.index('struct AppError:'):api.index('struct GitHubAPIError:')] + rules.replace('import Foundation', '') + r'''
precondition(AppVersion("1.0.9")! < AppVersion("1.0.10")!)
precondition(AppVersion("1.0.1-rc.9")! < AppVersion("1.0.1-rc.10")!)
precondition(AppVersion("1.0.1-rc.10")! < AppVersion("1.0.1")!)
precondition(AppVersion("1.0.1+8")! == AppVersion("1.0.1+7")!)
for bad in ["nightly", "1.0", "01.0.1", "1.0.1-", "1.0.1+", "1.0.1-01"] { precondition(AppVersion(bad) == nil) }
func release(_ tag: String, _ draft: Bool = false, _ pre: Bool = false, _ assets: String = "[]") throws -> AppUpdateRelease {
    let raw = "{\"tag_name\":\"\(tag)\",\"html_url\":\"https://github.com/wm0104/RepoPocket/releases/tag/\(tag)\",\"draft\":\(draft),\"prerelease\":\(pre),\"assets\":\(assets)}"
    return try JSONDecoder().decode(AppUpdateRelease.self, from: Data(raw.utf8))
}
precondition(try AppUpdateRules.isNewer(release("v1.1.0"), local: "1.0.1", localBuild: "7"))
precondition(try AppUpdateRules.isNewer(release("v1.0.1+8"), local: "1.0.1", localBuild: "7"))
precondition(try !AppUpdateRules.isNewer(release("v1.0.1"), local: "1.0.1", localBuild: "7"))
for bad in [try release("v1.1.0", true), try release("v1.1.0", false, true), try release("v1.1.0-rc.1")] {
    do { _ = try AppUpdateRules.isNewer(bad, local: "1.0.1", localBuild: "7"); fatalError("invalid release accepted") } catch {}
}
let asset = #"[{"name":"RepoPocket.ipa","browser_download_url":"https://github.com/wm0104/RepoPocket/releases/download/v1.1.0/RepoPocket.ipa"}]"#
precondition(try release("v1.1.0", false, false, asset).ipaURL != nil)
precondition(try release("v1.1.0", false, false, asset.replacingOccurrences(of: "github.com", with: "evil.invalid")).ipaURL == nil)
precondition(AppUpdateRules.statusError(404).contains("尚无"))
precondition(AppUpdateRules.statusError(403).contains("不使用 Token"))
print("PASS production SemVer/build, draft/prerelease, missing/equal/new versions, trusted IPA and public API errors")
'''
        # Throwing expressions cannot be evaluated in precondition's nonthrowing autoclosure.
        source = source.replace('precondition(try ', 'check(try ')
        source = 'func check(_ value: Bool) { precondition(value) }\n' + source
        with tempfile.TemporaryDirectory() as folder:
            file = Path(folder) / 'main.swift'; file.write_text(source)
            subprocess.run(['swiftc', str(file), '-o', folder + '/tests'], check=True)
            subprocess.run([folder + '/tests'], check=True)

if __name__ == '__main__': unittest.main()
