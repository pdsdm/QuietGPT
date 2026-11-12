import SwiftUI
import WebKit

struct AgentScreen: View {
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.agentOnline) private var online = false
    @State private var runner = AgentRunner()
    @State private var site = ""
    @State private var task = ""
    @FocusState private var focused: Bool

    private var address: URL? {
        AgentBrowser.address(from: site)
    }

    private var canStart: Bool {
        address != nil && !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && runner.canThink
    }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            if runner.phase == .idle {
                setup
            } else {
                session
            }
        }
        .animation(Motion.gentle, value: runner.phase)
        .sensoryFeedback(.impact, trigger: runner.log.count)
    }

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Agent")
                    .font(QuietGPTFont.largeTitle)
                    .foregroundStyle(palette.text)
                    .padding(.top, 24)

                Text("QuietGPT opens a web page and does the steps for you. You see each step. It asks you before it confirms.")
                    .font(QuietGPTFont.subheadline)
                    .foregroundStyle(palette.text2)
                    .padding(.top, 8)

                card {
                    Toggle(isOn: $online) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use the internet here")
                                .font(QuietGPTFont.callout)
                                .foregroundStyle(palette.text)
                            Text("Only this tab goes online, to the web page you give. QuietGPT still thinks on this iPhone.")
                                .font(QuietGPTFont.footnote)
                                .foregroundStyle(palette.text2)
                        }
                    }
                    .tint(palette.toggle)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                }
                .padding(.top, 24)

                if online {
                    card {
                        TextField("Web address", text: $site)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 52)
                        Divider().overlay(palette.line)
                        TextField("What to do. Example: a table for 2 on Friday at 21:00, name Ana", text: $task, axis: .vertical)
                            .lineLimit(3...6)
                            .focused($focused)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }
                    .font(QuietGPTFont.callout)
                    .foregroundStyle(palette.text)
                    .padding(.top, 12)

                    if !runner.canThink {
                        Text("QuietGPT needs Apple Intelligence for this. Turn it on in Settings, then Apple Intelligence & Siri.")
                            .font(QuietGPTFont.footnote)
                            .foregroundStyle(palette.text2)
                            .padding(.top, 12)
                    }

                    Button("Start") {
                        guard let address else { return }
                        focused = false
                        runner.start(task: task, at: address)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canStart)
                    .padding(.top, 20)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private var session: some View {
        VStack(spacing: 0) {
            AgentWebView(webView: runner.browser.webView)
                .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(palette.line, lineWidth: 1)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

            panel
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if runner.phase == .working {
                    LiveDot(color: palette.local)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(QuietGPTFont.callout)
                        .foregroundStyle(palette.text)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(QuietGPTFont.footnote)
                            .foregroundStyle(palette.text2)
                    }
                }
                Spacer(minLength: 0)
                Text("\(runner.log.count)")
                    .font(QuietGPTFont.monoSmall)
                    .foregroundStyle(palette.text3)
                    .accessibilityLabel("Steps: \(runner.log.count)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            switch runner.phase {
            case .approval:
                HStack(spacing: 12) {
                    Button("Stop") { runner.answer(false) }
                        .buttonStyle(QuietButtonStyle())
                    Button("Allow") { runner.answer(true) }
                        .buttonStyle(PrimaryButtonStyle())
                }
            case .handover:
                HStack(spacing: 12) {
                    Button("Stop") { runner.stop() }
                        .buttonStyle(QuietButtonStyle())
                    Button("Continue") { runner.answer(true) }
                        .buttonStyle(PrimaryButtonStyle())
                }
            case .working:
                Button("Stop") { runner.stop() }
                    .buttonStyle(QuietButtonStyle())
            case .finished, .stopped, .idle:
                Button("Close") { runner.reset() }
                    .buttonStyle(QuietButtonStyle())
            }
        }
    }

    private var headline: String {
        switch runner.phase {
        case .approval(let name):
            String(localized: "QuietGPT wants to tap “\(name)”.")
        case .handover(let name):
            String(localized: "Your turn. Fill “\(name)” on the page, then tap Continue.")
        case .finished:
            String(localized: "Done")
        case .stopped:
            String(localized: "Stopped")
        case .working, .idle:
            runner.log.last?.text ?? String(localized: "Opening the page")
        }
    }

    private var detail: String {
        switch runner.phase {
        case .finished(let message), .stopped(let message):
            message
        case .approval, .handover:
            ""
        case .working, .idle:
            runner.log.last?.detail ?? ""
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(palette.surface, in: .rect(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(palette.line, lineWidth: 1)
            }
    }
}

private struct AgentWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}
