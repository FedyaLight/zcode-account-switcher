import SwiftUI
import ZCodeAccountSwitcherCore

struct AccountCardView: View {
    var account: AccountRecord
    var isActive: Bool
    var onSwitch: () -> Void
    var onDelete: () -> Void
    var onRename: (String) -> Void

    @State private var isEditing = false
    @State private var draftName = ""

    init(
        account: AccountRecord,
        isActive: Bool,
        onSwitch: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onRename: @escaping (String) -> Void
    ) {
        self.account = account
        self.isActive = isActive
        self.onSwitch = onSwitch
        self.onDelete = onDelete
        self.onRename = onRename
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            healthRow
            actions
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.green.opacity(0.55) : Color.primary.opacity(0.1), lineWidth: isActive ? 1.5 : 1)
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    if isActive {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                    }
                    if isEditing {
                        TextField("Account name", text: $draftName, onCommit: commitRename)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Text(account.meta.displayName)
                            .font(.headline)
                            .lineLimit(1)
                            .onTapGesture {
                                draftName = account.meta.displayName
                                isEditing = true
                            }
                    }
                }

                Text(account.meta.email ?? account.meta.userId ?? account.id)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                Badge(text: account.meta.provider ?? "ZAI", tint: .secondary)
                Text(account.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var avatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.18), Color.green.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(initials)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(width: 42, height: 42)
    }

    private var healthRow: some View {
        HStack(spacing: 8) {
            Image(systemName: healthIcon)
                .foregroundStyle(healthTint)
            Text(account.health.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text("\(account.sizeKb) KB")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if isActive {
                Button {} label: {
                    Label("Active", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .disabled(true)
            } else {
                Button(action: onSwitch) {
                    Label("Switch", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .frame(width: 28)
            }
            .help("Delete")
        }
    }

    private func commitRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != account.meta.displayName {
            onRename(trimmed)
        }
        isEditing = false
    }

    private var initials: String {
        let source = account.meta.email ?? account.meta.displayName
        let first = source.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)
        return first.isEmpty ? "Z" : String(first).uppercased()
    }

    private var healthIcon: String {
        switch account.health.status {
        case .healthy: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var healthTint: Color {
        switch account.health.status {
        case .healthy: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}
