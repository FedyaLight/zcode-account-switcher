import AppKit
import Foundation
import ZCodeAccountSwitcherCore

@MainActor
final class AccountAppModel: ObservableObject {
    private static let hidesPrivateAccountDataKey = "hidesPrivateAccountData"

    @Published var accounts: [AccountRecord] = []
    @Published var status = AppStatus(current: nil, zcodeRunning: false)
    @Published var isLoading = false
    @Published var isBusy = false
    @Published var toast: ToastMessage?
    @Published var showingAddSheet = false
    @Published var showingDeleteConfirmation: AccountRecord?
    @Published var oauthSession: OAuthSession?
    @Published var hidesPrivateAccountData: Bool {
        didSet {
            UserDefaults.standard.set(hidesPrivateAccountData, forKey: Self.hidesPrivateAccountDataKey)
        }
    }

    let store: AccountStore
    var activeImportPanel: NSOpenPanel?
    lazy var oauthService = OAuthService(accountStore: store)
    var oauthCallbackServer: OAuthCallbackServer?

    init(store: AccountStore = AccountStore()) {
        hidesPrivateAccountData = UserDefaults.standard.bool(forKey: Self.hidesPrivateAccountDataKey)
        self.store = store
    }

    var currentAccountId: String? {
        status.current?.emailShortId.isEmpty == false ? status.current?.emailShortId : status.current?.shortId
    }

    var activeAccount: AccountRecord? {
        guard let currentAccountId else { return nil }
        return accounts.first { $0.id == currentAccountId }
    }

    var otherAccounts: [AccountRecord] {
        accounts.filter { $0.id != currentAccountId }
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
            showToast(.error, privacySafeErrorMessage(for: error))
        }
    }

    func capture(label: String?) async {
        await runBusy {
            let result = try store.capture(label: label, overwrite: false)
            if result.created {
                showToast(.success, hidesPrivateAccountData ? "Captured account." : "Captured \(result.meta.displayName).")
            } else {
                showToast(.info, hidesPrivateAccountData ? "Account already exists." : result.message ?? "Account already exists.")
            }
            await reloadStatusAndList()
        }
    }

    func switchToAccount(_ account: AccountRecord) async {
        await runBusy {
            _ = try await store.use(id: account.id, restart: false, force: true)
            let accountText = hidesPrivateAccountData ? "account" : account.meta.displayName
            showToast(.success, "Switched to \(accountText). Launch ZCode manually.")
            await reloadStatusAndList()
        }
    }

    func deleteAccount(_ account: AccountRecord) async {
        await runBusy {
            _ = try store.remove(id: account.id)
            showToast(.success, hidesPrivateAccountData ? "Deleted account." : "Deleted \(account.meta.displayName).")
            await reloadStatusAndList()
        }
    }

    func renameAccount(_ account: AccountRecord, label: String) async {
        do {
            _ = try store.rename(id: account.id, label: label)
            await reloadStatusAndList()
        } catch {
            showToast(.error, privacySafeErrorMessage(for: error))
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
            showToast(.error, privacySafeErrorMessage(for: error))
        }
    }

    func privacySafeErrorMessage(for error: Error) -> String {
        hidesPrivateAccountData ? "The operation failed." : error.localizedDescription
    }

    static func randomState() -> String {
        let bytes = (0..<16).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
