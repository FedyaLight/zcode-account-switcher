import SwiftUI

struct ToastView: View {
    var toast: ToastMessage

    var body: some View {
        Label(toast.message, systemImage: icon)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(.white)
            .background(tint, in: RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 10, y: 4)
    }

    private var icon: String {
        switch toast.style {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var tint: Color {
        switch toast.style {
        case .success: return .green
        case .error: return .red
        case .info: return .blue
        }
    }
}
