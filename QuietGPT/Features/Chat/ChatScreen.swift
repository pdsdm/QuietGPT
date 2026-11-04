import SwiftUI

struct ChatScreen: View {
    @Bindable var controller: ChatController
    var onShowChats: () -> Void

    @Environment(\.palette) private var palette
    @State private var greeted = false
    @State private var monitorShown = false
    @ScaledMetric(relativeTo: .largeTitle) private var greetingSize: CGFloat = 64

    private static let ideas: [(title: String, prompt: String)] = [
        (String(localized: "Help me write a message"), String(localized: "Help me write a short, kind message to a friend I have not talked to in a while.")),
        (String(localized: "Summarize a long text"), String(localized: "I will paste a long text. Summarize it in five short points.")),
        (String(localized: "Think a decision through"), String(localized: "Help me think through a decision. Ask me one question at a time."))
    ]

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            LiquidField(
                mode: controller.isResponding ? .think : .drift,
                mask: controller.hasConversation ? .fadeUp : .fadeDown
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if controller.hasConversation {
                    conversation
                        .contentShape(.rect)
                        .onTapGesture(perform: hideKeyboard)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    welcome
                        .contentShape(.rect)
                        .onTapGesture(perform: hideKeyboard)
                        .transition(.blurReplace)
                }
                footer
            }
        }
        .animation(Motion.spring, value: controller.hasConversation)
        .animation(Motion.gentle, value: controller.isResponding)
        .animation(Motion.spring, value: monitorShown)
        #if DEBUG
        .onAppear {
            if DebugLaunch.opensMonitor { monitorShown = true }
        }
        #endif
        .toolbarVisibility(controller.hasConversation ? .hidden : .visible, for: .tabBar)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: controller.completedReplies)
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    @ViewBuilder
    private var header: some View {
        if controller.hasConversation, let conversation = controller.conversation {
            HStack {
                Button(action: onShowChats) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(CircleIconButtonStyle())
                .accessibilityLabel("Chats")

                Spacer()

                VStack(spacing: 2) {
                    Text(conversation.title)
                        .font(QuietGPTFont.subheadline)
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        LiveDot(color: palette.local, size: 5)
                        Text("on this iPhone")
                    }
                    .font(QuietGPTFont.caption)
                    .foregroundStyle(palette.text2)
                }
                .transition(.blurReplace)

                Spacer()

                Button {
                    controller.startNew()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(CircleIconButtonStyle())
                .accessibilityLabel("New chat")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Text("What is on")
                .opacity(greeted ? 1 : 0)
                .blur(radius: greeted ? 0 : 8)
                .offset(y: greeted ? 0 : 12)
            Text("your mind?")
                .opacity(greeted ? 1 : 0)
                .blur(radius: greeted ? 0 : 8)
                .offset(y: greeted ? 0 : 12)
                .animation(Motion.gentle.delay(0.12), value: greeted)
        }
        .font(BrandFont.font(size: greetingSize))
        .tracking(-greetingSize * 0.025)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .foregroundStyle(palette.text)
        .animation(Motion.gentle, value: greeted)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(Self.ideas.enumerated()), id: \.offset) { index, idea in
                        Button {
                            controller.send(idea.prompt)
                        } label: {
                            Text(idea.title)
                                .font(QuietGPTFont.subheadline)
                                .foregroundStyle(palette.text)
                                .padding(.horizontal, 14)
                                .frame(height: 44)
                                .background(palette.background, in: .capsule)
                                .overlay {
                                    Capsule().strokeBorder(palette.line, lineWidth: 1)
                                }
                                .contentShape(.capsule)
                        }
                        .buttonStyle(PressableStyle(scale: 0.96))
                        .opacity(greeted ? 1 : 0)
                        .offset(y: greeted ? 0 : 16)
                        .animation(Motion.gentle.delay(0.25 + Double(index) * 0.07), value: greeted)
                    }
                }
                .padding(.horizontal, 12)
            }
            .scrollIndicators(.hidden)
            .padding(.bottom, 10)
        }
        .onAppear { greeted = true }
        .onDisappear { greeted = false }
    }

    private var conversation: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if let conversation = controller.conversation {
                    let messages = conversation.orderedMessages
                    let lastAssistant = messages.last(where: { $0.role == .assistant })?.id
                    ForEach(messages) { message in
                        Group {
                            switch message.role {
                            case .user:
                                UserBubble(text: message.text)
                            case .assistant:
                                AssistantMessage(
                                    text: message.text,
                                    isLatest: message.id == lastAssistant && !controller.isResponding,
                                    onRegenerate: controller.regenerate
                                )
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: message.role == .user ? .bottomTrailing : .bottomLeading)),
                            removal: .opacity
                        ))
                    }
                }
                if controller.isResponding {
                    StreamingMessage(text: controller.streamingText, isThinking: controller.phase == .thinking)
                        .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: .bottomLeading)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .animation(Motion.spring, value: controller.conversation?.messages.count)
            .animation(Motion.spring, value: controller.isResponding)
        }
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if monitorShown {
                MonitorPanel(controller: controller) {
                    monitorShown = false
                }
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: AnyTransition(.blurReplace)))
            }
            if controller.isResponding {
                Text("thinking on this iPhone · \(NetworkMeter.format(NetworkWatch.shared.total.sentBytes)) sent")
                    .font(QuietGPTFont.monoSmall)
                    .foregroundStyle(palette.text3)
                    .transition(.blurReplace)
            }
            Composer(
                text: $controller.draft,
                placeholder: controller.hasConversation ? "Reply" : "Ask anything. It stays here.",
                isResponding: controller.isResponding,
                canSend: controller.canSend,
                onSend: { controller.send() },
                onStop: controller.stop,
                onSecretHold: { monitorShown.toggle() }
            )
        }
        .padding(.horizontal, 12)
        .padding(.bottom, controller.hasConversation ? 8 : 24)
    }
}
