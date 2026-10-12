import Foundation

struct AppVersion: Comparable {
    let parts: [Int]
    let prerelease: [String]
    let build: Int?
    init?(_ text: String) {
        let raw = text.hasPrefix("v") || text.hasPrefix("V") ? String(text.dropFirst()) : text
        let metadata = raw.split(separator: "+", omittingEmptySubsequences: false)
        guard metadata.count <= 2 else { return nil }
        let main = metadata[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = main[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3, numbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) && ($0.count == 1 || !$0.hasPrefix("0")) }), numbers.allSatisfy({ Int($0) != nil }) else { return nil }
        parts = numbers.map { Int($0)! }
        prerelease = main.count == 2 ? main[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init) : []
        let identifiers = prerelease + (metadata.count == 2 ? metadata[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init) : [])
        guard identifiers.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 } }), prerelease.allSatisfy({ Int($0) == nil || $0.count == 1 || !$0.hasPrefix("0") }) else { return nil }
        build = metadata.count == 2 ? Int(metadata[1]) : nil
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        for i in 0..<3 where lhs.parts[i] != rhs.parts[i] { return lhs.parts[i] < rhs.parts[i] }
        if lhs.prerelease.isEmpty != rhs.prerelease.isEmpty { return !lhs.prerelease.isEmpty }
        for (a, b) in zip(lhs.prerelease, rhs.prerelease) where a != b {
            if let x = Int(a), let y = Int(b) { return x < y }
            if Int(a) != nil { return true }; if Int(b) != nil { return false }
            return a < b
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.parts == rhs.parts && lhs.prerelease == rhs.prerelease }
}
struct AppUpdateRelease: Decodable {
    struct Asset: Decodable { let name: String; let browser_download_url: URL }
    let tag_name: String
    let html_url: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    var ipaURL: URL? {
        let matches = assets.filter { $0.name == "RepoPocket.ipa" || $0.name == "RepoPocket-\(tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name).ipa" }
        guard matches.count == 1 else { return nil }
        let url = matches[0].browser_download_url
        guard url.scheme == "https", url.host == "github.com", url.path.hasPrefix("/wm0104/RepoPocket/releases/download/") else { return nil }
        return url
    }
}
enum AppUpdateRules {
    static func statusError(_ status: Int) -> String {
        switch status {
        case 404: return "尚无可用的正式 Release，或发布源暂不可用。"
        case 403, 429: return "GitHub 公共接口访问受限或达到速率限制，请稍后重试；此检查不使用 Token。"
        default: return "检查更新失败：GitHub HTTP \(status)，请稍后重试。"
        }
    }
    static func isNewer(_ release: AppUpdateRelease, local: String, localBuild: String) throws -> Bool {
        guard !release.draft, !release.prerelease, let remote = AppVersion(release.tag_name), remote.prerelease.isEmpty, let current = AppVersion(local) else { throw AppError(text: "发布版本格式无效或不是正式版本，无法安全比较。") }
        if remote != current { return current < remote }
        // Numeric +metadata is an explicit build marker; never infer builds from dates/IDs.
        if let remoteBuild = remote.build, let installedBuild = Int(localBuild) { return remoteBuild > installedBuild }
        return false
    }
}
