import Foundation

public struct AccountsExportPayload: Codable {
    public var version: Int
    public var app: String
    public var exportedAt: Int64
    public var accounts: [ExportedAccount]

    public init(version: Int = 1, app: String = "zcode-account-switcher", exportedAt: Int64, accounts: [ExportedAccount]) {
        self.version = version
        self.app = app
        self.exportedAt = exportedAt
        self.accounts = accounts
    }
}

public struct ExportedAccount: Codable {
    public var meta: AccountMeta
    public var snapshot: AccountSnapshot

    public init(meta: AccountMeta, snapshot: AccountSnapshot) {
        self.meta = meta
        self.snapshot = snapshot
    }
}
