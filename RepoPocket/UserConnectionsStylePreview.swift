#if DEBUG
import SwiftUI

/// The shipping repositories home and navigation, with an isolated fake account.
struct UserConnectionsStylePreview: View {
    @State private var api: GitHub?
    @State private var error = ""
    var body: some View {
        Group {
            if let api { RepositoriesView(api: api) }
            else if !error.isEmpty { Text(error) }
            else { ProgressView("准备关注列表测试") }
        }.task {
            guard api == nil, error.isEmpty else { return }
            do {
                let id = "401"
                try CredentialStore.save("fixture-connections", account: id)
                try AccountStore.record(.init(id: id, login: "fixture-owner", avatarURL: nil))
                AccountStore.activate(id)
                let config = URLSessionConfiguration.ephemeral
                config.protocolClasses = [ConnectionsPreviewProtocol.self]
                api = GitHub(configuration: config)
            } catch { self.error = error.localizedDescription }
        }
    }
}

private final class ConnectionsPreviewProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var posted = ""
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.path ?? ""
        let post = request.httpMethod == "POST" && path == "/repos/fixture-owner/sample/issues/4/comments"
        var acceptedPost = false
        if post, request.url?.host == "api.github.com", request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-connections",
           let data = Self.body(request), let body = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let text = body["body"], text.contains("@fixture-follower"), text.contains("> 请增加英文支持"), text.contains("#issuecomment-71") {
            Self.lock.lock(); Self.posted = text; Self.lock.unlock(); acceptedPost = true
        }
        let allowed = request.url?.host == "api.github.com"
            && (request.httpMethod == "GET" || acceptedPost)
            && request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-connections"
        let payload: String
        if path == "/user" {
            payload = #"{"id":401,"login":"fixture-owner","followers":2,"following":1}"#
        } else if path == "/users/fixture-owner/followers" {
            payload = #"[{"id":402,"login":"fixture-follower"},{"id":403,"login":"fixture-second"}]"#
        } else if path == "/users/fixture-owner/following" {
            payload = #"[{"id":404,"login":"fixture-following"}]"#
        } else if path == "/users/fixture-follower" || path == "/users/fixture-following" {
            let login = path.components(separatedBy: "/").last!
            payload = "{\"login\":\"" + login + "\",\"bio\":\"关注列表测试用户\",\"public_repos\":0,\"followers\":0,\"following\":0}"
        } else if path == "/user/repos" {
            payload = #"[{"id":501,"name":"alpha","full_name":"fixture-owner/alpha","html_url":"https://github.com/fixture-owner/alpha"},{"id":502,"name":"beta","full_name":"fixture-owner/beta","html_url":"https://github.com/fixture-owner/beta"}]"#
        } else if path == "/user/starred" {
            payload = #"[{"id":503,"name":"starred","full_name":"other/starred","html_url":"https://github.com/other/starred"}]"#
        } else if path == "/search/issues" {
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value ?? ""
            payload = query.contains("mentions:") ? #"{"items":[],"incomplete_results":false}"# : "{\"items\":[" + Self.issue + "],\"incomplete_results\":false}"
        } else if path == "/repos/fixture-owner/sample/issues/4" {
            payload = Self.issue
        } else if path == "/repos/fixture-owner/sample" {
            payload = #"{"id":504,"name":"sample","full_name":"fixture-owner/sample","html_url":"https://github.com/fixture-owner/sample","permissions":{"push":false}}"#
        } else if path == "/repos/fixture-owner/sample/issues/4/comments" {
            Self.lock.lock(); let posted = Self.posted; Self.lock.unlock()
            let rows: [[String: Any]] = [
                ["id":71,"user":["login":"fixture-follower"],"body":"> 更早的引用\n\n请增加英文支持","created_at":"2026-10-19T00:00:00Z"],
                ["id":72,"user":["login":"fixture-second"],"body":"另一位用户的评论","created_at":"2026-10-19T01:00:00Z"]
            ] + (posted.isEmpty ? [] : [["id":73,"user":["login":"fixture-owner"],"body":posted]])
            payload = String(decoding: (try? JSONSerialization.data(withJSONObject: rows)) ?? Data("[]".utf8), as: UTF8.self)
        } else if path == "/users/fixture-follower/events/public" {
            let page = Int(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value ?? "1") ?? 1
            let formatter = ISO8601DateFormatter()
            let date = formatter.string(from: Date().addingTimeInterval(page == 1 ? -600 : -86400))
            let rows: [[String: Any]] = page <= 3 ? (0..<30).map {
                ["id":"\(page)-\($0)","type":"PushEvent","actor":["login":"fixture-follower"],"repo":["name":"fixture-owner/sample"],"created_at":date]
            } : []
            payload = String(decoding: (try? JSONSerialization.data(withJSONObject: rows)) ?? Data("[]".utf8), as: UTF8.self)
        } else if path.hasSuffix("/repos") {
            payload = "[]"
        } else {
            payload = #"{"message":"Unexpected fixture route"}"#
        }
        let success = allowed && !payload.contains("Unexpected fixture route")
        let response = HTTPURLResponse(url: request.url!, statusCode: success ? 200 : 403,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    private static let issue = #"{"id":601,"number":4,"title":"Add English support","state":"open","html_url":"https://github.com/fixture-owner/sample/issues/4","body":"Issue fixture body","comments":2,"updated_at":"2026-10-19T00:00:00Z","user":{"login":"fixture-follower"}}"#
    private static func body(_ request: URLRequest) -> Data? {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count))
            if data.count > 60_000 { return nil }
        }
        return data
    }
    override func stopLoading() {}
}
#endif
