# voice-bridge

Talk to your [Claude Code](https://claude.com/claude-code) sessions from your
phone. Claude's updates and questions are read aloud in a natural voice; you
answer by holding a button and speaking. Every session on your Mac gets its own
card, and it keeps working with the phone's screen off.

```
 Phone: Android app (app/)  or  web page served by the hub
        │  over Tailscale HTTPS
        ▼
 Mac: hub (mac/)  ── launchd, 127.0.0.1:8765, natural voice (Kokoro)
        ▲   one MCP helper + hook script per Claude Code session
 Claude #1   Claude #2   Claude #3
```

| Folder | What | Docs |
|---|---|---|
| [`mac/`](mac/) | The hub (Python): the phone page, the API, the MCP tools `report` / `ask_user`, the Claude Code hooks, the installer | [mac/README.md](mac/README.md) |
| [`app/`](app/) | The Android app (Flutter): session cards, hold to talk, natural voice, notifications, keeps listening with the screen off | [app/README.md](app/README.md) |

## Quick start

1. **Mac:** `git clone https://github.com/khamidjon-khamidov/voice-bridge ~/tools/voice-bridge && ~/tools/voice-bridge/mac/scripts/install.sh`
2. **Tailscale** on the Mac and the phone, same account, then on the Mac: `tailscale serve --bg 8765`.
3. **Phone:** open the `https://<mac>.<tailnet>.ts.net` address in a browser, or install the app
   (`cd app && fvm flutter build apk --release --split-per-abi`, or download it from the hub at `/download/voice-bridge.apk`).
4. Restart your Claude Code sessions so they load the tools.

## License

MIT
