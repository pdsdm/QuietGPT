import SwiftUI

struct ToneBar: View {
    let model: KeyboardModel
    let onTone: (RewriteTone) -> Void
    let onUndo: () -> Void
    let onNextKeyboard: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(RewriteTone.allCases) { tone in
                        Button {
                            onTone(tone)
                        } label: {
                            Text(tone.title)
                                .font(.system(size: 15))
                                .padding(.horizontal, 14)
                                .frame(height: 40)
                                .foregroundStyle(tone == model.tone ? Ink.background : Ink.text)
                                .background(tone == model.tone ? Ink.text : Ink.raised, in: .capsule)
                                .overlay {
                                    Capsule().strokeBorder(tone == model.tone ? .clear : Ink.line, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isWriting)
                    }
                }
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 10) {
                if model.showsGlobe {
                    Button(action: onNextKeyboard) {
                        Image(systemName: "globe")
                            .font(.system(size: 17))
                            .foregroundStyle(Ink.text)
                            .frame(width: 44, height: 40)
                            .background(Ink.elevated, in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Next keyboard")
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(Ink.local)
                        .frame(width: 5, height: 5)
                        .opacity(model.isWriting ? 0.4 : 1)
                    Text("hush")
                        .foregroundStyle(Ink.text)
                    Text(model.status)
                        .foregroundStyle(Ink.text2)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                .font(.system(size: 13, design: .monospaced))

                Spacer(minLength: 0)

                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 15))
                        .foregroundStyle(Ink.text2)
                        .frame(width: 44, height: 40)
                        .background(Ink.elevated, in: .rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(!model.canUndo)
                .opacity(model.canUndo ? 1 : 0.35)
                .accessibilityLabel("Undo rewrite")
            }
            .padding(.horizontal, 10)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.background)
        .animation(.snappy, value: model.tone)
        .animation(.snappy, value: model.status)
    }
}
