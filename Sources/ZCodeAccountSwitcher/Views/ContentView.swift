import AppKit
import SwiftUI
import ZCodeAccountSwitcherCore

struct ContentView: View {
    @EnvironmentObject private var model: AccountAppModel
    @State private var accountViewMode: AccountViewMode = .grid

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    accountSections
                        .padding(24)
                        .frame(maxWidth: 1080)
                        .frame(maxWidth: .infinity)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .disabled(model.isBusy)
            .overlay {
                if model.isBusy {
                    ZStack {
                        Color.black.opacity(0.08)
                        ProgressView()
                            .controlSize(.large)
                    }
                }
            }

            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.toast)
        .sheet(isPresented: $model.showingAddSheet) {
            AddAccountSheet()
                .environmentObject(model)
        }
        .alert("Delete Account", isPresented: deleteBinding) {
            Button("Cancel", role: .cancel) { model.showingDeleteConfirmation = nil }
            Button("Delete", role: .destructive) {
                guard let account = model.showingDeleteConfirmation else { return }
                model.showingDeleteConfirmation = nil
                Task { await model.deleteAccount(account) }
            }
        } message: {
            Text("This removes the local snapshot only. It does not affect the ZCode account.")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            StatusPill(
                title: model.status.zcodeRunning ? "ZCode running" : "ZCode stopped",
                systemImage: model.status.zcodeRunning ? "bolt.horizontal.circle.fill" : "checkmark.circle.fill",
                tint: model.status.zcodeRunning ? .orange : .green
            )

            Spacer()

            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 18, height: 18)
            }
            .help("Refresh")
            .accessibilityLabel("Refresh")

            Button {
                model.presentImportPanel()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .help("Import")

            Button {
                Task { await model.exportAccounts() }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export")

            Button {
                model.showingAddSheet = true
            } label: {
                Label("Add Account", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var accountSections: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Text("Accounts")
                    .font(.title2.weight(.semibold))
                Spacer()
                privacyButton
                ViewModeControl(selection: $accountViewMode)
            }

            if model.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else if model.accounts.isEmpty {
                EmptyStateView {
                    model.showingAddSheet = true
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                if let active = model.activeAccount {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Active")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        activeAccountView(active)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Other Accounts (\(model.otherAccounts.count))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    otherAccountsView

                    if model.otherAccounts.isEmpty {
                        Text("No other accounts.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
            }
        }
    }

    private var privacyButton: some View {
        Button {
            model.hidesPrivateAccountData.toggle()
        } label: {
            Image(systemName: model.hidesPrivateAccountData ? "eye.slash" : "eye")
                .frame(width: 18, height: 18)
        }
        .help(model.hidesPrivateAccountData ? "Show account data" : "Hide account data")
        .accessibilityLabel(model.hidesPrivateAccountData ? "Show account data" : "Hide account data")
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { model.showingDeleteConfirmation != nil },
            set: { if !$0 { model.showingDeleteConfirmation = nil } }
        )
    }

    @ViewBuilder
    private var otherAccountsView: some View {
        switch accountViewMode {
        case .grid:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 14)], spacing: 14) {
                ForEach(model.otherAccounts) { account in
                    accountCard(for: account)
                }
            }
        case .list:
            LazyVStack(spacing: 8) {
                ForEach(model.otherAccounts) { account in
                    accountRow(for: account)
                }
            }
        }
    }

    @ViewBuilder
    private func activeAccountView(_ account: AccountRecord) -> some View {
        switch accountViewMode {
        case .grid:
            accountCard(for: account)
        case .list:
            accountRow(for: account)
        }
    }

    private func accountCard(for account: AccountRecord) -> some View {
        AccountCardView(
            account: account,
            isActive: account.id == model.currentAccountId,
            hidesPrivateAccountData: model.hidesPrivateAccountData,
            onSwitch: { Task { await model.switchToAccount(account) } },
            onDelete: { model.showingDeleteConfirmation = account },
            onRename: { label in Task { await model.renameAccount(account, label: label) } }
        )
    }

    private func accountRow(for account: AccountRecord) -> some View {
        AccountListRowView(
            account: account,
            isActive: account.id == model.currentAccountId,
            hidesPrivateAccountData: model.hidesPrivateAccountData,
            onSwitch: { Task { await model.switchToAccount(account) } },
            onDelete: { model.showingDeleteConfirmation = account },
            onRename: { label in Task { await model.renameAccount(account, label: label) } }
        )
    }
}
