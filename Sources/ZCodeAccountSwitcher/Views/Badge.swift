import SwiftUI

struct Badge: View {
    var text: String
    var tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.2), lineWidth: 1))
    }
}
