import SwiftUI

struct Composer: View {
    @Binding var text: String
    let placeholder: String
    let isResponding: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    var onSecretHold: () -> Void = {}

    @Environment(\.palette) private var palette
    @FocusState private var focused: Bool
    @State private var sends = 0
    @State private var secretHolds = 0
    @State private var skipsNextSend = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholder, text: $text, axis: .vertical)
                .font(QuietGPTFont.body)
                .foregroundStyle(palette.text)
                .tint(palette.accent)
                .lineLimit(1...6)
                .focused($focused)
                .padding(.vertical, 12)
                .padding(.leading, 18)
                .submitLabel(.send)
                .onSubmit(send)
                #if DEBUG
                .onAppear { focused = DebugLaunch.focusesComposer }
                #endif

            Button(action: isResponding ? onStop : send) {
                Image(systemName: isResponding ? "stop.fill" : "arrow.up")
                    .font(.system(size: isResponding ? 14 : 18, weight: .medium))
                    .contentTransition(.symbolEffect(.replace.downUp))
                    .symbolEffect(.bounce, value: sends)
                    .foregroundStyle(buttonForeground)
                    .frame(width: 44, height: 44)
                    .background(buttonBackground, in: .circle)
            }
            .buttonStyle(PressableStyle(scale: 0.86))
            .disabled(!canSend && !isResponding)
            .accessibilityLabel(isResponding ? "Stop" : "Send")
            .padding(4)
            .animation(Motion.spring, value: isResponding)
            .animation(Motion.spring, value: canSend)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 10).onEnded { _ in
                    skipsNextSend = true
                    secretHolds += 1
                    onSecretHold()
                }
            )
        }
        .background(palette.raised, in: .rect(cornerRadius: Radius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .strokeBorder(focused ? palette.accent.opacity(0.5) : .clear, lineWidth: 1)
        }
        .animation(Motion.spring, value: focused)
        .sensoryFeedback(.impact(weight: .light), trigger: sends)
        .sensoryFeedback(.success, trigger: secretHolds)
    }

    private var buttonBackground: Color {
        if isResponding { return palette.primary }
        return canSend ? palette.accent : palette.elevated
    }

    private var buttonForeground: Color {
        if isResponding { return palette.onPrimary }
        return canSend ? palette.onAccent : palette.text3
    }

    private func send() {
        if skipsNextSend {
            skipsNextSend = false
            return
        }
        guard canSend else { return }
        sends += 1
        onSend()
    }
}
