import SwiftData
import SwiftUI

enum AppTab: String, Hashable {
    case chat
    case chats
    case keyboard
    case voice
    case privacy
}

struct RootView: View {
    @AppStorage(SettingsKey.appearance) private var appearance = Appearance.light

    var body: some View {
        ThemedContent()
            .preferredColorScheme(appearance.colorScheme)
    }
}

private struct ThemedContent: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Palette.forScheme(colorScheme)
        AppFlow()
            .environment(\.palette, palette)
            .tint(palette.accent)
            .animation(Motion.gentle, value: colorScheme)
    }
}

private struct AppFlow: View {
    @AppStorage(SettingsKey.onboarded) private var onboarded = false
    @AppStorage(SettingsKey.lockEnabled) private var lockEnabled = true

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette

    @State private var controller = ChatController()
    @State private var tab: AppTab = .chat
    @State private var locked = true

    var body: some View {
        ZStack {
            if onboarded {
                MainTabs(controller: controller, tab: $tab)
                    .transition(AnyTransition.opacity.combined(with: .scale(scale: 1.04)))
            } else {
                OnboardingScreen { useLock in
                    lockEnabled = useLock
                    locked = false
                    withAnimation(Motion.gentle) { onboarded = true }
                }
                .transition(.opacity.combined(with: AnyTransition(.blurReplace)))
            }

            if onboarded && lockEnabled && locked {
                LockScreen {
                    withAnimation(Motion.gentle) { locked = false }
                }
                .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.96)).combined(with: AnyTransition(.blurReplace)))
                .zIndex(2)
            }

            if scenePhase != .active && onboarded && lockEnabled {
                PrivacyCover()
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        .animation(Motion.gentle, value: onboarded)
        .animation(Motion.gentle, value: locked)
        .animation(.easeInOut(duration: 0.2), value: scenePhase)
        .onAppear {
            controller.attach(modelContext)
            #if DEBUG
            DebugLaunch.apply(controller: controller, tab: &tab)
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, lockEnabled {
                controller.stop()
                locked = true
            }
        }
    }
}

private struct MainTabs: View {
    var controller: ChatController
    @Binding var tab: AppTab

    @Environment(\.palette) private var palette

    var body: some View {
        TabView(selection: $tab) {
            Tab("Chat", systemImage: "bubble.left", value: AppTab.chat) {
                ChatScreen(controller: controller) {
                    tab = .chats
                }
            }
            Tab("Chats", systemImage: "clock", value: AppTab.chats) {
                HistoryScreen(
                    controller: controller,
                    onOpen: { conversation in
                        controller.open(conversation)
                        tab = .chat
                    },
                    onNew: {
                        controller.startNew()
                        tab = .chat
                    }
                )
            }
            Tab("Keyboard", systemImage: "keyboard", value: AppTab.keyboard) {
                KeyboardScreen()
            }
            Tab("Voice", systemImage: "waveform", value: AppTab.voice) {
                VoiceScreen()
            }
            Tab("Privacy", systemImage: "lock.shield", value: AppTab.privacy) {
                PrivacyScreen(controller: controller)
            }
        }
        .tint(palette.text)
        .tabBarMinimizeBehavior(.onScrollDown)
        .sensoryFeedback(.selection, trigger: tab)
    }
}

private struct PrivacyCover: View {
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            AppMark(size: 88)
        }
    }
}
