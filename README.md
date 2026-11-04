# QuietGPT

![iOS 26+](https://img.shields.io/badge/iOS-26%2B-black?logo=apple)
![License: MIT](https://img.shields.io/badge/License-MIT-blue)
![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-UI-0D96F6?logo=swift&logoColor=white)
![SwiftData](https://img.shields.io/badge/SwiftData-storage-5E5CE6?logo=swift&logoColor=white)
![Xcode 26+](https://img.shields.io/badge/Xcode-26%2B-147EFB?logo=xcode&logoColor=white)
![Apple Foundation Models](https://img.shields.io/badge/Apple-Foundation%20Models-000000?logo=apple&logoColor=white)
![Platform](https://img.shields.io/badge/platform-iPhone-lightgrey?logo=apple)
![On device](https://img.shields.io/badge/runs-on%20device-2ea44f)
![Works offline](https://img.shields.io/badge/works-offline-2ea44f)
![No tracking](https://img.shields.io/badge/tracking-none-2ea44f)
![Last commit](https://img.shields.io/github/last-commit/pdsdm/QuietGPT?logo=github)

QuietGPT rewrites your messages with your own rules, in one tap, in any app. It has a keyboard, a share card and a private chat. It runs fully on the device with Apple Foundation Models. There is no account, no cloud and no tracking. It works in airplane mode.

<p align="center">
  <img src="docs/screenshots/onboarding.png" width="200" alt="Onboarding">
  <img src="docs/screenshots/keyboard.png" width="200" alt="Keyboard tab with the panel preview, rules and people">
  <img src="docs/screenshots/chat.png" width="200" alt="Chat">
  <img src="docs/screenshots/privacy.png" width="200" alt="Privacy">
</p>

## Features

- **QuietGPT keyboard.** A keyboard that looks and types like the iOS keyboard. Its panel rewrites your text in any app.
- **My rules.** Up to 10 short rules that QuietGPT follows in each rewrite. Each style can turn them off. Fix and the translations do not use them by default.
- **People.** Save how you write to one person. People show first in the panel.
- **Styles.** Kinder, Shorter, Longer, Formal, Fix, English, Spanish, or your own instruction. Edit, add and order them in the Keyboard tab, and change the base instructions.
- **Style packs.** Send your rules and styles as a `.quietgpt` file. Open a file to read it and add it. People are not shared.
- **Share extension.** Share text from any app to QuietGPT and get a rewrite.
- **Private chat.** Replies stream on the device. Markdown, lists and code blocks show with their own styles.
- **Chats.** SwiftData keeps your chats on the iPhone. You can search them.
- **Face ID lock.** QuietGPT locks when it goes to the background.
- **Privacy screen.** It shows the bytes that your chats send. The value is always `0 B`.
- **Monitor panel.** Reply speed, CPU, frames, memory, network and thermal state.
- **Dark and light themes** with a live ASCII background.

## Requirements

- Xcode 26 or later
- iOS 26 or later
- An iPhone with Apple Intelligence turned on, to get real replies

Without Apple Intelligence, QuietGPT shows a short message that explains how to turn it on.

## Run

1. Open `QuietGPT.xcodeproj`.
2. To use your own team, create `Config/Local.xcconfig` with `DEVELOPMENT_TEAM` and `QUIETGPT_BUNDLE_PREFIX`. It overrides `Config/Base.xcconfig` and git ignores it.
3. Run the `QuietGPT` scheme.

Run the tests with `Cmd+U` or:

```sh
xcodebuild test -project QuietGPT.xcodeproj -scheme QuietGPT -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### Turn on the keyboard

Go to Settings > General > Keyboard > Keyboards > Add New Keyboard and select QuietGPT. The keyboard does not ask for full access.

## Structure

| Folder | Content |
|---|---|
| `QuietGPT/App` | App entry, root view, tab bar, lock flow, settings keys, debug launch options |
| `QuietGPT/Features/Chat` | Chat screen, chat controller, composer, streaming text |
| `QuietGPT/Features/Chat/Messages` | Message boxes, Markdown view, code blocks |
| `QuietGPT/Features/History` | Chats list |
| `QuietGPT/Features/Voice` | Voice tab |
| `QuietGPT/Features/Privacy` | Privacy tab |
| `QuietGPT/Features/Keyboard` | Keyboard settings |
| `QuietGPT/Features/Onboarding` | First launch screens |
| `QuietGPT/Features/Lock` | Lock screen |
| `QuietGPT/Features/Monitor` | Monitor panel, system sampler, frame meter |
| `QuietGPT/Core/Reply` | `ReplyEngine`, the on-device reply stream, and reply metrics |
| `QuietGPT/Core/Persistence` | SwiftData models (`Conversation`, `Message`) |
| `QuietGPT/Core/Markdown` | Markdown block parser |
| `QuietGPT/DesignSystem/Theme` | Dark and light palettes, appearance, type styles, motion |
| `QuietGPT/DesignSystem/Components` | Wordmark, app mark, live dot, button styles, chips |
| `QuietGPT/DesignSystem/Field` | The live ASCII background (`FieldEngine`, `AsciiField`) |
| `QuietGPT/Resources` | Asset catalog with the app icon and accent color |
| `Rewrite` | `Rewriter`, styles and keyboard colors, shared by the app, the keyboard and the share extension |
| `QuietGPTKeyboard` | The QuietGPT keyboard extension |
| `QuietGPTShare` | The share extension with the rewrite card |
| `Config` | Entitlements for all targets, Info.plist files for the extensions |
| `QuietGPTTests` | Unit tests, in the same folders as `QuietGPT` |
| `scripts` | App icon generator and power monitor |
| `docs/screenshots` | Screenshots for this file |

## Debug launch options

Debug builds read these launch arguments:

- `-QuietGPTTab chats|voice|privacy` opens a tab.
- `-QuietGPTPrompt "text"` sends a message on launch.
- `-QuietGPTSimulate YES` streams a sample reply, for the simulator.
- `-QuietGPTMonitor YES` opens the monitor panel.

## App icon

```sh
swift scripts/make-icon.swift QuietGPT/Resources/Assets.xcassets/AppIcon.appiconset
```

## Reply speed and power

Hold the send button for 10 seconds to open the monitor panel above the input box. It shows Neural Engine reply speed, CPU, interface frames, memory, network and thermal state.

Each reply logs its speed in the `chat` category:

```sh
log stream --predicate 'subsystem == "com.pdsdm.hush"' --level info
```

`scripts/power-monitor.c` shows CPU, GPU and Neural Engine power on an Apple Silicon Mac, without `sudo`:

```sh
clang -O2 scripts/power-monitor.c -o power-monitor -framework CoreFoundation -lIOReport
./power-monitor 30
```

## License

QuietGPT is available under the MIT License. See [LICENSE](LICENSE).
