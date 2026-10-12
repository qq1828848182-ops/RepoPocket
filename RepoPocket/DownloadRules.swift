import Foundation

/// File operations are bounded to an explicitly authorized parent. Never overwrite.
enum DownloadRules {
    static func safeName(_ raw: String) -> String {
        let name = (raw as NSString).lastPathComponent
        let clean = name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != ":" && $0 != "\\" }.map(String.init).joined()
        return clean.isEmpty || clean == "." || clean == ".." ? "file" : String(clean.prefix(180))
    }
    static func rejectSymlinks(_ url: URL) throws {
        var current = url.standardizedFileURL
        while current.path != "/" {
            if (try? current.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw NSError(domain: "DownloadStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "目录含符号链接，请重新选择保存位置。"]) }
            current.deleteLastPathComponent()
        }
    }
    static func save(_ source: URL, parent: URL, valid: () -> Bool,
                     fingerprint: (URL) throws -> String,
                     copy: (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) }) throws -> URL {
        let fm = FileManager.default
        guard valid() else { throw CancellationError() }
        try rejectSymlinks(parent)
        let folder = parent.appendingPathComponent("RepoPocket", isDirectory: true)
        try rejectSymlinks(folder)
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        let name = safeName(source.lastPathComponent)
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var target = folder.appendingPathComponent(name)
        var suffix = 1
        while fm.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent(stem + " (\(suffix))" + (ext.isEmpty ? "" : "." + ext)); suffix += 1
        }
        let staging = folder.appendingPathComponent(".repopocket-" + UUID().uuidString + ".partial")
        defer { try? fm.removeItem(at: staging) }
        let expected = try fingerprint(source)
        try copy(source, staging)
        guard valid() else { throw CancellationError() }
        guard try fingerprint(staging) == expected else { throw NSError(domain: "DownloadStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "保存校验失败，请重试。"]) }
        // moveItem is exclusive (throws on an existing destination), not a replace.
        try fm.moveItem(at: staging, to: target)
        return target
    }
}

enum CacheRules {
    /// Only the two dedicated cache children; never Documents, temp, downloads or Keychain.
    static func clear(root: URL, busy: Bool, remove: (URL) throws -> Void) throws {
        guard !busy else { throw NSError(domain: "Cache", code: 1, userInfo: [NSLocalizedDescriptionKey: "操作进行中，请稍后清理缓存。"]) }
        try DownloadRules.rejectSymlinks(root)
        let children = ["RepoPocketCache", "RepoPocketAvatars"].map { root.appendingPathComponent($0, isDirectory: true) }
        for child in children { try DownloadRules.rejectSymlinks(child) }
        for child in children {
            if FileManager.default.fileExists(atPath: child.path) { try remove(child) }
        }
    }
}
