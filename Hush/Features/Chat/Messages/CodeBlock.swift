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
                        try? await Task.sleep(for: .seconds(1.4))
                        withAnimation(Motion.snappy) { copied = false }
                    }
                } label: {
                    Text(copied ? "copied" : "copy")
                        .contentTransition(.numericText())
                        .frame(minHeight: 32)
                }
                .buttonStyle(PressableStyle())
            }
            .font(HushFont.monoSmall)
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
        .background(palette.background, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.line, lineWidth: 1)
        }
    }
}
