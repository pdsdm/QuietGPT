import SwiftUI
import UIKit

struct RewriteCard: View {
    let loadText: () async -> String
    let onClose: () -> Void

    @State private var original = ""
    @State private var styles = StyleStore.enabledStyles
    @State private var tone = StyleStore.enabledStyles.first ?? RewriteStyle.builtIn[0]
    @State private var result = ""
    @State private var failure: String?
    @State private var isWriting = false
    @State private var copied = false
    @State private var task: Task<Void, Never>?

    private let rewriter = Rewriter()

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            card
                .padding(8)
                .transition(.move(edge: .bottom))
        }
        .task {
            rewriter.prepare()
            original = await loadText().trimmingCharacters(in: .whitespacesAndNewlines)
            run()
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(Ink.line)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                Text(BrandFont.name)
                    .font(BrandFont.wordmark(size: 19))
                    .tracking(-0.45)
                    .foregroundStyle(Ink.text)
                HStack(spacing: 6) {
                    Circle().fill(Ink.local).frame(width: 5, height: 5)
                    Text("on this iPhone")
                }
                .font(BrandFont.font(size: 12))
                .foregroundStyle(Ink.text2)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Ink.text2)
                        .frame(width: 32, height: 32)
                        .background(Ink.elevated, in: .circle)
                }
                .accessibilityLabel("Close")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("your text")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Ink.text3)
                Text(original.isEmpty ? " " : original)
                    .font(BrandFont.font(size: 15))
                    .foregroundStyle(Ink.text2)
                    .lineLimit(3)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(styles) { option in
                        Button {
                            tone = option
                            run()
                        } label: {
                            Text(option.title)
                                .font(BrandFont.font(size: 15))
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .foregroundStyle(option == tone ? Ink.background : Ink.text)
                                .background(option == tone ? Ink.text : Ink.raised, in: .capsule)
                                .overlay {
                                    Capsule().strokeBorder(option == tone ? .clear : Ink.line, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)

            VStack(alignment: .leading, spacing: 8) {
                Text(tone.title.lowercased())
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Ink.text3)
                ScrollView {
                    Text(failure ?? (result.isEmpty ? "writing…" : result))
                        .font(BrandFont.font(size: 18))
                        .foregroundStyle(failure == nil && !result.isEmpty ? Ink.text : Ink.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 200, alignment: .topLeading)
            .background(Ink.surface, in: UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 6, bottomTrailingRadius: 22, topTrailingRadius: 22))
            .overlay {
                UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 6, bottomTrailingRadius: 22, topTrailingRadius: 22)
                    .strokeBorder(Ink.line, lineWidth: 1)
            }

            Button(action: copy) {
                Text(copied ? "Copied · paste it in your chat" : "Copy")
                    .font(BrandFont.font(size: 17))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundStyle(Ink.background)
                    .background(Ink.text, in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(result.isEmpty || isWriting)
            .opacity(result.isEmpty || isWriting ? 0.4 : 1)

            Text("rewritten on this iPhone · 0 B sent")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Ink.text3)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .background(Ink.background, in: .rect(cornerRadius: 34, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(Ink.line, lineWidth: 1)
        }
        .animation(.snappy, value: tone)
        .animation(.snappy, value: copied)
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
    }

    private func run() {
        task?.cancel()
        result = ""
        failure = nil
        copied = false
        guard !original.isEmpty else {
            failure = "Select some text, then share it to QuietGPT."
            return
        }
        guard rewriter.isAvailable else {
            failure = "QuietGPT needs Apple Intelligence. Turn it on in Settings."
            return
        }
        isWriting = true
        let stream = rewriter.rewrite(original, style: tone)
        task = Task {
            do {
                for try await text in stream {
                    result = text
                }
            } catch is CancellationError {
                return
            } catch {
                failure = Rewriter.message(for: error)
            }
            if !Task.isCancelled {
                isWriting = false
            }
        }
    }

    private func copy() {
        UIPasteboard.general.string = result.trimmingCharacters(in: .whitespacesAndNewlines)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            onClose()
        }
    }
}
