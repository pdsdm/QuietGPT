import SwiftUI

struct SplashScreen: View {
    static let duration: Duration = .seconds(3.4)
    static let shortDuration: Duration = .seconds(0.6)

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsName = false

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            VStack(spacing: 24) {
                AsciiLock(side: 340)
                Wordmark(size: 30)
                    .opacity(showsName ? 1 : 0)
                    .offset(y: showsName ? 0 : 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BrandFont.name)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(reduceMotion ? 0 : 1.9)) { showsName = true }
        }
    }
}

#Preview {
    SplashScreen()
}
