import subprocess, tempfile, zipfile, stat
from pathlib import Path
with tempfile.TemporaryDirectory() as d:
 root = Path(d)
 (root/'Sources'/'ZIPRegression').mkdir(parents=True)
 (root/'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ZIPRegression", platforms: [.macOS(.v12)], dependencies: [.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.19")], targets: [.executableTarget(name: "ZIPRegression", dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")])])
''')
 fixtures = [('valid', 'nested/a.txt', False), ('traversal', '../escape', False), ('absolute', '/escape', False), ('backslash', 'a\\b', False), ('symlink', 'link', True)]
 for name, path, link in fixtures:
  with zipfile.ZipFile(root/(name+'.zip'), 'w') as z:
   info=zipfile.ZipInfo(path)
   if link:
    info.create_system=3; info.external_attr=(stat.S_IFLNK | 0o777)<<16
   z.writestr(info, '/etc/passwd' if link else 'hello')
 with zipfile.ZipFile(root/'duplicate.zip', 'w') as z:
  z.writestr('A.txt','a'); z.writestr('a.txt','b')
 tests = '''
let fm = FileManager.default
let base = URL(fileURLWithPath: CommandLine.arguments[1])
for name in ["valid", "traversal", "absolute", "backslash", "symlink", "duplicate"] {
 let output = base.appendingPathComponent(name + "-out")
 try fm.createDirectory(at: output, withIntermediateDirectories: true)
 var rejected = false
 do { try WorkspaceZIP.extract(base.appendingPathComponent(name + ".zip"), to: output) } catch { rejected = true }
 precondition(rejected == (name != "valid"), name)
 if name != "valid" { precondition(try! fm.contentsOfDirectory(atPath: output.path).isEmpty) }
}
print("PASS: real ZIPFoundation extraction; zip slip, absolute, backslash, symlink and duplicate rejection before writes")
'''
 (root/'Sources'/'ZIPRegression'/'main.swift').write_text('import Foundation\nstruct AppError: LocalizedError { let text: String; var errorDescription: String? { text } }\n'+Path('RepoPocket/WorkspaceZIP.swift').read_text()+tests)
 subprocess.run(['swift','run','--package-path',str(root),'ZIPRegression',str(root)],check=True)
