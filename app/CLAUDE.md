# Voice bridge (Android) — Claude instructions

Phone client for the hub in [`../mac`](../mac). Read the root [CLAUDE.md](../CLAUDE.md) first.
Human docs: [README.md](README.md).

## What talks to what

- The hub (Python, on the Mac, `127.0.0.1:8765`, exposed with `tailscale serve`)
  is the source of truth. This app only mirrors it. Its API:
  `GET /events` (SSE: `{"type":"state",sessions,questions}` snapshots and
  `{"type":"message",...}` with `id:` lines; replays after `Last-Event-ID`),
  `POST /api/answer|instruct|status|phone_mode|label|forget`, `GET /api/voices`,
  `GET /audio/<message id>?voice=` (MP3; id 0 = voice sample), `GET /health`.
- A change to the hub's API must be made in both repos; there is no shared schema.
  The hub's own web page (`../mac/voice_bridge/static/index.html`) is the other client.
- The hub decides what is spoken (`say`) and whether a natural voice is possible
  (`natural`, false for non-English). The app never builds spoken text itself.

## Code map

- `lib/logic/bridge_cubit.dart`: one cubit for the whole home screen (connection,
  feed, speaking, notifications, replies, settings). Returns a feedback line from
  every action; the UI shows it in a SnackBar (`run()` in `home_screen.dart`).
  Every action must give success or error feedback.
- `lib/logic/target.dart`: who a reply goes to. Keep it in step with
  `currentTarget()` in the hub's web page.
- `lib/services/alerts.dart`: notifications and the keep-alive foreground service
  (`mediaPlayback` type, no timeout on Android 15). The service handler does
  nothing; it only keeps the process alive. `keepAlive(true)` is called on every
  hub update, so it must stay idempotent (it once re-opened the battery prompt
  over and over).
- `lib/services/speaker.dart`: every playback step has a timeout and `hush()`
  always ends the current one; the web page once got stuck on a paused player.
- `AppDeps` in `app.dart` is the seam for tests; tests use `test/fakes.dart`.

## Gotchas

- `permission_handler` was removed: its Android build needs a newer Kotlin
  Gradle plugin than Flutter 3.35.4 ships. Permissions come from the plugins
  that need them (notifications, speech, battery).
- `flutter_local_notifications` 20 needs core library desugaring (set in
  `android/app/build.gradle.kts`).
- Cleartext HTTP is allowed only to `10.0.2.2` (emulator → Mac) for tests;
  the real hub is HTTPS over Tailscale.
- In a headless emulator, system dialogs sometimes ignore `adb shell input tap`;
  find the button with `uiautomator dump` or press BACK.
