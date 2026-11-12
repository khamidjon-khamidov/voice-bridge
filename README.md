# voice-bridge

Talk to your [Claude Code](https://claude.com/claude-code) sessions from your phone.
Claude's updates and questions are read aloud on a phone web page. You answer by
holding a button and speaking (or by typing), and every session on your Mac gets
its own card.

```
 Phone (Safari/Chrome over Tailscale HTTPS)
        │  live updates in, answers out
        ▼
 ┌──────────────────────────────┐
 │  hub  (vb-hub, launchd)      │  phone page + API + session list
 │  127.0.0.1:8765              │
 └──────────────────────────────┘
     ▲            ▲            ▲   local HTTP
 [vb-mcp]     [vb-mcp]     [vb-mcp]   stdio MCP helper, one per session
 [vb-hook]    [vb-hook]    [vb-hook]  hook script, runs on Claude's events
     ▲            ▲            ▲
 Claude #1    Claude #2    Claude #3
```

- **`report(message)`**: Claude sends a short update; the phone speaks it. Doesn't wait.
- **`ask_user(question)`**: Claude asks; the phone speaks it and **waits** for your
  answer (15 min, then Claude falls back to its judgment or the terminal). If no phone
  is connected it returns at once, so Claude never hangs on an empty room.
- **Status**: per session or for all. A working session gets told on its next
  tool call to `report` a one-sentence summary; an idle one is answered from its
  last update without bothering Claude.
- **Message**: send Claude a new instruction. A working session gets it on its
  next tool call; an idle one gets it with your next prompt, or right away in
  phone mode.
- **Phone mode** (per session, off by default): when Claude finishes, it waits
  (up to 30 min) for your next instruction from the phone instead of stopping, so
  you can keep a session going hands-free. While it waits the terminal looks busy;
  press `Esc` there to take it back.
- **Needs you at the terminal**: permission prompts are announced on the phone.
  You can't approve them from the phone.

### How sessions are told apart

Each Claude Code process starts its own `vb-mcp` helper and runs `vb-hook` on its
events. Both find their parent Claude process and use its PID and start time as
the session key, so a helper and its hooks always land on the same card. Cards
are named `folder · branch` (tap the name to rename) and show the
`claude --resume <id>` command. When a Claude process exits, its card greys out
and disappears after an hour.

## Install

Requirements: macOS, [uv](https://docs.astral.sh/uv/), Claude Code, and
[Tailscale](https://tailscale.com) on the Mac and the phone (free personal plan).

```bash
git clone https://github.com/khamidjon-khamidov/voice-bridge ~/tools/voice-bridge
~/tools/voice-bridge/scripts/install.sh
```

`install.sh` is safe to run again. It:

1. installs dependencies (`uv sync`; uv fetches Python 3.12 if needed);
2. starts the hub as a launchd agent (`com.voicebridge.hub`, starts at login, restarts if it dies), listening on `127.0.0.1:8765` only;
3. adds hooks, `MCP_TOOL_TIMEOUT` and tool permissions to `~/.claude/settings.json` (backup: `settings.json.bak-voice-bridge`);
4. adds the rules in [`CLAUDE_RULES.md`](CLAUDE_RULES.md) to `~/.claude/CLAUDE.md` between marker comments;
5. registers the MCP server for every project:

   ```bash
   claude mcp add -s user voice-bridge -- ~/tools/voice-bridge/.venv/bin/vb-mcp
   ```

Restart running Claude Code sessions afterwards.

### Reach it from your phone

```bash
tailscale serve --bg 8765
```

Open the `https://<your-mac>.<tailnet>.ts.net` address it prints on the phone.
In the Tailscale admin console, turn on **DNS → HTTPS Certificates** first if it
asks. HTTPS isn't optional: phone browsers only allow the microphone on secure
pages. Tailscale also keeps the page private to your own devices, and the hub
never listens on your Wi-Fi or the internet.

On iPhone: tap **Start** once (iOS only lets a page speak after a tap), allow the
microphone the first time you hold the talk button, and use Share → Add to Home
Screen for a full-screen app.

## Using it

- **Waiting for you** lists open questions, oldest first. The bar at the bottom
  says who you're answering; tap a question or a session's **Message** to change it.
- **Hold to talk**: speak, release, check the text, then **Send**. Tick
  *Send voice right away* to skip the check. Choose the speech language next to it.
- Spoken messages start with the session name, so you know who's talking.
- **🔊 / 🔇** mutes speech on this phone.

### Limits

- The phone only speaks while the page is open and the screen is on. Messages
  that arrive while it's locked appear when you open it again; they aren't read
  aloud then.
- Status reaches a working Claude on its next tool call; during one long command
  (a 10-minute build) it waits for that to finish.
- History is kept in memory; restarting the hub clears it.

## Configuration

Environment variables, set in the launchd plist (`~/Library/LaunchAgents/com.voicebridge.hub.plist`) for the hub:

| Variable | Default | Meaning |
|---|---|---|
| `VB_PORT` | `8765` | Hub port (`VB_PORT=… scripts/install.sh` writes it into the plist) |
| `VB_ASK_TIMEOUT` | `900` | Seconds `ask_user` waits for an answer |
| `VB_PHONE_MODE_WAIT` | `1800` | Seconds a finished session waits for a phone instruction in phone mode |
| `VB_HUB_URL` | `http://127.0.0.1:8765` | Where the helper and hooks find the hub |

If you raise `VB_ASK_TIMEOUT` above 20 minutes, raise `MCP_TOOL_TIMEOUT` (ms) in
`~/.claude/settings.json` too. If you raise `VB_PHONE_MODE_WAIT` above ~59
minutes, raise the Stop hook's `timeout` there as well.

## Troubleshooting

- `curl http://127.0.0.1:8765/health` shows whether the hub is up.
- Hub log: `~/Library/Logs/voice-bridge/hub.log`. Restart it with
  `launchctl kickstart -k gui/$(id -u)/com.voicebridge.hub`.
- `claude mcp list` should show `voice-bridge` as connected.
- The hooks fail open: if the hub is down, Claude Code works exactly as before.
- Red dot on the page means the live connection dropped; it reconnects by itself.
- "Voice needs HTTPS": you opened the page over plain `http://`. Use the `tailscale serve` address.

## Uninstall

```bash
~/tools/voice-bridge/scripts/uninstall.sh
tailscale serve reset   # if you don't use serve for anything else
```

## Files

```
voice_bridge/hub.py             hub: phone page, API, session registry
voice_bridge/helper.py          MCP server (FastMCP, stdio): report, ask_user
voice_bridge/hook.py            hook script for SessionStart/UserPromptSubmit/PostToolUse/Notification/Stop/SessionEnd
voice_bridge/common.py          finds the parent Claude process (session key)
voice_bridge/static/index.html  phone page
scripts/install.sh, uninstall.sh, configure_claude.py
CLAUDE_RULES.md                 rules added to ~/.claude/CLAUDE.md
```

## License

MIT
