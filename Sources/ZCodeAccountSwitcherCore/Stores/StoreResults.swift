public struct CaptureResult: Equatable {
    public var id: String
    public var meta: AccountMeta
    public var created: Bool
    public var message: String?
}

public struct SwitchResult: Equatable {
    public var restarted: Bool
}

public struct ImportResult {
    public var imported: [AccountMeta]
    public var updated: [AccountMeta]
    public var skipped: [(id: String?, reason: String)]
}
