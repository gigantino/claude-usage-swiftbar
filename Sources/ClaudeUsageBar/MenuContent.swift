import SwiftUI
import ClaudeUsageCore

/// The dropdown shown when the menu bar item is clicked. Uses the native `.menu`
/// style, so rows are standard menu items: Text for read-outs, Toggle for
/// settings, Button for actions.
struct MenuContent: View {
    @ObservedObject var model: UsageViewModel

    var body: some View {
        Group {
            usageRows

            Divider()

            Toggle("Show time in menu bar", isOn: $model.showTimeInTitle)

            Picker("Poll usage API", selection: $model.refreshInterval) {
                ForEach(UsageViewModel.RefreshInterval.allCases) { interval in
                    Text(interval.label).tag(interval)
                }
            }

            Button(model.isPolling ? "Refreshing…" : "Refresh from API now") {
                model.refreshNow()
            }
            .disabled(model.isPolling)

            Divider()

            if let status = model.statusMessage {
                Text(status)
            }
            if let freshness = UsageFormatting.freshness(model.snapshot, now: model.clock),
               let source = model.snapshot?.source {
                Text("\(source.displayName) (\(freshness))")
            }

            Divider()

            Button("Quit Claude Usage") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    @ViewBuilder
    private var usageRows: some View {
        let rows = model.snapshot?.rows(now: model.clock) ?? []
        if rows.isEmpty {
            Text("No usage data yet")
            Text("Open a Claude Code session or refresh")
                .font(.caption)
        } else {
            ForEach(rows) { row in
                Text(text(for: row))
            }
        }
    }

    private func text(for row: UsageRow) -> String {
        var text = "\(row.title): \(row.percent)"
        if let countdown = row.countdown { text += " (\(countdown))" }
        if let detail = row.detail { text += " (\(detail))" }
        return text
    }
}
