# voice-bridge — Claude instructions (root)

Two parts in one repo: the hub on the Mac ([`mac/`](mac/)) and the Android app
([`app/`](app/)). Human overview: [README.md](README.md). App-specific notes:
[app/CLAUDE.md](app/CLAUDE.md). This machine's and phone's details (addresses,
pairing, what is installed where) are in `CLAUDE.local.md`, which is git-ignored
because this repo is **public**: never move those details into tracked files.

## How it fits together

- **Hub** (`mac/voice_bridge/hub.py`): Starlette app on `127.0.0.1:8765`, run by launchd
  (`com.voicebridge.hub`), exposed to the phone with `tailscale serve --bg 8765`.
  In-memory sessions, questions and message history; phone mode and custom names
  persist in `~/Library/Application Support/voice-bridge/state.json`.
- **Per Claude session**: `vb-mcp` (stdio FastMCP helper: `report`, `ask_user`) and
  `vb-hook` (SessionStart, UserPromptSubmit, PostToolUse, Notification, Stop,
  SessionEnd). Both find their parent Claude process; its PID + start time is the
  session key. The native Claude binary shows up as a version number, so match
  on argv[0] == "claude" or the `/claude/versions/` path.
- **Phone mode**: the Stop hook waits (30 min) for a phone instruction and returns
  `decision: block` with it. Switches on when the user messages or answers from
  the phone, off when they type a terminal prompt (unless that prompt is just
  carrying queued phone messages). A finished session can't be woken from outside.
- **Natural voice**: Kokoro (kokoro-onnx, model in
  `~/Library/Application Support/voice-bridge/models`, ~340 MB) makes an MP3 per
  message on demand (`/audio/<id>?voice=`, id 0 = sample). Non-Latin text gets
  `natural: false` and the phone's own voice.
- **Clients**: `mac/voice_bridge/static/index.html` (web page) and `app/` (Flutter).
  Both mirror the hub's API; there is no shared schema, so an API change touches
  the hub, the page and the app. Reply-target rules exist in both clients.
- **Downloads**: the hub serves `*.apk` from
  `~/Library/Application Support/voice-bridge/downloads` at `/download/<name>`.

## Paths and running services

- launchd, the hooks in `~/.claude/settings.json` and the MCP registration point at
  `~/tools/voice-bridge/.venv/bin/vb-*`. Since the move into `mac/`, that `.venv`
  is a **symlink to `mac/.venv`**, so they keep working. Rerunning
  `mac/scripts/install.sh` rewrites them to `mac/.venv` directly; the symlink can go after that.
- After changing hub code: `launchctl kickstart -k gui/$(id -u)/com.voicebridge.hub`.
  The web page is served fresh on reload; the MCP helper and hooks run new code
  in new sessions / on the next hook call.
- Logs: `~/Library/Logs/voice-bridge/hub.log` (audio sends are logged there).
- Test the hub without touching the live one: `VB_PORT=8766 VB_STATE_FILE=<tmp> mac/.venv/bin/vb-hub`.

## Conventions

- Hub: Python 3.12 via uv (`cd mac && uv sync`). The `mcp` package v2 renamed
  FastMCP; this uses the standalone `fastmcp` package.
- App: Flutter via FVM (`app/.fvmrc`, always `fvm flutter ...`). Every change
  ships with tests; run `fvm flutter analyze`, `fvm flutter test`, and the
  integration test on an emulator against a test hub (see app/README.md), and
  report real results.
- Every user action in either client gets success or error feedback.
- Spoken text stays short and plain (no code, paths or markdown). The hub decides
  what is said (`say`); clients don't build spoken text.
- Pushing to GitHub publishes (public repo): only with the user's explicit yes.
- The global rules Claude follows when the phone is connected live in
  `mac/CLAUDE_RULES.md`; the installer copies them into `~/.claude/CLAUDE.md`
  between marker comments. Edit both, or rerun `mac/scripts/configure_claude.py`.

## Getting a build onto the phone

Build `cd app && fvm flutter build apk --release --split-per-abi`, then either:
- install over wireless ADB through Tailscale (pairing details in `CLAUDE.local.md`), or
- copy `app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` to the downloads
  folder as `voice-bridge.apk` and open `/download/voice-bridge.apk` on the phone.
