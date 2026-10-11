import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct GitWorkspaceView: View {
    @EnvironmentObject private var gitCore: GitCore
    @State private var pickerPresented = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            List {
                Section("本地 Git 仓库") {
                    if gitCore.repositories.isEmpty {
                        Text("还没有导入仓库。选择包含 .git 的文件夹开始。")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(gitCore.repositories) { repository in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(repository.name).font(.headline)
                                Text(repository.url.path).font(.caption).foregroundColor(.secondary)
                            }
                            .swipeActions {
                                Button("移除", role: .destructive) { gitCore.remove(repository) }
                            }
                        }
                    }
                }
                Section {
                    Button { pickerPresented = true } label: {
                        Label("导入本地仓库", systemImage: "folder.badge.plus")
                    }
                } footer: {
                    Text("当前阶段只验证并保存本地仓库。下一阶段接入 libgit2 后提供状态、提交和历史。")
                }
            }
            .navigationTitle("Git")
            .sheet(isPresented: $pickerPresented) {
                FolderPicker { url in
                    do { try gitCore.importRepository(url) }
                    catch { errorMessage = error.localizedDescription }
                }
            }
            .alert("无法导入", isPresented: Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })) {
                Button("好", role: .cancel) {}
            } message: { Text(errorMessage) }
        }
    }
}

private struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder], asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}
