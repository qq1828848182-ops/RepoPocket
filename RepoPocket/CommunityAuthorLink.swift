import SwiftUI

struct CommunityAuthorLink: View {
    @ObservedObject var api: GitHub
    let user: User?
    var date: String? = nil
    var body: some View {
        Group {
            if let user, !user.login.isEmpty {
                NavigationLink { UserRepositoriesView(api: api, user: user) } label: { identity }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("查看 " + user.login + " 的主页")
            } else { identity }
        }
    }
    private var identity: some View {
        HStack(spacing: 12) {
            GitHubAvatar(url: user?.avatar_url, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(user?.login ?? "已删除用户").font(.headline).foregroundStyle(.primary)
                if let date { Text(ChinaDate.dateTime(date)).font(.caption).foregroundStyle(.secondary) }
            }
        }.frame(minHeight: 44)
    }
}
