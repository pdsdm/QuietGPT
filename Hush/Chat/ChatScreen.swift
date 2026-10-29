import SwiftUI

struct ChatScreen: View {
    @Bindable var controller: ChatController
    var onShowChats: () -> Void

    @Environment(\.palette) private var palette
    @State private var greeted = false

    private static let ideas: [(title: String, hint: String, prompt: String)] = [
        ("Help me write a message", "write", "Help me write a short, kind message to a friend I have not talked to in a while."),
        ("Summarize a long text", "read", "I will paste a long text. Summarize it in five short points."),
        ("Think a decision through", "think", "Help me think through a decision. Ask me one question at a time.")
    ]

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            AsciiField(
                mode: controller.isResponding ? .think : .drift,
                mask: controller.hasConversation ? .fadeUp : .fadeDown
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if controller.hasConversation {
                    conversation
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    welcome
                        .transition(.blurReplace)
                }
                footer
            }
        }
        .animation(Motion.spring, value: controller.hasConversation)
        .animation(Motion.gentle, value: controller.isResponding)
        .toolbarVisibility(controller.hasConversation ? .hidden : .visible, for: .tabBar)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: controller.completedReplies)
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
                        .font(HushFont.subheadline)
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        LiveDot(color: palette.local, size: 5)
                        Text("on this iPhone")
                    }
                    .font(HushFont.caption)
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
        } else {
            HStack {
                Wordmark(size: 26)
                Spacer()
                Chip(title: "On this iPhone", dot: palette.local)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
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
            .font(.system(size: 34, weight: .regular))
            .tracking(-0.6)
            .foregroundStyle(palette.text)
            .animation(Motion.gentle, value: greeted)

            VStack(spacing: 0) {
                ForEach(Array(Self.ideas.enumerated()), id: \.offset) { index, idea in
                    Button {
                        controller.send(idea.prompt)
                    } label: {
                        HStack {
                            Text(idea.title)
                                .font(HushFont.body)
                                .foregroundStyle(palette.text)
                            Spacer()
                            Text(idea.hint)
                                .font(HushFont.mono)
                                .foregroundStyle(palette.text3)
                        }
                        .frame(minHeight: 50)
                        .contentShape(.rect)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(palette.line).frame(height: 1)
                    }
                    .opacity(greeted ? 1 : 0)
                    .offset(y: greeted ? 0 : 16)
                    .animation(Motion.gentle.delay(0.25 + Double(index) * 0.07), value: greeted)
                }
            }
            .overlay(alignment: .top) {
                Rectangle().fill(palette.line).frame(height: 1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
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
            if controller.isResponding {
                Text("thinking on this iPhone · 0 B sent")
                    .font(HushFont.monoSmall)
                    .foregroundStyle(palette.text3)
                    .transition(.blurReplace)
            }
            Composer(
                text: $controller.draft,
                placeholder: controller.hasConversation ? "Reply" : "Ask anything. It stays here.",
                isResponding: controller.isResponding,
                canSend: controller.canSend,
                onSend: { controller.send() },
                onStop: controller.stop
            )
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
