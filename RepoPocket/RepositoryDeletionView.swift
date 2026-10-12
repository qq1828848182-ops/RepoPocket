import SwiftUI

struct RepositoryDeletionTarget: Identifiable {
    let id = UUID()
    let repository: Repository
    let context: RepositoryDeletionContext
}

struct RepositoryDeletionView: View {
    @ObservedObject var api: GitHub
    let repository: Repository
    let context: RepositoryDeletionContext
    let onDeleted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation = ""
    @State private var busy = false
    @State private var errorMessage = ""
    private var accountIsCurrent: Bool {
        context.accountID == AccountStore.activeID && context.generation == AccountStore.generation
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("危险操作：永久删除 GitHub 远端仓库") {
                    Text("将删除整个远端仓库，包括代码、Issues、Release 及其附件。这不是删除单个文件，也不是删除本地工作区。此操作不可撤销。")
                        .foregroundColor(.red)
                    Text(repository.full_name).font(.headline).textSelection(.enabled)
                    Text("访问账号：" + (api.login.isEmpty ? context.accountID : api.login))
                    Text(RepositoryDeletion.permissionHelp).font(.caption)
                }
                Section("输入完整 owner/repo 确认") {
                    TextField(repository.full_name, text: $confirmation)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .disabled(busy)
                    if !accountIsCurrent { Text("账号已变化，请关闭并重新打开。").foregroundColor(.red) }
                    if !errorMessage.isEmpty { Text(errorMessage).foregroundColor(.red).textSelection(.enabled) }
                    if busy { ProgressView("正在核验权限并删除…") }
                    Button("永久删除远端仓库", role: .destructive) {
                        guard !busy else { return }
                        busy = true; errorMessage = ""
                        Task {
                            defer { busy = false }
                            do {
                                let message = try await api.deleteRepository(repository, context: context, confirmation: confirmation)
                                onDeleted(); dismiss(); api.message = message
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }.disabled(busy || !accountIsCurrent || confirmation != repository.full_name || repository.permissions?.admin != true)
                }
            }
            .navigationTitle("删除远端仓库")
            .toolbar { Button("取消") { dismiss() }.disabled(busy) }
            .interactiveDismissDisabled(busy)
        }
    }
}
