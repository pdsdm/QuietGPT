import SwiftData
import SwiftUI

enum AppTab: String, Hashable {
    case chat
    case chats
    case keyboard
    case privacy
}

struct RootView: View {
    var body: some View {
        ThemedContent()
            .background(TouchCatcher())
    }
}

private struct ThemedContent: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Palette.forScheme(colorScheme)
        AppFlow()
            .environment(\.palette, palette)
            .tint(palette.accent)
            .font(QuietGPTFont.body)
            .animation(Motion.gentle, value: colorScheme)
    }
}

private struct AppFlow: View {
    @AppStorage(SettingsKey.onboarded) private var onboarded = false
    @AppStorage(SettingsKey.lockEnabled) private var lockEnabled = true

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var controller = ChatController()
    @State private var tab: AppTab = .chat
    @State private var locked = true
    @State private var loading = true
    @State private var authenticating = false
    @State private var openedPack: OpenedPack?
    @State private var packFailure: String?
    @State private var packRevision = 0

    private var canShowPack: Bool {
        onboarded && !loading && !(lockEnabled && locked)
    }

    private var visiblePack: Binding<OpenedPack?> {
        Binding(
            get: { canShowPack ? openedPack : nil },
            set: { openedPack = $0 }
        )
    }

    private var visibleFailure: Binding<Bool> {
        Binding(
            get: { canShowPack && packFailure != nil },
            set: { if !$0 { packFailure = nil } }
        )
    }

    private func open(_ url: URL) {
        guard url.isFileURL else { return }
        do {
            openedPack = OpenedPack(pack: try StylePack.read(from: url))
            packFailure = nil
        } catch {
            openedPack = nil
            packFailure = StylePack.message(for: error)
        }
    }

    var body: some View {
        ZStack {
            if onboarded {
                MainTabs(controller: controller, tab: $tab, packRevision: $packRevision)
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
                LockScreen(authenticating: $authenticating) {
                    withAnimation(Motion.gentle) { locked = false }
                }
                .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.96)).combined(with: AnyTransition(.blurReplace)))
                .zIndex(2)
            }

            if scenePhase != .active && onboarded && lockEnabled && !authenticating {
                PrivacyCover()
                    .transition(.opacity)
                    .zIndex(3)
            }

            if loading {
                SplashScreen()
                    .transition(.opacity)
                    .zIndex(4)
            }
        }
        .animation(Motion.gentle, value: onboarded)
        .animation(Motion.gentle, value: locked)
        .animation(.easeInOut(duration: 0.2), value: scenePhase)
        .onOpenURL(perform: open)
        .sheet(item: visiblePack) { opened in
            PackImportScreen(pack: opened.pack) {
                packRevision += 1
                tab = .keyboard
            }
        }
        .alert("Style pack", isPresented: visibleFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(packFailure ?? "")
        }
        .onAppear {
            controller.attach(modelContext)
            #if DEBUG
            DebugLaunch.apply(controller: controller, tab: &tab)
            #endif
        }
        .task {
            try? await Task.sleep(for: reduceMotion ? SplashScreen.shortDuration : SplashScreen.duration)
            withAnimation(.easeOut(duration: 0.45)) { loading = false }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                NetworkWatch.shared.scan()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                KeyboardDismissal.hide()
                controller.stop()
                if lockEnabled {
                    locked = true
                }
            }
        }
    }
}

private struct OpenedPack: Identifiable {
    let id = UUID()
    let pack: StylePack
}

private struct MainTabs: View {
    var controller: ChatController
    @Binding var tab: AppTab
    @Binding var packRevision: Int

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
                    .id(packRevision)
            }
            Tab("Privacy", systemImage: "hand.raised", value: AppTab.privacy) {
                PrivacyScreen(controller: controller) {
                    packRevision += 1
                }
            }
        }
        .tint(palette.text)
        .tabBarMinimizeBehavior(tab == .keyboard ? .never : .onScrollDown)
        .sensoryFeedback(.selection, trigger: tab)
    }
}

private struct PrivacyCover: View {
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            AsciiLock(side: 320, state: .open)
        }
    }
}
