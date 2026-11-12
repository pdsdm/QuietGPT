import SwiftUI

struct StoreFailureScreen: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Palette.forScheme(colorScheme)
        ZStack {
            palette.background.ignoresSafeArea()

            VStack(spacing: 10) {
                Text("QuietGPT can't open your chats")
                    .font(QuietGPTFont.title)
                    .foregroundStyle(palette.text)
                Text("Restart your iPhone and make sure that it has free storage. Then open QuietGPT again. The keyboard still works.")
                    .font(QuietGPTFont.subheadline)
                    .foregroundStyle(palette.text2)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
        }
    }
}
