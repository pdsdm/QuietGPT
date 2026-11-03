import SwiftUI

enum Motion {
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.8)
    static let gentle = Animation.spring(response: 0.6, dampingFraction: 0.9)
    static let copiedHold = Duration.seconds(1.4)
}
