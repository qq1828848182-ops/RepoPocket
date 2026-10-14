import SwiftUI

@MainActor final class WorkspaceSelectionStore: ObservableObject {
    @Published var session = WorkspaceSelectionSession()
}

// Keep native navigation/list transitions. Compact only the expensive header space.
struct AdaptiveWorkspaceLayout: ViewModifier {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(verticalSizeClass == .compact ? .inline : .large)
            .environment(\.defaultMinListRowHeight, verticalSizeClass == .compact ? 36 : 44)
    }
}
extension View {
    func adaptiveWorkspaceLayout() -> some View { modifier(AdaptiveWorkspaceLayout()) }
}

// Row backgrounds, not a clip on the List: native swipe actions and scrolling remain intact.
struct SoftGroupShape: Shape {
    var top: Bool
    var bottom: Bool
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 22
        let extended = CGRect(x: rect.minX, y: rect.minY - (top ? 0 : radius),
                              width: rect.width, height: rect.height + (top ? 0 : radius) + (bottom ? 0 : radius))
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: extended)
    }
}

extension View {
    /// Keep the 1.0.4 outer shape, using the native content-aligned separator.
    /// Label rows align after the icon; text-only rows align with their text.
    func softGroupedRow(top: Bool = false, bottom: Bool = false, animateBackground: Bool = true) -> some View {
        listRowSeparator(.hidden, edges: .top)
            .listRowSeparator(bottom ? .hidden : .visible, edges: .bottom)
            .alignmentGuide(.listRowSeparatorLeading) { dimensions in
                max(dimensions[.listRowSeparatorLeading], dimensions[.leading])
            }
            .listRowBackground(
                SoftGroupShape(top: top, bottom: bottom)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(Rectangle())
                    .transaction { transaction in
                        if !animateBackground {
                            transaction.animation = nil
                            transaction.disablesAnimations = true
                        }
                    }
            )
    }
}

/// Native sibling rows with one shared boundary calculation, including rows
/// that appear after loading, permission checks or errors. No clipping of taps.
struct SoftGroupRow: Identifiable {
    let id: String
    let content: AnyView
    init<Content: View>(_ id: String, @ViewBuilder content: () -> Content) {
        self.id = id; self.content = AnyView(content())
    }
}
@resultBuilder enum SoftGroupRowsBuilder {
    static func buildExpression(_ row: SoftGroupRow) -> [SoftGroupRow] { [row] }
    static func buildBlock(_ groups: [SoftGroupRow]...) -> [SoftGroupRow] { groups.flatMap { $0 } }
    static func buildOptional(_ rows: [SoftGroupRow]?) -> [SoftGroupRow] { rows ?? [] }
    static func buildEither(first: [SoftGroupRow]) -> [SoftGroupRow] { first }
    static func buildEither(second: [SoftGroupRow]) -> [SoftGroupRow] { second }
    static func buildArray(_ groups: [[SoftGroupRow]]) -> [SoftGroupRow] { groups.flatMap { $0 } }
}
struct SoftGroupRows: View {
    private let rows: [SoftGroupRow]
    init(@SoftGroupRowsBuilder rows: () -> [SoftGroupRow]) { self.rows = rows() }
    var body: some View {
        ForEach(rows) { row in
            row.content.softGroupedRow(top: row.id == rows.first?.id, bottom: row.id == rows.last?.id)
        }
    }
}
