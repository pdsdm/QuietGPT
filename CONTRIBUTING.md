# Contributing to QuietGPT

Thank you for your help. QuietGPT is small on purpose. It rewrites a message with your own rules, in one tap, in any app, and all text stays on your iPhone. This guide tells you which changes fit, how to build the app, and how to send a change so that it can be merged quickly.

## Before you start

For a change that is larger than a fix, open an issue first. Say what you want to do and why. Earlier issues already discuss many ideas. A short discussion prevents work on a change that will not be merged. Small fixes, translations and typo corrections can go directly to a pull request.

## What fits

QuietGPT has one promise: your text does not leave your iPhone. Changes that make the rewrite faster, clearer or more correct, and keep this promise, are the most welcome.

Usually a good fit:

- Fixes, with clear steps to reproduce the problem.
- Keyboard behavior that is the same as the iOS keyboard, for example accents, cursor control and autocorrect rules.
- Better base instructions or styles, tested on a real iPhone.
- Changes that make an existing function clearer or easier to find.
- New languages, and better translations of the current ones.

Usually not a fit:

- Network code of any type: servers, cloud AI, sync, update checks or remote config.
- Analytics, crash reporting, ads or third-party packages.
- Full access for the keyboard. The keyboard works without it, and it must stay that way.
- Other AI systems, or AI weights in the app. QuietGPT uses Apple Foundation Models only.
- An account, a subscription or a paywall.
- Code that saves the text that you type or rewrite, except the chats that you keep.
- More than one unrelated change in one pull request.

When many people ask for something, the answer is usually a more general change that covers all of them. If your idea waits for this, please be patient.

## Building

```sh
git clone https://github.com/pdsdm/QuietGPT.git
cd QuietGPT
open QuietGPT.xcodeproj
```

You need Xcode 26 or later. To run on an iPhone, create `Config/Local.xcconfig` with your team and a bundle prefix that you own. Git ignores this file.

```
DEVELOPMENT_TEAM = YOUR_TEAM_ID
QUIETGPT_BUNDLE_PREFIX = com.yourname.quietgpt
```

Do not use the QuietGPT bundle prefix. Real replies need an iPhone with Apple Intelligence. In the simulator, use the launch argument `-QuietGPTSimulate YES` to get a sample reply. The README has the full list of [requirements](README.md#requirements) and [launch options](README.md#debug-launch-options).

## Sending a change

- One change for each pull request. Small ones get a review and a merge sooner.
- Make sure that all tests pass. Press `Cmd+U`, or run the command in the [README](README.md#tests). The same tests run on each pull request.
- Add tests in `QuietGPTTests`, in the same folder as the code that they test.
- Test on a real iPhone. Say which iPhone and which iOS version. The simulator does not show the real keyboard size or real replies.
- For the keyboard, test it in more than one app, for example Messages and Notes. For a visual change, a short recording helps a lot.
- For a change to instructions or styles, give a few sample texts and the rewrites from before and after the change. The system follows rules literally, and longer instructions can add errors.
- Keep "Allow edits by maintainers" on. I sometimes push a commit on top of your branch to change details. The change still lands as yours.
- Pull requests are merged with a squash. You stay the author. Each person whose idea or code went into it is added as a co-author.

## Text and languages

Each target has a `Localizable.xcstrings` file: `QuietGPT`, `QuietGPTKeyboard` and `QuietGPTShare`. The app speaks English and Spanish now. The Monitor panel stays in English.

- When you add text, add it in all languages. A rough translation is better than none. Say which ones need a review by a native speaker.
- Write short, plain sentences. The app does not use the word "model" in its text.
- A new language is very welcome. Add it to the three `Localizable.xcstrings` files. Make sure that Apple Intelligence supports it.

## Code

- Match the code around your change: its names and its structure.
- No new dependencies. The project has no third-party packages.
- The shared rewrite code is in `Rewrite`. The app, the keyboard and the share card all use it. A change there affects all three.
- Keep the app quiet: no logs of personal data or of the text that people write, and no background work that is not necessary.
- After your change, this command must print nothing:

  ```sh
  grep -rE 'URLSession|import Network|https?://' QuietGPT QuietGPTKeyboard QuietGPTShare Rewrite --include='*.swift'
  ```

## Ports and forks

The code has the MIT License, but the QuietGPT name and icon do not. See the note at the end of [LICENSE](LICENSE). Ports to other platforms and forks are welcome as separate projects with their own name, icon and bundle identifier. I am happy to link to them from the README. They will not be merged into this repository. Do not publish a copy of QuietGPT on the App Store.

## AI tools

You can use them. Read and test what you send as carefully as if you wrote each line. Keep the change as small as the problem needs. Describe how you tested it in your own words.

## Reporting a bug

Use the bug report template. Give your iPhone, your iOS version, the QuietGPT version, the device and Siri language, and the steps to the problem. If QuietGPT shows a message, copy it.

Issues are public. Do not paste private messages, names or other personal data. Use sample text.

## Reporting a privacy problem

If you find a way that text or data leaves the iPhone, do not put the details in a public issue. Open an issue that says only that you found a privacy problem, and I will contact you.
