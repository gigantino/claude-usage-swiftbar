# Claude Usage

A lightweight macOS menu bar app that shows your Claude Code usage: session (5h),
weekly (7d), per-model, and extra-credit limits, with live reset countdowns.

Native Swift, no Dock icon, no external dependencies.

## How it gets the data

There is no official usage API, so this app combines the two best sources and
never scrapes the Claude Code TUI:

1. Status line feed (default, free, real-time). While a Claude Code session is
   open, Claude pipes rate-limit data to its status line. The bundled
   `claude-usage` CLI, used as your status line command, caches that data. No API
   calls, no tokens, no Keychain access, and it keeps your context-usage line.
2. OAuth usage endpoint (optional). Polling `api.anthropic.com/api/oauth/usage`
   adds weekly, per-model, and extra-credit figures and refreshes data when no
   session is open. It reads the OAuth token from the Keychain, which prompts for
   consent, so it is off by default. Turn it on from the menu when you want it.

Note on Keychain prompts: Claude Code rewrites its Keychain item whenever it
refreshes the OAuth token, which resets macOS's access list. Enabling polling can
re-prompt for consent after a token refresh. The status-line feed avoids this,
which is why it is the default.

## Requirements

- macOS 13 (Ventura) or later
- [Claude Code](https://www.claude.com/product/claude-code) logged in with a
  Pro/Max (Claude.ai) account. Usage limits aren't exposed for API-key logins.
- Xcode 15+ / Swift toolchain (to build)

## Install

```sh
git clone <this repo> && cd claude-usage-swiftbar
./scripts/build-app.sh
```

This builds `build/ClaudeUsageBar.app` and installs the `claude-usage` CLI to
`~/.local/bin`. Then:

```sh
cp -R build/ClaudeUsageBar.app /Applications/
open /Applications/ClaudeUsageBar.app
```

The first OAuth poll triggers a one-time Keychain prompt. Click Always Allow.

To launch at login: System Settings > General > Login Items > add the app.

### Recommended: enable the free real-time feed

Add the status line command to `~/.claude/settings.json`:

```json
{ "statusLine": { "type": "command", "command": "claude-usage statusline" } }
```

Usage then updates instantly while you work, with zero API calls.

## CLI

`claude-usage` works on its own for scripts and other status bars:

```sh
claude-usage statusline   # read status-line JSON on stdin, cache it, print a line
claude-usage fetch        # poll the OAuth endpoint once and update the cache
claude-usage print        # print the current cached usage
```

## Development

```sh
swift build      # build
swift test       # run the unit tests
swift run ClaudeUsageBar   # run the app from source
```

Architecture:

- `ClaudeUsageCore`: models, status-line/OAuth decoders, Keychain reader, OAuth
  client, cache, formatting (all unit-tested).
- `claude-usage`: the CLI / status line command.
- `ClaudeUsageBar`: the `MenuBarExtra` app.

The cache lives at `~/Library/Application Support/ClaudeUsageBar/usage.json`.
