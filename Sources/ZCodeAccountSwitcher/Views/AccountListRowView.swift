import SwiftUI
import ZCodeAccountSwitcherCore

struct AccountListRowView: View {
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
        HStack(spacing: 10) {
            avatar

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if isActive {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                    }
                    if isEditing {
                        TextField("Account name", text: $draftName, onCommit: commitRename)
                            .textFieldStyle(.plain)
                            .font(.callout.weight(.medium))
                    } else {
                        Text(account.meta.displayName)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                            .onTapGesture {
                                draftName = account.meta.displayName
                                isEditing = true
                            }
                    }
                }

                Text(account.meta.email ?? account.meta.userId ?? account.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Image(systemName: healthIcon)
                    .foregroundStyle(healthTint)
                Text(compactHealthSummary)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 124, alignment: .leading)
            .help(account.health.summary)

            Text("\(account.sizeKb) KB")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 52, alignment: .trailing)

            Badge(text: account.meta.provider ?? "ZAI", tint: .secondary)
                .frame(width: 54, alignment: .trailing)

            primaryAction
                .frame(width: 92, alignment: .trailing)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            .help("Delete")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.green.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: isActive ? 1.2 : 1)
        )
    }

    private var avatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.16), Color.green.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(initials)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(width: 32, height: 32)
    }

    @ViewBuilder
    private var primaryAction: some View {
        if isActive {
            Label("Active", systemImage: "checkmark")
                .font(.caption.weight(.semibold))
                .frame(width: 86, height: 24)
                .foregroundStyle(.green)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        } else {
            Button(action: onSwitch) {
                Label("Switch", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
                    .frame(width: 86, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6))
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

    private var compactHealthSummary: String {
        switch account.health.status {
        case .healthy: return "Snapshot ready"
        case .warning: return "Needs review"
        case .error: return "Snapshot invalid"
        }
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
