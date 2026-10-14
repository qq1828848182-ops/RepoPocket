import Foundation

struct FileCommitResponse: Decodable {
    struct Content: Decodable { let sha: String }
    let content: Content
}

enum FileVersionRules {
    static func requireUnchanged(expectedSHA: String, actualSHA: String, isFile: Bool) throws {
        guard isFile, !expectedSHA.isEmpty, expectedSHA == actualSHA else {
            throw AppError(text: "远端文件已变化，拒绝删除新内容；请重新加载文件并确认。")
        }
    }
}
