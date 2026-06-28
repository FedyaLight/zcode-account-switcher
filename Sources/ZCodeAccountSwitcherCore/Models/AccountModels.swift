import Foundation

public struct AccountMeta: Codable, Identifiable, Equatable {
    public var id: String
    public var shortId: String?
    public var emailShortId: String?
    public var userId: String?
    public var provider: String?
    public var label: String?
    public var email: String?
    public var name: String?
    public var avatar: String?
    public var customerId: String?
    public var userKey: String?
    public var source: String?
    public var note: String?
    public var capturedAt: Int64?

    public init(
        id: String,
        shortId: String? = nil,
        emailShortId: String? = nil,
        userId: String? = nil,
        provider: String? = nil,
        label: String? = nil,
        email: String? = nil,
        name: String? = nil,
        avatar: String? = nil,
        customerId: String? = nil,
        userKey: String? = nil,
        source: String? = nil,
        note: String? = nil,
        capturedAt: Int64? = nil
    ) {
        self.id = id
        self.shortId = shortId
        self.emailShortId = emailShortId
        self.userId = userId
        self.provider = provider
        self.label = label
        self.email = email
        self.name = name
        self.avatar = avatar
        self.customerId = customerId
        self.userKey = userKey
        self.source = source
        self.note = note
        self.capturedAt = capturedAt
    }

    public var displayName: String {
        let candidates = [label, email, name, shortId, id]
        return candidates.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }.first ?? id
    }
}

public struct AccountSnapshot: Codable, Equatable {
    public var credentials: String
    public var config: String

    public init(credentials: String, config: String) {
        self.credentials = credentials
        self.config = config
    }
}

public struct CredentialProfile: Equatable {
    public var activeProvider: String
    public var email: String?
    public var name: String?
    public var avatar: String?
    public var credentialUserId: String?
    public var zcodeUserId: String?
    public var customerId: String?
    public var accessUserId: String?
    public var userKey: String?
    public var zcodeJWT: String?

    public init(
        activeProvider: String,
        email: String? = nil,
        name: String? = nil,
        avatar: String? = nil,
        credentialUserId: String? = nil,
        zcodeUserId: String? = nil,
        customerId: String? = nil,
        accessUserId: String? = nil,
        userKey: String? = nil,
        zcodeJWT: String? = nil
    ) {
        self.activeProvider = activeProvider
        self.email = email
        self.name = name
        self.avatar = avatar
        self.credentialUserId = credentialUserId
        self.zcodeUserId = zcodeUserId
        self.customerId = customerId
        self.accessUserId = accessUserId
        self.userKey = userKey
        self.zcodeJWT = zcodeJWT
    }
}

public struct SnapshotHealth: Codable, Equatable {
    public enum Status: String, Codable {
        case healthy
        case warning
        case error
    }

    public var status: Status
    public var summary: String
    public var warnings: [String]
    public var errors: [String]

    public init(status: Status, summary: String, warnings: [String] = [], errors: [String] = []) {
        self.status = status
        self.summary = summary
        self.warnings = warnings
        self.errors = errors
    }
}

public struct AccountRecord: Identifiable, Equatable {
    public var id: String { meta.id }
    public var meta: AccountMeta
    public var sizeKb: Int
    public var health: SnapshotHealth

    public init(
        meta: AccountMeta,
        sizeKb: Int = 0,
        health: SnapshotHealth
    ) {
        self.meta = meta
        self.sizeKb = sizeKb
        self.health = health
    }
}

public struct AccountFingerprint: Codable, Equatable {
    public var userId: String
    public var shortId: String
    public var emailShortId: String
    public var provider: String
    public var label: String
    public var email: String?
    public var name: String?
    public var avatar: String?
    public var customerId: String?
    public var userKey: String?
    public var source: String

    public init(
        userId: String,
        shortId: String,
        emailShortId: String,
        provider: String,
        label: String,
        email: String? = nil,
        name: String? = nil,
        avatar: String? = nil,
        customerId: String? = nil,
        userKey: String? = nil,
        source: String
    ) {
        self.userId = userId
        self.shortId = shortId
        self.emailShortId = emailShortId
        self.provider = provider
        self.label = label
        self.email = email
        self.name = name
        self.avatar = avatar
        self.customerId = customerId
        self.userKey = userKey
        self.source = source
    }
}

public struct AppStatus: Equatable {
    public var current: AccountFingerprint?
    public var zcodeRunning: Bool

    public init(current: AccountFingerprint?, zcodeRunning: Bool) {
        self.current = current
        self.zcodeRunning = zcodeRunning
    }
}
