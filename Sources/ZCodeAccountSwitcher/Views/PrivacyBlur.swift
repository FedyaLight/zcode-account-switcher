import SwiftUI

extension View {
    @ViewBuilder
    func privacyBlurred(_ isActive: Bool, radius: CGFloat = 4) -> some View {
        if isActive {
            self
                .privacySensitive()
                .blur(radius: radius)
                .accessibilityHidden(true)
        } else {
            self
        }
    }
}
