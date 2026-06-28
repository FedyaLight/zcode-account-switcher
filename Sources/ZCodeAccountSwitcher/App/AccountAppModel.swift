import Foundation
import ZCodeAccountSwitcherCore

@MainActor
final class AccountAppModel: ObservableObject {
    @Published var accounts: [AccountRecord] = []
    @Published var status = AppStatus(current: nil, zcodeRunning: false, hasLastBackup: false)
    @Published var isLoading = false
    @Published var isBusy = false
    @Published var searchText = ""
    @Published var toast: ToastMessage?
    @Published var showingAddSheet = false
    @Published var showingDeleteConfirmation: AccountRecord?
    @Published var oauthSession: OAuthSession?

    let store: AccountStore
    lazy var oauthService = OAuthService(accountStore: store)
    var oauthCallbackServer: OAuthCallbackServer?

    init(store: AccountStore = AccountStore()) {
        self.store = store
    }

    var filteredAccounts: [AccountRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return accounts }
        return accounts.filter { record in
            [
                record.meta.displayName,
                record.meta.email,
                record.meta.name,
                record.meta.provider,
                record.id
            ]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(query) }
        }
    }

    var currentAccountId: String? {
        status.current?.emailShortId.isEmpty == false ? status.current?.emailShortId : status.current?.shortId
    }

    var activeAccount: AccountRecord? {
        guard let currentAccountId else { return nil }
        return accounts.first { $0.id == currentAccountId }
    }

    var otherAccounts: [AccountRecord] {
        filteredAccounts.filter { $0.id != currentAccountId }
    }

    func refresh() async {
        isLoading = true
        await reloadStatusAndList()
        isLoading = false
    }

    func reloadStatusAndList() async {
        status = store.status()
        do {
            accounts = try store.list()
        } catch {
            showToast(.error, error.localizedDescription)
        }
    }

    func capture(label: String?) async {
        await runBusy {
            let result = try store.capture(label: label, overwrite: false)
            if result.created {
                showToast(.success, "Captured \(result.meta.displayName).")
            } else {
                showToast(.info, result.message ?? "Account already exists.")
            }
            await reloadStatusAndList()
        }
    }

    func switchToAccount(_ account: AccountRecord) async {
        await runBusy {
            _ = try await store.use(id: account.id, restart: false, force: true)
            showToast(.success, "Switched to \(account.meta.displayName). Launch ZCode manually.")
            await reloadStatusAndList()
        }
    }

    func deleteAccount(_ account: AccountRecord) async {
        await runBusy {
            _ = try store.remove(id: account.id)
            showToast(.success, "Deleted \(account.meta.displayName).")
            await reloadStatusAndList()
        }
    }

    func renameAccount(_ account: AccountRecord, label: String) async {
        do {
            _ = try store.rename(id: account.id, label: label)
            await reloadStatusAndList()
        } catch {
            showToast(.error, error.localizedDescription)
        }
    }

    func rollback() async {
        await runBusy {
            let result = try await store.rollback(restart: true, force: true)
            let restartText = result.restarted ? "ZCode restarted." : "Login state restored. Launch ZCode manually."
            showToast(.success, "Rolled back to previous login state. \(restartText)")
            await reloadStatusAndList()
        }
    }

    func showToast(_ style: ToastStyle, _ message: String) {
        toast = ToastMessage(style: style, message: message)
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if toast?.message == message {
                toast = nil
            }
        }
    }

    func runBusy(_ operation: () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await operation()
        } catch {
            showToast(.error, error.localizedDescription)
        }
    }

    static func randomState() -> String {
        let bytes = (0..<16).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
