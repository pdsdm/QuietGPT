import SwiftUI

struct UserBubble: View {
    let text: String

    @Environment(\.palette) private var palette

    var body: some View {
        HStack {
            Spacer(minLength: 56)
            Text(text)
                .font(HushFont.body)
                .foregroundStyle(palette.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(palette.elevated, in: UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22, bottomTrailingRadius: 6, topTrailingRadius: 22, style: .continuous))
                .textSelection(.enabled)
        }
    }
}
