import SwiftUI

struct VoiceScreen: View {
    @Environment(\.palette) private var palette
    @State private var appeared = false

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            AsciiField(mode: .ripple, mask: .vignette)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Voice")
                        .font(HushFont.largeTitle)
                        .foregroundStyle(palette.text)
                    Spacer()
                    Text("soon")
                        .font(HushFont.monoSmall)
                        .foregroundStyle(palette.accentText)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(palette.accentSoft, in: .capsule)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)

                Spacer()

                VStack(spacing: 28) {
                    BreathingMic()
                        .scaleEffect(appeared ? 1 : 0.8)
                        .opacity(appeared ? 1 : 0)

                    VStack(spacing: 10) {
                        Text("Talk to Hush out loud.")
                            .font(HushFont.title)
                            .foregroundStyle(palette.text)
                        Text("Hush hears you and answers on this iPhone. Your voice never leaves it.")
                            .font(HushFont.subheadline)
                            .foregroundStyle(palette.text2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 290)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                }

                Spacer()

                Text("coming in a future update")
                    .font(HushFont.monoSmall)
                    .foregroundStyle(palette.text3)
                    .padding(.bottom, 24)
            }
        }
        .onAppear {
            withAnimation(Motion.gentle) { appeared = true }
        }
        .onDisappear { appeared = false }
    }
}

private struct BreathingMic: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    let phase = (t / 3 + Double(ring) / 3).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .strokeBorder(palette.accent.opacity(0.35 * (1 - phase)), lineWidth: 1)
                        .frame(width: 88 + phase * 90, height: 88 + phase * 90)
                }
                Circle()
                    .fill(palette.raised)
                    .overlay { Circle().strokeBorder(palette.line, lineWidth: 1) }
                    .frame(width: 88, height: 88)
                    .scaleEffect(1 + 0.03 * sin(t * 1.6))
                Image(systemName: "mic")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(palette.text2)
            }
            .frame(width: 180, height: 180)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Voice is coming soon")
    }
}
