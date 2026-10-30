# Hush

Hush is a private AI chat for iPhone. It runs fully on the device with Apple Foundation Models. There is no account, no cloud and no tracking. It works in airplane mode.

## Requirements

- Xcode 26 or later
- iOS 26 or later
- An iPhone with Apple Intelligence turned on, to get real replies

Without Apple Intelligence, Hush shows a short message that explains how to turn it on.

## Run

1. Open `Hush.xcodeproj`.
2. Select your team in Signing & Capabilities.
3. Run the `Hush` scheme.

Run the tests with `Cmd+U` or:

```sh
xcodebuild test -project Hush.xcodeproj -scheme Hush -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Structure

| Folder | Content |
|---|---|
| `Hush/App` | Root view, tab bar, lock flow, settings keys |
| `Hush/Theme` | Dark and light palettes, type styles, motion |
| `Hush/Field` | The live ASCII background (`FieldEngine`, `AsciiField`) |
| `Hush/Components` | Wordmark, app mark, buttons, chips |
| `Hush/Chat` | Chat screen, composer, message boxes, streaming text, Markdown |
| `Hush/Engine` | `ReplyEngine`, the on-device reply stream |
| `Hush/Data` | SwiftData models |
| `Hush/Screens` | Onboarding, lock, Chats, Voice, Privacy |
| `HushTests` | Unit tests |
| `scripts` | `make-icon.swift` makes the app icon PNGs |

## Debug launch options

Debug builds read these launch arguments:

- `-HushTab chats|voice|privacy` opens a tab.
- `-HushPrompt "text"` sends a message on launch.
- `-HushSimulate YES` streams a sample reply, for the simulator.

## App icon

```sh
swift scripts/make-icon.swift Hush/Assets.xcassets/AppIcon.appiconset
```

## Reply speed and power

Each reply logs its speed in the `chat` category:

```sh
log stream --predicate 'subsystem == "com.pdsdm.hush"' --level info
```

`scripts/power-monitor.c` shows CPU, GPU and Neural Engine power on an Apple Silicon Mac, without `sudo`:

```sh
clang -O2 scripts/power-monitor.c -o power-monitor -framework CoreFoundation -lIOReport
./power-monitor 30
```
