import Foundation

enum CommunityMutation {
    case createIssue, comment(Int), state(Int, String), merge(Int, String), cancelRun(Int), rerun(Int), deleteRun(Int)
}
struct CommunityMutationRequest {
    let suffix: String
    let method: String
    let requiresPush: Bool
    let body: [String: Any]
}
enum CommunityMutationRules {
    static func request(_ action: CommunityMutation, title: String = "", text: String = "") throws -> CommunityMutationRequest {
        func positive(_ id: Int) throws { guard id > 0 else { throw AppError(text: "无效的操作编号") } }
        switch action {
        case .createIssue:
            let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, clean.count <= 256, text.utf8.count <= 60_000 else { throw AppError(text: "请填写不超过256字的标题，正文须小于60 KB。") }
            return .init(suffix: "/issues", method: "POST", requiresPush: false, body: ["title": clean, "body": text])
        case .comment(let id):
            try positive(id)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 60_000 else { throw AppError(text: "评论不能为空，且须小于60 KB。") }
            return .init(suffix: "/issues/\(id)/comments", method: "POST", requiresPush: false, body: ["body": text])
        case .state(let id, let state):
            try positive(id); guard ["open", "closed"].contains(state) else { throw AppError(text: "无效议题状态") }
            return .init(suffix: "/issues/\(id)", method: "PATCH", requiresPush: false, body: ["state": state])
        case .merge(let id, let sha):
            try positive(id); guard sha.count == 40, sha.allSatisfy({ $0.isHexDigit }) else { throw AppError(text: "未取得 PR 的确切提交，不能合并。") }
            return .init(suffix: "/pulls/\(id)/merge", method: "PUT", requiresPush: true, body: ["sha": sha, "merge_method": "merge"])
        case .cancelRun(let id):
            try positive(id); return .init(suffix: "/actions/runs/\(id)/cancel", method: "POST", requiresPush: true, body: [:])
        case .rerun(let id):
            try positive(id); return .init(suffix: "/actions/runs/\(id)/rerun", method: "POST", requiresPush: true, body: [:])
        case .deleteRun(let id):
            try positive(id); return .init(suffix: "/actions/runs/\(id)", method: "DELETE", requiresPush: true, body: [:])
        }
    }
}
struct WorkflowRuns: Decodable { let workflow_runs: [WorkflowRun] }
struct WorkflowRun: Decodable, Identifiable {
    let id: Int
    let name: String?
    let display_title: String?
    let run_number: Int
    let head_branch: String?
    let head_sha: String
    let status: String
    let conclusion: String?
    let created_at: String
}
struct WorkflowJobs: Decodable { let jobs: [WorkflowJob] }
struct WorkflowArtifacts: Decodable { let artifacts: [WorkflowArtifact] }
struct WorkflowArtifact: Decodable, Identifiable {
    let id: Int
    let name: String
    let size_in_bytes: Int
    let expired: Bool
}
struct WorkflowJob: Decodable, Identifiable {
    let id: Int
    let name: String
    let status: String
    let conclusion: String?
    let steps: [Step]?
    struct Step: Decodable, Identifiable {
        let number: Int
        let name: String
        let status: String
        let conclusion: String?
        var id: Int { number }
    }
}
struct StarTimestamp: Decodable { let starred_at: String; let user: User? }
struct CodeTree: Decodable {
    let tree: [File]
    let truncated: Bool?
    struct File: Decodable { let path: String; let type: String; let size: Int? }
}
struct CodeLineSummary { let files: Int; let lines: Int; let skipped: Int; let treeTruncated: Bool }
enum NativeStatisticsRules {
    static let extensions = Set(["swift", "m", "mm", "h", "c", "cpp", "hpp", "js", "jsx", "ts", "tsx", "py", "go", "rs", "java", "kt", "sh", "rb", "dart", "cs", "css", "html", "json", "yml", "yaml"])
    static func lineCount(_ text: String) -> Int { text.isEmpty ? 0 : text.filter { $0 == "\n" }.count + (text.hasSuffix("\n") ? 0 : 1) }
}
