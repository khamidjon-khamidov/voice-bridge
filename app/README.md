# Voice bridge (Android)

Talk to your Claude Code sessions from your phone. This app is the phone end of
the hub in [`../mac`](../mac), which every Claude Code session on the Mac reports to.

- Claude's updates and questions are **read aloud** in a natural voice (Kokoro,
  made on the Mac; the phone's own voice is the fallback).
- **Hold to talk** to answer or give Claude a new instruction; it sends when you let go.
- One card per Claude session: **Status**, **Message**, **Phone mode**, rename.
- Keeps listening **with the screen off**: a foreground service (small permanent
  notification) keeps the connection and the voice alive, and a question that
  arrives while the app is in the background shows a notification.

Android only for now. Installed by hand, not on Play.

## Needs

- The hub running on the Mac and served over Tailscale
  (`tailscale serve --bg 8765`), see the voice-bridge repo.
- Tailscale on the phone, signed into the same account.

## Run and build

```bash
fvm install
fvm flutter run                                   # on a device or emulator
fvm flutter build apk --release --split-per-abi   # phone: app-arm64-v8a-release.apk (~19 MB)
```

Release builds are signed with the debug key (personal app). On first start the
app asks for the Mac address, notifications, and to run in the background; the
microphone is asked the first time you hold the talk button.

## Tests

```bash
fvm flutter test        # unit + widget (fakes for hub, speech and notifications)

# End to end on an emulator against a real hub (the emulator reaches the Mac at 10.0.2.2):
VB_PORT=8766 VB_STATE_FILE=/tmp/vb-it.json ~/tools/voice-bridge/mac/.venv/bin/vb-hub &
fvm flutter test integration_test --dart-define=HUB=http://10.0.2.2:8766
```

Running the integration test replaces the debug APK on the emulator and its
saved settings.

## Layout

```
lib/
  main.dart, app.dart        wiring (AppDeps lets tests swap device/network pieces)
  data/                      hub HTTP + Server-Sent Events client, models, preferences
  logic/                     BridgeCubit (everything the home screen does), reply target rules
  services/                  speaker (MP3 + phone TTS fallback), listener (speech_to_text), alerts (notifications + keep-alive service)
  ui/                        setup, home (cards, feed), talk bar, settings sheet
design/mockups/              the hub's web page, which served as the approved design
```
