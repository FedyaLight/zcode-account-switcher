import Foundation

public struct QuotaService {
    public static let billingCurrentURL = URL(string: "https://zcode.z.ai/api/v1/zcode-plan/billing/current")!
    public static let billingBalanceURL = URL(string: "https://zcode.z.ai/api/v1/zcode-plan/billing/balance")!
    public static let clientAppVersion = "4.1.10"
    public static let clientPlatform = "win32-x64"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func readCandidateTokens(credentials: [String: Any], config: [String: Any]) -> [String] {
        let activeProviderRaw = JSONSupport.string(credentials["oauth:active_provider"])
        let activeProvider = (try? ZCodeCredentialCrypto.decrypt(activeProviderRaw)) ?? activeProviderRaw ?? "zai"
        var tokens: [String] = []

        func add(_ value: Any?) {
            guard let raw = JSONSupport.string(value) else { return }
            let plain = (try? ZCodeCredentialCrypto.decrypt(raw)) ?? raw
            guard looksLikeToken(plain), !tokens.contains(plain) else { return }
            tokens.append(plain)
        }

        add(credentials["zcodejwttoken"])
        add(credentials["oauth:zai:access_token"])
        add(credentials["oauth:bigmodel:access_token"])
        add(credentials["oauth:\(activeProvider):access_token"])

        if let providers = config["provider"] as? [String: Any] {
            for value in providers.values {
                guard let provider = value as? [String: Any],
                      let options = provider["options"] as? [String: Any]
                else { continue }
                add(options["apiKey"])
            }
        }

        return tokens
    }

    public func queryQuota(tokens: [String]) async throws -> QuotaOverview {
        var lastError: Error?
        var authFailCount = 0

        for token in tokens {
            do {
                return try await queryQuota(token: token)
            } catch {
                lastError = error
                if error.localizedDescription.contains("HTTP 401") || error.localizedDescription.contains("HTTP 403") {
                    authFailCount += 1
                }
            }
        }

        if authFailCount > 0, authFailCount == tokens.count, let token = tokens.first {
            try await Task.sleep(nanoseconds: 1_500_000_000)
            do {
                return try await queryQuota(token: token)
            } catch {
                throw AccountError.oauthTokenResponse("This account token is expired. Delete and add the account again.")
            }
        }

        throw lastError ?? AccountError.oauthTokenResponse("Quota request failed.")
    }

    private func queryQuota(token: String) async throws -> QuotaOverview {
        let current = try await fetchBilling(url: buildBillingURL(Self.billingCurrentURL), token: token)
        let balance = try await fetchBilling(url: Self.billingBalanceURL, token: token)
        return normalizeQuota(currentData: current, balanceData: balance)
    }

