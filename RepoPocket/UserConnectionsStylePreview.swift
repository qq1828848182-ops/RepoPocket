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
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.path ?? ""
        let allowed = request.url?.host == "api.github.com"
            && request.httpMethod == "GET"
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
        } else if path == "/user/repos" || path == "/user/starred" || path.hasSuffix("/repos") {
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
    override func stopLoading() {}
}
#endif
