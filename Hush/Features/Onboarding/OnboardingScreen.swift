import SwiftUI

struct OnboardingScreen: View {
    var onFinish: (_ useLock: Bool) -> Void

    @Environment(\.palette) private var palette
    @State private var page = 0
    @State private var appeared = false

    private static let pageCount = 3

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            AsciiField(mode: page == 1 ? .drift : .ripple, mask: .fadeDown)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                indicator
                    .padding(.top, 12)

                ZStack {
                    switch page {
                    case 0: intro.transition(pageTransition)
                    case 1: proof.transition(pageTransition)
                    default: lock.transition(pageTransition)
                    }
                }
                .frame(maxHeight: .infinity)

                actions
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .animation(Motion.spring, value: page)
        .sensoryFeedback(.selection, trigger: page)
        .onAppear {
            withAnimation(Motion.gentle.delay(0.1)) { appeared = true }
        }
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 40)).combined(with: AnyTransition(.blurReplace)),
            removal: .opacity.combined(with: .offset(x: -40)).combined(with: AnyTransition(.blurReplace))
        )
    }

    private var indicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<Self.pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == page ? palette.text : palette.line)
                    .frame(width: index == page ? 20 : 6, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(page + 1) of \(Self.pageCount)")
    }

    private var intro: some View {
        VStack(spacing: 28) {
            AppMark(size: 96, animated: true)
                .scaleEffect(appeared ? 1 : 0.7)
                .opacity(appeared ? 1 : 0)
            Wordmark(size: 64)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
            Text("A private mind that lives on your iPhone.")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(palette.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                .opacity(appeared ? 1 : 0)
        }
    }

    private var proof: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Nothing leaves\nthis phone.")
                .font(.system(size: 34, weight: .regular))
                .tracking(-0.6)
                .foregroundStyle(palette.text)
            TerminalLines(lines: [
                ("account", "none"),
                ("cloud", "none"),
                ("tracking", "none"),
                ("airplane mode", "works"),
                ("sent", "0 B")
            ])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lock: some View {
        VStack(spacing: 22) {
            Image(systemName: "faceid")
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundStyle(palette.text)
                .symbolEffect(.pulse, options: .repeating)
            Text("Lock your chats")
                .font(HushFont.title)
                .foregroundStyle(palette.text)
            Text("Only your face opens Hush. You can change this later in Privacy.")
                .font(HushFont.subheadline)
                .foregroundStyle(palette.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 8) {
            if page < Self.pageCount - 1 {
                Button(page == 0 ? "Begin" : "Continue") {
                    page += 1
                }
                .buttonStyle(PrimaryButtonStyle())
                .transition(.blurReplace)
            } else {
                Button("Use Face ID") { onFinish(true) }
                    .buttonStyle(PrimaryButtonStyle())
                    .transition(.blurReplace)
                Button("Not now") { onFinish(false) }
                    .buttonStyle(QuietButtonStyle())
                    .transition(.opacity)
            }
        }
        .frame(minHeight: 106, alignment: .bottom)
    }
}

private struct TerminalLines: View {
    let lines: [(label: String, value: String)]

    @Environment(\.palette) private var palette
    @State private var visible = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(spacing: 0) {
                    Text("> \(line.label)")
                        .foregroundStyle(palette.text2)
                    Spacer()
                    Text(line.value)
                        .foregroundStyle(line.value == "none" ? palette.text : palette.local)
                }
                .font(HushFont.mono)
                .opacity(index < visible ? 1 : 0)
                .offset(y: index < visible ? 0 : 6)
                .blur(radius: index < visible ? 0 : 4)
            }
        }
        .padding(16)
        .background(palette.surface.opacity(0.9), in: .rect(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(palette.line, lineWidth: 1)
        }
        .task {
            for index in 1...lines.count {
                try? await Task.sleep(for: .milliseconds(220))
                if Task.isCancelled { return }
                withAnimation(Motion.spring) { visible = index }
            }
        }
        .sensoryFeedback(.selection, trigger: visible)
    }
}
