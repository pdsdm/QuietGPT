#if DEBUG
import Foundation

enum DebugLaunch {
    private static let sampleReply = """
    Here are three small changes that help most people sleep better:

    - **Keep one wake time**, also on weekends.
    - Dim the lights and put the phone away an hour before bed.
    - Keep the room cool, dark and quiet.

    Give it two weeks. Most people notice a change by then.
    """

    private enum Key: String {
        case monitor = "QuietGPTMonitor"
        case focus = "QuietGPTFocus"
        case tab = "QuietGPTTab"
        case simulate = "QuietGPTSimulate"
        case prompt = "QuietGPTPrompt"
    }

    static var opensMonitor: Bool {
        UserDefaults.standard.bool(forKey: Key.monitor.rawValue)
    }

    static var focusesComposer: Bool {
        UserDefaults.standard.bool(forKey: Key.focus.rawValue)
    }

    static func apply(controller: ChatController, tab: inout AppTab) {
        let defaults = UserDefaults.standard
        if let name = defaults.string(forKey: Key.tab.rawValue), let launchTab = AppTab(rawValue: name) {
            tab = launchTab
        }
        if defaults.bool(forKey: Key.simulate.rawValue) {
            controller.simulateReplies(with: sampleReply)
        }
        if let prompt = defaults.string(forKey: Key.prompt.rawValue), !prompt.isEmpty {
            controller.send(prompt)
        }
    }
}
#endif
