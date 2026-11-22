# App Review notes

Paste the text below into App Store Connect > App Review Information > Notes.

```
QuietGPT is a private AI chat that runs on the iPhone and works in Airplane Mode. The chat answers with a language engine that is inside the app: the LFM3-1.7B weights by Liquid AI (LFM Open License v1.0), converted to Core ML and run on the Apple Neural Engine. The app download includes these files (about 1.9 GB), so the app downloads nothing after install. The app also has a keyboard that rewrites text in other apps with the on-device Apple Foundation Models framework. It has no account, no server, no ads and no in-app purchases. No demo account is necessary.

DEVICE REQUIREMENT
The app needs iPhone 15 Pro or later with iOS 26 or later (UIRequiredDeviceCapabilities: iphone-performance-gaming-tier), because the chat engine needs the memory of these iPhones. The chat does not need Apple Intelligence. The keyboard rewrites need Apple Intelligence: turn it on in Settings > Apple Intelligence & Siri and wait for its download to finish. Without Apple Intelligence, the keyboard shows a message that explains this, and typing still works.

FIRST LAUNCH
The first time the chat starts, iOS prepares the engine files for the Neural Engine. This takes up to about 1 minute. During this time, the chat answers with Apple Foundation Models if Apple Intelligence is on. Otherwise the reply shows "Setting up on this iPhone" and comes when the setup finishes. Later launches take a few seconds.

HOW TO TEST THE CHAT
1. Open QuietGPT and complete the first launch screens.
2. Open the Chat tab and send a message. The reply streams on the iPhone. The brain button next to the send button turns the thought step on or off. When it is on, a box shows the thought while it is written. Tap the box to see all of it.
3. Turn on Airplane Mode and send another message. The reply still comes.

HOW TO TEST THE KEYBOARD
1. Go to Settings > General > Keyboard > Keyboards > Add New Keyboard and select QuietGPT.
2. Open any app with a text field, for example Notes, and switch to the QuietGPT keyboard with the globe key.
3. Type a message, for example: Can you send me the file by tomorrow? Thanks.
4. Tap the lock key to open the rewrite panel.
5. Select a style, for example Formal. The new text replaces your text.

The keyboard does not ask for full access and does not use the network. It has a key to go to the next keyboard. The lock key and the logo open a panel inside the keyboard. They do not open another app.

OTHER FUNCTIONS
Face ID lock: it is in the Privacy tab, and the first launch screens also offer it. The app locks when it goes to the background.
Style packs: in the Keyboard tab, you can send your rules and styles as a .quietgpt file. Nothing leaves the iPhone until you send the file.
Delete all data: it is in the Privacy tab.

DIAGNOSTIC PANEL
Holding the send button in the chat for 10 seconds opens a small panel with reply speed, CPU, frames, memory, network and thermal state. It shows data only for this iPhone and it does not change how the app works. It sends no data. The public README documents it.

PRIVACY
The app collects no data. The privacy policy link is in the Privacy tab. The source code is public: https://github.com/pdsdm/QuietGPT
```

## Other App Store Connect values

| Field | Value |
|---|---|
| Privacy Policy URL | https://github.com/pdsdm/QuietGPT/blob/main/PRIVACY.md |
| Support URL | https://github.com/pdsdm/QuietGPT/issues |
| App Privacy | Data Not Collected |
| Category | Productivity |
| Price | Free |
| Version | 1.0 |
