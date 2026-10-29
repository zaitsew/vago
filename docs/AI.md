# Vago with AI tools

Vago has no server, so its AI integration is local: App Intents on the iPhone and a read-only
MCP server on the Mac. Both answer from the numbers the apps already keep. Nothing leaves the
devices, and the MCP server cannot change anything.

## iPhone: App Intents and Shortcuts

| Intent | Says | Changes state |
|---|---|---|
| Get Today's Focus | "😐 15 of 30 min on procrastination, 15 min left. 90 min of work, 25 min of focus." | no |
| Get Daily Limit | "Your limit today is 30 minutes. 15 used, 15 left." Returns the limit as a number. | no |
| Start Focus Block (25 or 50 min) | starts a block, pauses distracting apps | yes: starts a block |
| Stop Focus Block | gives up the block, lifts the pause; the tree wilts, focus time so far counts | yes: stops the block |

Siri and Spotlight offer them with no setup: "How focused am I in Vago", "My limit in Vago",
"Start focus in Vago", "Stop focus in Vago". In Shortcuts they are actions, so they chain into
automations (start a block when a Focus mode turns on).

- The intents run in the app's process, without opening it. Reads publish this iPhone's day, pull
  the Mac's from iCloud and roll the limit first, as the app does on foreground.
- Start needs Screen Time access (granted in onboarding). Without it the intent says so.
- Starting a block from Siri cannot start the Live Activity (the system allows that only in the
  foreground). The widget reloads; the Live Activity catches up when the app opens.
- Source: `iOS/App/Intents/`. The Focus tab calls the same `FocusControl`.

## Mac: read-only MCP server

`vago-mcp` reads `~/Library/Application Support/Vago/state.json`, the file the menu-bar app
writes, and speaks MCP over stdio. It needs the Mac app to have run, not to be running; the answer
says when the numbers were last updated.

| Tool | Returns |
|---|---|
| `get_today` | minutes of procrastination, work and focus today across devices, the daily limit, minutes left, mood, which devices reported, last update |
| `get_week` | the last seven days (today included): per-day minutes, averages over tracked days, best and worst day, days at or under the 30-minute target |

Both are marked read-only (`readOnlyHint: true`, `destructiveHint: false`,
`openWorldHint: false`) and take no arguments. The server opens one file for reading and writes
nothing. It returns minutes only: no app names, window titles, URLs, rules or goals (it decodes
only the ledger, the limit and the running focus block from the file).

The iPhone's numbers appear after iCloud syncs them to the Mac. A focus block started on the iPhone
is not visible to the Mac's file; the tools report a block running on the Mac only.

### Install

```bash
scripts/install-mcp.sh                       # builds, copies to ~/.local/bin/vago-mcp
claude mcp add vago -- ~/.local/bin/vago-mcp # Claude Code
codex mcp add vago -- ~/.local/bin/vago-mcp  # Codex
```

Then ask: "How focused was I today?" or "How was my week with Vago?".

Check it by hand:

```bash
vago-mcp today                         # the same text a tool call returns
vago-mcp week
vago-mcp --state ./state.json today    # another file; $VAGO_STATE works too
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | vago-mcp
```

Source: `Sources/vago-mcp` (the CLI) and `Sources/VagoKit` (`StateFile`, `MCPServer`, `Summary`),
tested by `swift test`.

## Privacy

No new network calls and no new data collection. The intents read the App Group the app already
keeps; the MCP server reads a local file and answers the program that launched it. Whether a
chat client keeps the answer is that client's setting. `PrivacyInfo.xcprivacy` is unchanged.

## Directories

Not submitted anywhere, and not meant for a directory: a local MCP over a personal file is for the
owner's own Claude Code and Codex. The App Store listing never names an AI assistant (POLICY §15).
