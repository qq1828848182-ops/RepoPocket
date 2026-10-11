import SwiftUI
import UIKit

@MainActor
final class UpdateChecker: ObservableObject {
    struct Release: Decodable, Identifiable {
        let tag_name: String
        let name: String?
        let html_url: URL
        var id: String { tag_name }
    }
    @Published var release: Release?
    @Published var error: String?
    @Published var checking = false
    private let url = URL(string: "https://api.github.com/repos/wm0104/RepoPocket/releases/latest")!
    func check() async {
        guard !checking else { return }; checking = true; defer { checking = false }
        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("RepoPocket", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let value = try JSONDecoder().decode(Release.self, from: data)
            let remote = value.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let local = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            release = compare(remote, local) == .orderedDescending ? value : nil
        } catch let caught { self.error = "检查更新失败：\(caught.localizedDescription)" }
    }
    private func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = lhs.split(separator: ".").map { Int($0) ?? 0 }, b = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) { let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0; if x != y { return x < y ? .orderedAscending : .orderedDescending } }
        return .orderedSame
    }
}

struct UpdatePrompt: ViewModifier {
    @StateObject private var checker = UpdateChecker()
    func body(content: Content) -> some View {
        content.environmentObject(checker).task { await checker.check() }
            .alert("发现 RepoPocket 新版本", isPresented: Binding(get: { checker.release != nil }, set: { if !$0 { checker.release = nil } })) {
                Button("打开 GitHub 发布页") {
                    if let url = checker.release?.html_url { UIApplication.shared.open(url) }
                }
                Button("稍后", role: .cancel) {}
            } message: { Text(checker.release.map { $0.name ?? $0.tag_name } ?? "") }
            .alert("更新检查", isPresented: Binding(get: { checker.error != nil }, set: { if !$0 { checker.error = nil } })) {
                Button("好", role: .cancel) {}
            } message: { Text(checker.error ?? "") }
    }
}
