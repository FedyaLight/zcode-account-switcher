import SwiftUI

struct ViewModeControl: View {
    @Binding var selection: AccountViewMode

    var body: some View {
        HStack(spacing: 4) {
            modeButton(.grid, systemImage: "square.grid.2x2")
            modeButton(.list, systemImage: "list.bullet")
        }
        .padding(3)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private func modeButton(_ mode: AccountViewMode, systemImage: String) -> some View {
        Button {
            selection = mode
        } label: {
            Image(systemName: systemImage)
                .frame(width: 28, height: 24)
                .foregroundStyle(selection == mode ? Color.accentColor : Color.secondary)
                .background(
                    selection == mode ? Color.accentColor.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
        .help(mode == .grid ? "Grid view" : "List view")
    }
}
