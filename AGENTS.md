# Repository Guidelines

## Project Structure & Module Organization

This is a Swift Package Manager macOS menu bar app. The executable target lives under `Sources/HushMic/`.

- `Sources/HushMic/App/`: app entry point and process setup.
- `Sources/HushMic/Views/`: SwiftUI menu/status UI.
- `Sources/HushMic/Services/`: CoreAudio monitoring, playback control, permissions, launch-at-login, and shared app state.
- `Sources/HushMic/Models/`: small data types such as microphone snapshots.
- `script/build_and_run.sh`: builds, bundles, launches, and verifies the app.
- `dist/` and `.build/` are generated outputs and should not be treated as source.

Keep related feature code close together. Avoid new abstraction layers unless they remove real duplication or make a user-facing behavior easier to change.

## Build, Test, and Development Commands

- `swift build`: compile the SwiftPM executable target.
- `./script/build_and_run.sh`: build, package, and open `dist/HushMic.app`.
- `./script/build_and_run.sh --verify`: launch the packaged app and confirm the process starts.
- `./script/build_and_run.sh --logs`: open the app and stream process logs.
- `./script/build_and_run.sh --telemetry`: stream logs for subsystem `com.location.HushMic`.
- `./script/build_and_run.sh --debug`: run the packaged binary under `lldb`.

Use the script when testing launch-at-login or permission behavior, because those flows depend on the `.app` bundle.

## Coding Style & Naming Conventions

Follow the existing Swift style: 2-space indentation in `Package.swift`, type names in `UpperCamelCase`, and methods/properties in `lowerCamelCase`. Prefer small service types with direct responsibilities. Name files after their main type, for example `MicrophoneMonitor.swift` or `LaunchAtLoginService.swift`.

Keep UI wrappers minimal. Each `View`, `VStack`, `Group`, or helper type should have a concrete layout or state reason to exist.

## Testing Guidelines

There is currently no `Tests/` target. For behavior changes, at minimum run `swift build` and `./script/build_and_run.sh --verify`. For microphone, accessibility, media playback, or launch-at-login changes, also test manually from the packaged app and note permission prompts.

If adding tests, create `Tests/HushMicTests/` and keep test names behavior-focused, such as `testRestoresOnlyPlaybackPausedByApp`.

## Commit & Pull Request Guidelines

Recent history uses very short messages, but new commits should be descriptive and imperative, for example `Fix playback restore state tracking`. Keep each commit focused on one behavior.

Pull requests should include a short summary, verification commands, and screenshots or recordings for visible menu/UI changes. Mention permission-sensitive flows, especially Accessibility, Automation prompts for Music/Spotify, and launch-at-login registration.

## Security & Configuration Tips

Do not hard-code user-specific paths, Apple IDs, signing identities, or private automation data. The bundle identifier is currently local: `com.location.HushMic`. Revisit it before distribution or notarization.
