import Foundation

public struct SnapshotHealthValidator {
    private let quotaService: QuotaService

    public init(quotaService: QuotaService = QuotaService()) {
        self.quotaService = quotaService
    }

    public func validate(snapshot: AccountSnapshot, meta: AccountMeta? = nil) -> SnapshotHealth {
        var warnings: [String] = []
        var errors: [String] = []

        if snapshot.credentials.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Missing credentials login state.")
        }
        if snapshot.config.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Missing config login state.")
        }
        guard errors.isEmpty else {
            return finalize(warnings: warnings, errors: errors)
        }

        let credentials: [String: Any]
        let config: [String: Any]
        do {
            credentials = try JSONSupport.parseDictionary(snapshot.credentials)
        } catch {
            errors.append("credentials.json is not valid JSON.")
            credentials = [:]
        }
        do {
            config = try JSONSupport.parseDictionary(snapshot.config)
        } catch {
            errors.append("config.json is not valid JSON.")
            config = [:]
        }
        guard errors.isEmpty else {
            return finalize(warnings: warnings, errors: errors)
        }

        let tokens = quotaService.readCandidateTokens(credentials: credentials, config: config)
        if tokens.isEmpty {
            errors.append("No usable login or billing token was found.")
        }

        let providerInfo = extractProviderInfo(credentials: credentials, config: config)
        if providerInfo.apiKey == nil {
            warnings.append("No enabled provider apiKey was found.")
        }
        if (meta?.userId ?? providerInfo.userId) == nil {
            warnings.append("Could not resolve a stable user_id from this snapshot.")
        }

        let userInfoState = checkUserInfo(credentials: credentials, provider: providerInfo.provider)
        if let warning = userInfoState.warning {
            warnings.append(warning)
        }

        return finalize(warnings: warnings, errors: errors)
    }

    private func extractProviderInfo(credentials: [String: Any], config: [String: Any]) -> (provider: String?, apiKey: String?, userId: String?) {
        let activeProvider = readActiveProvider(credentials: credentials)
        guard let providers = config["provider"] as? [String: Any] else {
            return (activeProvider, nil, nil)
        }

        var candidates: [(id: String, enabled: Bool, apiKey: String, userId: String?)] = []
        for (id, value) in providers {
            guard let provider = value as? [String: Any],
                  let options = provider["options"] as? [String: Any],
                  let apiKey = options["apiKey"] as? String
            else { continue }
            let payload = JWTSupport.decodePayload(apiKey)
            candidates.append((
                id: id,
                enabled: JSONSupport.bool(provider["enabled"]),
                apiKey: apiKey,
                userId: JSONSupport.string(payload?["user_id"] ?? payload?["sub"])
            ))
        }
        candidates.sort { $0.enabled && !$1.enabled }
        let preferred = candidates.first
        return (activeProvider ?? preferred?.id, preferred?.apiKey, preferred?.userId)
    }

    private func readActiveProvider(credentials: [String: Any]) -> String? {
        guard let raw = JSONSupport.string(credentials["oauth:active_provider"]) else { return nil }
        return (try? ZCodeCredentialCrypto.decrypt(raw)) ?? raw
    }

    private func checkUserInfo(credentials: [String: Any], provider: String?) -> (canDecrypt: Bool, warning: String?) {
        var keys: [String] = []
        if let provider { keys.append("oauth:\(provider):user_info") }
        keys.append(contentsOf: ["oauth:zai:user_info", "oauth:bigmodel:user_info"])

        for key in keys {
            guard let value = JSONSupport.string(credentials[key]) else { continue }
            if !ZCodeCredentialCrypto.isEncrypted(value) {
                return (true, nil)
            }
            if ZCodeCredentialCrypto.decryptJSON(value) != nil {
                return (true, nil)
            }
            return (false, "user_info exists, but cannot be decrypted on this Mac.")
        }

        return (false, "No user_info was found, so display details may be incomplete.")
    }

    private func finalize(warnings: [String], errors: [String]) -> SnapshotHealth {
        if let error = errors.first {
            return SnapshotHealth(status: .error, summary: error, warnings: warnings, errors: errors)
        }
        if let warning = warnings.first {
            return SnapshotHealth(status: .warning, summary: warning, warnings: warnings, errors: errors)
        }
        return SnapshotHealth(status: .healthy, summary: "Snapshot is complete and ready.", warnings: warnings, errors: errors)
    }
}
