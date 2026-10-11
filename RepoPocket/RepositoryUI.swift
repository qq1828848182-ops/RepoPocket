import SwiftUI
import UIKit

// Avatar requests are deliberately unauthenticated and restricted to GitHub's image host.
// Never follow redirects: even an allowed avatar host must not redirect to another host.
private final class AvatarRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class AvatarLoader: ObservableObject {
    @Published var image: UIImage?
    private static let cache = NSCache<NSURL, UIImage>()
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = false
        configuration.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 24 * 1024 * 1024, diskPath: "RepoPocketAvatars")
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration, delegate: AvatarRedirectPolicy(), delegateQueue: nil)
    }()
    func load(_ raw: String?) async {
        image = nil
        guard let raw, let url = URL(string: raw), url.scheme == "https",
              url.host == "avatars.githubusercontent.com", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return }
        if let cached = Self.cache.object(forKey: url as NSURL) { image = cached; return }
        do {
            let (data, response) = try await Self.session.data(from: url)
            guard !Task.isCancelled, let response = response as? HTTPURLResponse,
                  response.statusCode == 200, data.count <= 4 * 1024 * 1024,
                  let decoded = UIImage(data: data) else { return }
            Self.cache.setObject(decoded, forKey: url as NSURL, cost: data.count)
            image = decoded
        } catch { /* Missing or offline avatars retain their placeholder. */ }
    }
}

struct GitHubAvatar: View {
    let url: String?
    var size: CGFloat = 40
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var loader = AvatarLoader()
    var body: some View {
        Group {
            if let image = loader.image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: "person.crop.circle.fill").resizable().foregroundColor(.secondary) }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: loader.image != nil)
        .task(id: url) { await loader.load(url) }
    }
}

struct RepositoryCard: View {
    let repository: Repository
    let account: String
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    var body: some View {
        HStack(alignment: .top, spacing: verticalSizeClass == .compact ? 8 : 12) {
            GitHubAvatar(url: repository.owner?.avatar_url)
            VStack(alignment: .leading, spacing: verticalSizeClass == .compact ? 3 : 6) {
                Text(repository.full_name).font(.headline).lineLimit(2)
                if let description = repository.description, !description.isEmpty {
                    Text(description).font(.subheadline).foregroundColor(.secondary).lineLimit(2)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                    Label(repository.private == true ? "私有" : "公开", systemImage: repository.private == true ? "lock" : "globe")
                    Label(repository.default_branch ?? "未设置", systemImage: "arrow.triangle.branch")
                }
                    VStack(alignment: .leading, spacing: 4) {
                        Label(repository.private == true ? "私有" : "公开", systemImage: repository.private == true ? "lock" : "globe")
                        Label(repository.default_branch ?? "未设置", systemImage: "arrow.triangle.branch")
                    }
                }.font(.caption).foregroundColor(.secondary)
                if let date = repository.updated_at.flatMap({ ISO8601DateFormatter().date(from: $0) }) {
                    Text("更新：" + date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundColor(.secondary)
                }
                Text("访问账号：" + (account.isEmpty ? "待验证" : account)).font(.caption2).foregroundColor(.secondary)
            }
        }.padding(.vertical, verticalSizeClass == .compact ? 3 : 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}

struct LoadingRows: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView("加载中…")
            ForEach(0..<3) { _ in
                HStack {
                    Circle().fill(Color.secondary.opacity(0.15)).frame(width: 36, height: 36)
                    VStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)).frame(height: 12)
                        RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.10)).frame(width: 140, height: 10)
                    }
                }.accessibilityHidden(true)
            }
        }.padding(.vertical, 8)
    }
}
