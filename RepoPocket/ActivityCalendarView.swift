import SwiftUI

struct ActivityCalendarView: View {
    let days: [ActivityDay]
    @Binding var selected: String?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    private var leading: Int {
        guard let first = days.first else { return 0 }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = ChinaDate.timeZone
        return (calendar.component(.weekday, from: first.date) + 5) % 7
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let first = days.first, let last = days.last {
                Text(first.title + " — " + last.title).font(.subheadline).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 44).accessibilityHidden(true) }
                ForEach(days) { day in
                    Button { selected = day.id } label: {
                        Text(day.id.suffix(2)).font(.caption.monospacedDigit())
                            .foregroundStyle((day.count ?? 0) >= 4 ? Color.white : Color.primary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(tint(day), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 6).stroke(selected == day.id ? Color.accentColor : Color.secondary.opacity(day.complete ? 0 : 0.4), style: StrokeStyle(lineWidth: selected == day.id ? 2 : 1, dash: day.complete ? [] : [3, 2])) }
                    }.buttonStyle(.plain)
                    .accessibilityLabel(day.title + "，" + day.detail)
                    .accessibilityIdentifier("activity-day-" + day.id)
                }
            }
            HStack(spacing: 12) {
                Label("未完整加载", systemImage: "square.dashed")
                Text("浅色少 · 深色多")
            }.font(.caption2).foregroundStyle(.secondary)
        }.padding(.vertical, 5)
    }
    private func tint(_ day: ActivityDay) -> Color {
        guard let count = day.count else { return Color.clear }
        if count == 0 { return Color.secondary.opacity(0.1) }
        return Color.green.opacity(count < 4 ? 0.25 : (count < 10 ? 0.6 : 0.95))
    }
}

struct ActivityDayEvents: View {
    @ObservedObject var api: GitHub
    let day: ActivityDay
    var body: some View {
        Section(day.title + " · 公开活动") {
            SoftGroupRows {
                SoftGroupRow("summary") { Text(day.detail).font(.caption).foregroundStyle(.secondary) }
                for event in day.events {
                    SoftGroupRow(event.id) {
                        NavigationLink { BrowserView(api: api, repo: event.repo.name, path: "", branch: "") } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(event.summary).foregroundStyle(.primary)
                                Text(event.repo.name).font(.subheadline)
                                Text(ChinaDate.dateTime(event.created_at)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}
