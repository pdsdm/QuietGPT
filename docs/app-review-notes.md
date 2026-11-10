# App Review notes

Paste the text below into App Store Connect > App Review Information > Notes.

```
QuietGPT is a private AI chat that runs on the iPhone. It answers with the on-device Apple Foundation Models framework and it works in Airplane Mode. In our recorded tests on iPhone 16 Pro Max, chat replies ran on the Apple Neural Engine. iOS selects the hardware. The app also has a keyboard and a share card that use the same on-device AI to rewrite text in other apps. It has no account, no server, no ads, no in-app purchases and no third-party packages. No demo account is necessary.

DEVICE REQUIREMENT
Please test on an iPhone with Apple Intelligence: iPhone 15 Pro, iPhone 15 Pro Max, iPhone Air, iPhone 16 or later, with iOS 26 or later. Turn on Apple Intelligence in Settings > Apple Intelligence & Siri and wait for its download to finish. The device and Siri must use the same supported language.

On an iPhone without Apple Intelligence, the app shows a message that explains this. This is expected behavior, not a crash. Typing with the keyboard still works.

HOW TO TEST THE CHAT
1. Open QuietGPT and complete the first launch screens.
2. Open the Chat tab and send a message. The reply streams on the iPhone.
3. Turn on Airplane Mode and send another message. The reply still comes.

HOW TO TEST THE KEYBOARD
1. Go to Settings > General > Keyboard > Keyboards > Add New Keyboard and select QuietGPT.
2. Open any app with a text field, for example Notes, and switch to the QuietGPT keyboard with the globe key.
3. Type a message, for example: Can you send me the file by tomorrow? Thanks.
4. Tap the lock key to open the rewrite panel.
5. Select a style, for example Formal. The new text replaces your text.

The keyboard does not ask for full access and does not use the network. It has a key to go to the next keyboard. The lock key and the logo open a panel inside the keyboard. They do not open another app.

HOW TO TEST THE SHARE CARD
1. In Notes, select text and tap Share.
2. Select QuietGPT and select a style.

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
