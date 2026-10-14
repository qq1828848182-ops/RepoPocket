import SwiftUI
import SafariServices

struct ReadingLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Keep supported GitHub destinations native; other web pages remain inside the app.
struct ReadingLinkDestination: View {
    let url: URL
    let api: GitHub?
    @Environment(\.dismiss) private var dismiss
    private var destination: AnyView {
        guard let api, url.host?.lowercased() == "github.com",
              url.user == nil, url.password == nil else { return AnyView(ContainedWebPage(url: url)) }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, let repo = try? RepositoryInput.parse(parts[0] + "/" + parts[1]) else {
            return AnyView(ContainedWebPage(url: url))
        }
        if parts.count == 2 { return AnyView(BrowserView(api: api, repo: repo, path: "", branch: "")) }
        if parts.count == 4, let number = Int(parts[3]), number > 0, ["issues", "pull"].contains(parts[2]) {
            return AnyView(CollaborationDetailView(api: api, repo: repo, kind: parts[2] == "issues" ? .issues : .pulls, number: number))
        }
        if parts.count == 4, parts[2] == "commit", parts[3].count == 40,
           parts[3].allSatisfy({ $0.isHexDigit }) {
            return AnyView(CommitDetailView(api: api, repo: repo, sha: parts[3]))
        }
        if parts.count == 3, parts[2] == "actions" {
            return AnyView(WorkflowRunsView(api: api, repo: repo, branch: ""))
        }
        return AnyView(ContainedWebPage(url: url))
    }
    var body: some View {
        NavigationStack { destination.toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } } }
    }
}

struct ContainedWebPage: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
