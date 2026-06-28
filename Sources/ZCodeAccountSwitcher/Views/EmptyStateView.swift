import SwiftUI

struct EmptyStateView: View {
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("No accounts yet")
                .font(.headline)
            Button {
                onAdd()
            } label: {
                Label("Add Account", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
