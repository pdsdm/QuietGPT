import SwiftData
import SwiftUI

struct PrivacyScreen: View {
    var controller: ChatController
    var onDeleteAll: () -> Void

    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.lockEnabled) private var lockEnabled = true
    @ScaledMetric(relativeTo: .largeTitle) private var counterSize: CGFloat = 72
    @State private var confirmingDelete = false
    @State private var appeared = false

    private var network: NetworkWatch { .shared }

    private static let checks: [(title: LocalizedStringKey, body: LocalizedStringKey)] = [
        ("Runs on this iPhone", "QuietGPT answers on the device. No server."),
        ("Encrypted storage", "Chats are locked with your passcode."),
        ("No account, no analytics", "No tracking, no crash reports, no ads.")
    ]

    var body: some View {
        ZStack(alignment: .top) {
            palette.background.ignoresSafeArea()

            LiquidField(mode: .ripple, mask: .fadeDown)
                .frame(height: 360)
                .ignoresSafeArea(edges: .top)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Privacy")
                        .font(QuietGPTFont.largeTitle)
                        .foregroundStyle(palette.text)
                        .padding(.top, 24)

                    counter
                        .padding(.top, 28)
                        .padding(.bottom, 24)

                    card {
                        ForEach(Array(Self.checks.enumerated()), id: \.offset) { index, check in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("ok")
                                    .font(QuietGPTFont.mono)
                                    .foregroundStyle(palette.local)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(check.title)
                                        .font(QuietGPTFont.callout)
                                        .foregroundStyle(palette.text)
                                    Text(check.body)
                                        .font(QuietGPTFont.footnote)
                                        .foregroundStyle(palette.text2)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .opacity(appeared ? 1 : 0)
                            .offset(x: appeared ? 0 : -12)
                            .animation(Motion.gentle.delay(0.2 + Double(index) * 0.08), value: appeared)
                            if index < Self.checks.count - 1 {
                                Divider().overlay(palette.line)
                            }
                        }
                    }

                    networkCard
                        .padding(.top, 12)

                    card {
                        Toggle(isOn: $lockEnabled) {
                            Text("Face ID lock")
                                .font(QuietGPTFont.callout)
                                .foregroundStyle(palette.text)
                        }
                        .tint(palette.local)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                    }
                    .padding(.top, 12)

                    Text("Test it: turn on airplane mode and keep chatting.")
                        .font(QuietGPTFont.footnote)
                        .foregroundStyle(palette.text2)
                        .padding(.top, 20)

                    Button("Delete all data", role: .destructive) {
                        confirmingDelete = true
                    }
                    .buttonStyle(QuietButtonStyle(color: palette.danger))
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
        .confirmationDialog("Delete all data?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete all data", role: .destructive, action: deleteAll)
        } message: {
            Text("This removes every chat, rule, person and style from this iPhone. It cannot be undone.")
        }
        .sensoryFeedback(.warning, trigger: confirmingDelete) { _, new in new }
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
    }

    private var counter: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                LiveDot(color: palette.local)
                Text("live")
            }
            .font(QuietGPTFont.footnote)
            .foregroundStyle(palette.local)

            ScrambleText(final: NetworkMeter.format(network.total.sentBytes), active: appeared)
                .font(.system(size: counterSize, weight: .light, design: .monospaced))
                .tracking(-3)
                .foregroundStyle(palette.text)

            Text("sent by QuietGPT. Measured each second on this iPhone.")
                .font(QuietGPTFont.subheadline)
                .foregroundStyle(palette.text2)
        }
        .accessibilityElement(children: .combine)
    }

    private var networkCard: some View {
        card {
            VStack(alignment: .leading, spacing: 0) {
                networkRow("Connections opened by QuietGPT", value: "\(network.total.connections)")
                    .padding(.bottom, -5)
                Text("iOS does not count the bytes of Apple's writing service. To check network activity on this iPhone, go to Settings > Privacy & Security > App Privacy Report.")
                    .font(QuietGPTFont.footnote)
                    .foregroundStyle(palette.text2)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 13)
            }
        }
    }

    private func networkRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(QuietGPTFont.callout)
                .foregroundStyle(palette.text)
            Spacer(minLength: 0)
            Text(value)
                .font(QuietGPTFont.mono)
                .foregroundStyle(palette.local)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(palette.surface, in: .rect(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(palette.line, lineWidth: 1)
            }
    }

    private func deleteAll() {
        controller.deleteAll()
        StyleStore.reset()
        onDeleteAll()
    }
}

struct ScrambleText: View {
    let final: String
    var active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: String = ""

    private static let glyphs: [Character] = Array(".·:-=+*#%")

    var body: some View {
        Text(shown.isEmpty ? final : shown)
            .accessibilityLabel(final)
            .task(id: "\(active) \(final)") {
                guard active, !reduceMotion else {
                    shown = final
                    return
                }
                let characters = Array(final)
                for step in 0...14 {
                    let settled = Int(Double(characters.count) * Double(step) / 14)
                    shown = String(characters.enumerated().map { index, character in
                        index < settled || character == " " ? character : Self.glyphs.randomElement() ?? character
                    })
                    try? await Task.sleep(for: .milliseconds(45))
                    if Task.isCancelled { return }
                }
                shown = final
            }
    }
}