    private func buildBillingURL(_ baseURL: URL) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "app_version", value: Self.clientAppVersion))
        queryItems.append(URLQueryItem(name: "platform", value: Self.clientPlatform))
        components.queryItems = queryItems
        return components.url ?? baseURL
    }

    private func fetchBilling(url: URL, token: String) async throws -> Any {
        let retryDelays: [UInt64] = [500_000_000, 1_500_000_000, 4_000_000_000]
        var lastError: Error?

        for attempt in 0...retryDelays.count {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "accept")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")

            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let parsed = data.isEmpty ? [:] : ((try? JSONSerialization.jsonObject(with: data)) ?? String(decoding: data, as: UTF8.self))
            if (200..<300).contains(statusCode) {
                return parsed
            }

            if statusCode == 429, attempt < retryDelays.count {
                lastError = AccountError.oauthTokenResponse("Server rate limited the quota request.")
                try await Task.sleep(nanoseconds: retryDelays[attempt])
                continue
            }

            if statusCode == 401 || statusCode == 403 {
                throw AccountError.oauthTokenResponse("Token expired or invalid (HTTP \(statusCode)).")
            }

            let message: String
            if let dictionary = parsed as? [String: Any] {
                message = JSONSupport.string(dictionary["message"] ?? dictionary["msg"] ?? dictionary["error"]) ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
            } else {
                message = String(describing: parsed)
            }
            throw AccountError.oauthTokenResponse("Quota API HTTP \(statusCode): \(message)")
        }

        throw lastError ?? AccountError.oauthTokenResponse("Quota request failed.")
    }

    private func normalizeQuota(currentData: Any, balanceData: Any) -> QuotaOverview {
        let current = unwrap(currentData)
        let balance = unwrap(balanceData)
        let pool = flattenNumbers(["current": current, "balance": balance])

        var total = sumNumbers(pool, names: ["total_units"])
            ?? firstNumber(pool, names: ["total", "totalQuota", "totalCredits", "quotaTotal", "amountTotal", "creditTotal"])
        var used = sumNumbers(pool, names: ["used_units"])
            ?? firstNumber(pool, names: ["used", "usedQuota", "usedCredits", "quotaUsed", "amountUsed", "consumed", "totalUsed"])
        var remaining = sumNumbers(pool, names: ["remaining_units"])
            ?? firstNumber(pool, names: ["remaining", "remain", "balance", "available", "availableQuota", "left", "quotaRemaining"])

        if total == nil, let used, let remaining {
            total = used + remaining
        }
        if used == nil, let total, let remaining {
            used = max(0, total - remaining)
        }
        if remaining == nil, let total, let used {
            remaining = max(0, total - used)
        }

        let percentUsed = total.flatMap { totalValue -> Double? in
            guard totalValue > 0, let used else { return nil }
            return min(100, max(0, (used / totalValue) * 100))
        }

        let plans = JSONSupport.array((current as? [String: Any])?["plans"]) ?? []
        let balances = JSONSupport.array((balance as? [String: Any])?["balances"]) ?? []

        return QuotaOverview(
            total: total,
            used: used,
            remaining: remaining,
            percentUsed: percentUsed,
            isEmpty: plans.isEmpty && balances.isEmpty,
            planTier: extractPlanTier(currentData),
            items: normalizeQuotaItems(balance),
            refreshedAt: TimeSupport.millisecondsNow
        )
    }

    private func normalizeQuotaItems(_ balance: Any) -> [QuotaItem] {
        guard let dictionary = balance as? [String: Any],
              let balances = dictionary["balances"] as? [[String: Any]]
        else { return [] }

        return balances.map { item in
            let total = toNumber(item["total_units"])
            let used = toNumber(item["used_units"])
            let remaining = toNumber(item["remaining_units"]) ?? toNumber(item["available_units"])
            let percentUsed = total.flatMap { totalValue -> Double? in
                guard totalValue > 0, let used else { return nil }
                return min(100, max(0, (used / totalValue) * 100))
            }
            return QuotaItem(
                name: JSONSupport.string(item["show_name"] ?? item["name"] ?? item["entitlement_id"] ?? item["plan_id"]) ?? "Unknown model",
                total: total,
                used: used,
                remaining: remaining,
                percentUsed: percentUsed,
                unit: JSONSupport.string(item["unit_type"] ?? item["meter"]) ?? "quota",
                periodEnd: JSONSupport.string(item["period_end"] ?? item["expires_at"])
            )
        }
    }

    private func extractPlanTier(_ currentData: Any) -> PlanTier? {
        guard let current = unwrap(currentData) as? [String: Any],
              let plans = current["plans"] as? [[String: Any]]
        else { return nil }

        let active = plans.filter {
            (JSONSupport.string($0["status"]) ?? "").lowercased() == "active"
        }
        guard !active.isEmpty else { return nil }

        func matches(_ plan: [String: Any], _ keyword: String) -> Bool {
            let id = (JSONSupport.string(plan["plan_id"]) ?? "").lowercased()
            let name = (JSONSupport.string(plan["name"]) ?? "").lowercased()
            return id.contains(keyword) || name.contains(keyword)
        }

        if active.contains(where: { matches($0, "max") }) { return PlanTier(label: "Max", tier: "max") }
        if active.contains(where: { matches($0, "pro") }) { return PlanTier(label: "Pro", tier: "pro") }
        if active.contains(where: { matches($0, "lite") }) { return PlanTier(label: "Lite", tier: "lite") }
        if active.contains(where: { matches($0, "start-plan") || matches($0, "start plan") }) {
            return PlanTier(label: "Start Plan", tier: "start")
        }
        return nil
    }

    private func unwrap(_ data: Any) -> Any {
        var current = data
        for _ in 0..<4 {
            guard let dictionary = current as? [String: Any] else { return current }
            if let data = dictionary["data"] {
                current = data
                continue
            }
            if let result = dictionary["result"] {
                current = result
                continue
            }
            break
        }
        return current
    }

    private func flattenNumbers(_ object: Any, prefix: String = "", out: inout [String: Double]) {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                let path = prefix.isEmpty ? key : "\(prefix).\(key)"
                if let number = toNumber(value) {
                    out[path] = number
                } else {
                    flattenNumbers(value, prefix: path, out: &out)
                }
            }
        } else if let array = object as? [Any] {
            for (index, value) in array.enumerated() {
                flattenNumbers(value, prefix: "\(prefix)[\(index)]", out: &out)
            }
        }
    }

    private func flattenNumbers(_ object: Any) -> [String: Double] {
        var out: [String: Double] = [:]
        flattenNumbers(object, out: &out)
        return out
    }

    private func firstNumber(_ values: [String: Double], names: Set<String>) -> Double? {
        for (path, value) in values {
            if let name = path.split(separator: ".").last, names.contains(String(name)) {
                return value
            }
        }
        return nil
    }

    private func sumNumbers(_ values: [String: Double], names: Set<String>) -> Double? {
        var total = 0.0
        var count = 0
        for (path, value) in values {
            if let name = path.split(separator: ".").last, names.contains(String(name)) {
                total += value
                count += 1
            }
        }
        return count > 0 ? total : nil
    }

    private func toNumber(_ value: Any?) -> Double? {
        if let double = value as? Double, double.isFinite { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue.isFinite ? number.doubleValue : nil }
        if let string = value as? String {
            let normalized = string.replacingOccurrences(of: ",", with: "")
            return Double(normalized)
        }
        return nil
    }

    private func looksLikeToken(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).count > 20
    }
}
