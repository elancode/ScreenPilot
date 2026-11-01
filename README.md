# ScreenPilot

ScreenPilot is a macOS menu bar app that watches your screen and offers useful suggestions ("nudges") as you work. It periodically captures the active screen and sends the image to Claude. When there's something worth saying, it shows a nudge:

- **Technical copilot:** explains errors, flags security issues or misconfigurations, points out trends in dashboards, metrics, or billing pages, and surfaces non-obvious tips in docs and settings.
- **Task assistant:** when you're writing something (a reply, a review, a ticket), it drafts copy-pasteable content for you.

You can ask follow-up questions about any nudge. ScreenPilot answers using the screenshot that produced it.

## Features

- **Menu bar only:** there's no Dock icon (`LSUIElement`). A dropdown shows the nudge feed, and an overlay panel shows new nudges.
- **Smart capture scheduling:**
  - pauses after 2 minutes without keyboard or mouse input
  - skips frames that look nearly the same as the last one sent (image diff)
  - waits at least 5 seconds between API calls
  - backs off to once a minute after 3 "nothing to say" responses in a row
- **App blocklist:** never captures password managers or Keychain Access (1Password, LastPass, Keychain Access by default). You can add more bundle IDs in Settings.
- **Daily budget:** caps API calls per day (default 500). The counter resets at midnight.
- **Deduplication:** recent nudges are sent back to the model so it doesn't repeat itself.
- **Long-term memory:** activities, nudges, and your feedback on them go into a local SQLite FTS5 store. Relevant past context is used to improve a nudge in a second pass. Entries older than 90 days are deleted.
- **Markdown rendering** in nudge cards.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16
- An [Anthropic API key](https://console.anthropic.com/)
- Optional: [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.40+ if you change `project.yml`

## Building

The Xcode project is generated from `project.yml` and committed to the repo. After editing `project.yml`, regenerate it:

```bash
xcodegen generate
```

Then open the project in Xcode and run the `ScreenPilot` scheme:

```bash
open ScreenPilot.xcodeproj
```

Signing is set to manual with a **Developer ID Application** identity and team `HN2BGT46R6`. If you're building on a machine without that certificate, change the team or switch to automatic signing in Xcode (or in `project.yml`) for local development.

### Tests

```bash
xcodebuild test -project ScreenPilot.xcodeproj -scheme ScreenPilot
```

### Release build

`scripts/build-release.sh` archives, exports, notarizes, and staples the app, then packages a signed DMG into `build/`:

```bash
./scripts/build-release.sh
```

Notarization uses a stored notarytool keychain profile, which defaults to `ScreenPilot` (override it with `NOTARY_PROFILE`). Create the profile once:

```bash
xcrun notarytool store-credentials "ScreenPilot" --apple-id YOUR_APPLE_ID --team-id HN2BGT46R6
```

If notarization fails, the script warns you and builds an un-notarized DMG anyway.

## First run

1. Launch ScreenPilot. It appears in the menu bar.
2. Grant **Screen Recording** permission when macOS asks (System Settings → Privacy & Security → Screen Recording). You may need to relaunch afterward.
3. Open **Settings** from the dropdown and paste your Anthropic API key.
4. Optionally adjust the daily budget, the model (default `claude-sonnet-4-6`), and the app blocklist.

## Privacy and data

- Screenshots go only to the Anthropic Messages API, using your own key. They are not written to disk, although the most recent ones are kept in memory so you can ask follow-up questions.
- Your API key is stored in the macOS Keychain.
- Settings, activity history, and memory are stored locally in `~/Library/Application Support/ScreenPilot/`.
- Blocklisted apps are never captured.
- The app runs without the App Sandbox (it needs screen capture and window-title access) but with the Hardened Runtime enabled.

## Project layout

```
ScreenPilot/
  App/            # App entry, AppDelegate wiring, AppState, notifications
  Capture/        # ScreenCaptureKit capture, scheduler, image diff, input & window tracking
  Intelligence/   # Anthropic client, prompts, response parsing, routing, context window
  Memory/         # Long-term memory (SQLite FTS5) writer, store, maintenance
  MenuBar/        # Status bar controller and SwiftUI views (feed, cards, overlay, settings)
  Models/         # Nudge, ActivityEntry, FollowUp, AnalysisResult, CaptureDecision
  Storage/        # SQLite database and Keychain helper
ScreenPilotTests/ # Unit tests (image diff, nudge parser)
scripts/          # Release build script
project.yml       # XcodeGen spec
```
