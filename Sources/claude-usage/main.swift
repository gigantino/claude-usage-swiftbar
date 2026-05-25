import Foundation
import ClaudeUsageCore

// `claude-usage` is the command line companion to the menu bar app.
//
// Subcommands:
//   statusline   Read Claude Code's status-line JSON from stdin, cache the
//                rate-limit data, and print a status line. Use as the
//                `statusLine.command` in ~/.claude/settings.json.
//   fetch        Poll the OAuth usage endpoint once and update the cache.
//   print        Print the current cached usage (default).
//   help         Show usage.

let cache = UsageCache.default

func runStatusLine() -> Int32 {
    let input = FileHandle.standardInput.readDataToEndOfFile()

    guard let payload = try? StatusLinePayload(from: input) else {
        // Not valid status-line JSON; emit nothing rather than garbage.
        return 0
    }

    // Persist rate-limit data when Claude Code provides it (Pro/Max, after the
    // first API response). This is the free, real-time feed for the menu bar.
    let snapshot = payload.usageSnapshot()
    if let snapshot {
        try? cache.save(snapshot)
    }

    // Render a status line: context window plus session usage when available.
    var parts: [String] = []
    if let ctx = UsageFormatting.percent(payload.contextPercentage) {
        parts.append("Context: \(ctx)")
    }
    if let session = snapshot?.fiveHour, let pct = UsageFormatting.percent(session.utilization) {
        var line = "Session: \(pct)"
        if let cd = UsageFormatting.countdown(to: session.resetsAt) {
            line += " (\(cd))"
        }
        parts.append(line)
    }
    print(parts.joined(separator: "  ·  "))
    return 0
}

func runFetch() async -> Int32 {
    do {
        let snapshot = try await OAuthUsageClient().fetch()
        try cache.save(snapshot)
        print(renderSummary(snapshot))
        return 0
    } catch {
        FileHandle.standardError.write(Data("claude-usage: \(error)\n".utf8))
        return 1
    }
}

func runPrint() -> Int32 {
    guard let snapshot = cache.load() else {
        print("No cached usage yet. Run `claude-usage fetch` or open a Claude Code session.")
        return 0
    }
    print(renderSummary(snapshot))
    return 0
}

func renderSummary(_ snapshot: UsageSnapshot) -> String {
    let rows = snapshot.rows()
    guard !rows.isEmpty else { return "No usage data available." }

    var lines = rows.map { row -> String in
        var text = "\(row.title): \(row.percent)"
        if let countdown = row.countdown { text += "  (\(countdown))" }
        if let detail = row.detail { text += "  (\(detail))" }
        return text
    }
    if let freshness = UsageFormatting.freshness(snapshot) {
        lines.append("(\(snapshot.source.displayName), \(freshness))")
    }
    return lines.joined(separator: "\n")
}

func printHelp() {
    print("""
    claude-usage - Claude Code usage helper

    USAGE:
      claude-usage <command>

    COMMANDS:
      statusline   Read status-line JSON on stdin, cache usage, print a status line
      fetch        Poll the OAuth usage endpoint once and update the cache
      print        Print the current cached usage (default)
      help         Show this help

    Set as your Claude Code status line by adding to ~/.claude/settings.json:
      "statusLine": { "type": "command", "command": "claude-usage statusline" }
    """)
}

let command = CommandLine.arguments.dropFirst().first ?? "print"
let status: Int32
switch command {
case "statusline": status = runStatusLine()
case "fetch": status = await runFetch()
case "print": status = runPrint()
case "help", "-h", "--help": printHelp(); status = 0
default:
    FileHandle.standardError.write(Data("Unknown command: \(command)\n".utf8))
    printHelp()
    status = 64 // EX_USAGE
}
exit(status)
