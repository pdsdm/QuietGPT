import SwiftUI
import UIKit

struct CodeBlock: View {
    let code: String
    let language: String

    @Environment(\.palette) private var palette
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    withAnimation(Motion.snappy) { copied = true }
                    Task {
                        try? await Task.sleep(for: Motion.copiedHold)
                        withAnimation(Motion.snappy) { copied = false }
                    }
                } label: {
                    Text(copied ? "copied" : "copy")
                        .contentTransition(.numericText())
                        .frame(minHeight: 32)
                }
                .buttonStyle(PressableStyle())
            }
            .font(QuietGPTFont.monoSmall)
            .foregroundStyle(palette.text3)
            .padding(.horizontal, 12)
            .padding(.top, 2)

            Divider().overlay(palette.line)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(palette.text)
                    .padding(12)
                    .textSelection(.enabled)
            }
        }
        .background(palette.background, in: .rect(cornerRadius: Radius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .strokeBorder(palette.line, lineWidth: 1)
        }
    }
}
