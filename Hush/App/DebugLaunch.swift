#if DEBUG
import Foundation

enum DebugLaunch {
    private static let sampleReply = """
    Here are three small changes that help most people sleep better:

    - **Keep one wake time**, also on weekends.
    - Dim the lights and put the phone away an hour before bed.
    - Keep the room cool, dark and quiet.

    And the line of Swift you asked for:

    ```swift
    let bedtime = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: .now)
    ```
    """

    static func apply(controller: ChatController, tab: inout AppTab) {
        let defaults = UserDefaults.standard
        switch defaults.string(forKey: "HushTab") {
        case "chats": tab = .chats
        case "voice": tab = .voice
        case "privacy": tab = .privacy
        default: break
        }
        if defaults.bool(forKey: "HushSimulate") {
            controller.simulateReplies(with: sampleReply)
        }
        if let prompt = defaults.string(forKey: "HushPrompt"), !prompt.isEmpty {
            controller.send(prompt)
        }
    }
}
#endif
