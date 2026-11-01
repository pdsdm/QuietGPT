import LocalAuthentication
import SwiftUI

struct LockScreen: View {
    var onUnlock: () -> Void

    @Environment(\.palette) private var palette
    @State private var failed = 0
    @State private var authenticating = false

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            AsciiField(mode: .ripple, mask: .none)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 22) {
                    AppMark(size: 88)
                        .opacity(authenticating ? 0.6 : 1)
                        .animation(.easeInOut(duration: 0.4), value: authenticating)
                        .keyframeAnimator(initialValue: 0.0, trigger: failed) { content, offset in
                            content.offset(x: offset)
                        } keyframes: { _ in
                            KeyframeTrack {
                                SpringKeyframe(-12, duration: 0.08)
                                SpringKeyframe(10, duration: 0.08)
                                SpringKeyframe(-6, duration: 0.08)
                                SpringKeyframe(0, duration: 0.2)
                            }
                        }
                    VStack(spacing: 6) {
                        Text("Hush is locked")
                            .font(HushFont.title)
                            .foregroundStyle(palette.text)
                        Text("Your chats are encrypted on this iPhone.")
                            .font(HushFont.subheadline)
                            .foregroundStyle(palette.text2)
                    }
                }
                Spacer()
                VStack(spacing: 8) {
                    Button("Unlock with Face ID") { authenticate(biometricsOnly: true) }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Use passcode") { authenticate(biometricsOnly: false) }
                        .buttonStyle(QuietButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
        .sensoryFeedback(.error, trigger: failed)
        .task { authenticate(biometricsOnly: false) }
    }

    private func authenticate(biometricsOnly: Bool) {
        guard !authenticating else { return }
        let context = LAContext()
        let policy: LAPolicy = biometricsOnly ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
        var error: NSError?

        guard context.canEvaluatePolicy(policy, error: &error) else {
            if !context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) {
                onUnlock()
            } else {
                failed += 1
            }
            return
        }

        authenticating = true
        Task {
            let success = (try? await context.evaluatePolicy(policy, localizedReason: "Unlock your chats")) ?? false
            authenticating = false
            if success {
                onUnlock()
            } else {
                failed += 1
            }
        }
    }
}
