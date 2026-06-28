import Foundation

public struct QuotaOverview: Codable, Equatable {
    public var total: Double?
    public var used: Double?
    public var remaining: Double?
    public var percentUsed: Double?
    public var isEmpty: Bool
    public var planTier: PlanTier?
    public var items: [QuotaItem]
    public var refreshedAt: Int64

    public init(
        total: Double?,
        used: Double?,
        remaining: Double?,
        percentUsed: Double?,
        isEmpty: Bool,
        planTier: PlanTier?,
        items: [QuotaItem],
        refreshedAt: Int64
    ) {
        self.total = total
        self.used = used
        self.remaining = remaining
        self.percentUsed = percentUsed
        self.isEmpty = isEmpty
        self.planTier = planTier
        self.items = items
        self.refreshedAt = refreshedAt
    }
}

public struct PlanTier: Codable, Equatable {
    public var label: String
    public var tier: String

    public init(label: String, tier: String) {
        self.label = label
        self.tier = tier
    }
}

public struct QuotaItem: Codable, Identifiable, Equatable {
    public var id: String { name + (periodEnd ?? "") }
    public var name: String
    public var total: Double?
    public var used: Double?
    public var remaining: Double?
    public var percentUsed: Double?
    public var unit: String
    public var periodEnd: String?

    public init(
        name: String,
        total: Double?,
        used: Double?,
        remaining: Double?,
        percentUsed: Double?,
        unit: String,
        periodEnd: String?
    ) {
        self.name = name
        self.total = total
        self.used = used
        self.remaining = remaining
        self.percentUsed = percentUsed
        self.unit = unit
        self.periodEnd = periodEnd
    }
}
