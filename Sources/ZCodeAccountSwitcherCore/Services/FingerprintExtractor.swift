import Foundation

public struct FingerprintExtractor {
    private let paths: ZCodePaths

    public init(paths: ZCodePaths = ZCodePaths()) {
        self.paths = paths
    }

    public func currentFingerprint() -> AccountFingerprint? {
        extractFingerprint(
            credentialsText: try? String(contentsOf: paths.credentialsFile, encoding: .utf8),
            configText: try? String(contentsOf: paths.configFile, encoding: .utf8)
        )
    }

    public func extractFingerprint(credentialsText: String?, configText: String?) -> AccountFingerprint? {
        let profile = readCredentialProfile(credentialsText: credentialsText)

        if let profile,
           let userId = profile.zcodeUserId ?? profile.credentialUserId ?? profile.accessUserId {
            let shortId = String(userId.prefix(8))
            let emailShortId = profile.email.map { "em-" + Self.simpleHash($0.lowercased()).prefixString(10) } ?? shortId
            return AccountFingerprint(
                userId: userId,
                shortId: shortId,
                emailShortId: emailShortId,
                provider: profile.activeProvider,
                label: profile.email ?? profile.name ?? "Account-\(shortId)",
                email: profile.email,
                name: profile.name,
                avatar: profile.avatar,
                customerId: profile.customerId,
                userKey: profile.userKey,
                source: profile.email == nil ? "credentials.zcodejwttoken" : "credentials.zcodejwttoken+user_info"
            )
        }

        if let configText,
           let rawConfig = try? JSONSupport.parseDictionary(configText),
           let providers = rawConfig["provider"] as? [String: Any] {
            var candidates: [(id: String, provider: [String: Any], apiKey: String)] = []

            for (id, value) in providers {
                guard let provider = value as? [String: Any],
                      let options = provider["options"] as? [String: Any],
                      let apiKey = options["apiKey"] as? String,
                      !apiKey.hasPrefix("enc:"),
                      apiKey.count >= 30
                else { continue }
                candidates.append((id: id, provider: provider, apiKey: apiKey))
            }

            candidates.sort { lhs, rhs in
                JSONSupport.bool(lhs.provider["enabled"]) && !JSONSupport.bool(rhs.provider["enabled"])
            }

            for candidate in candidates {
                guard let payload = JWTSupport.decodePayload(candidate.apiKey),
                      let userId = JSONSupport.string(payload["user_id"] ?? payload["sub"])
                else { continue }

                let shortId = String(userId.prefix(8))
                let email = profile?.email
                let emailShortId = email.map { "em-" + Self.simpleHash($0.lowercased()).prefixString(10) } ?? shortId
                return AccountFingerprint(
                    userId: userId,
                    shortId: shortId,
                    emailShortId: emailShortId,
                    provider: candidate.id,
                    label: profile?.email ?? profile?.name ?? "Account-\(shortId)",
                    email: email,
                    name: profile?.name,
                    avatar: profile?.avatar,
                    customerId: profile?.customerId,
                    userKey: profile?.userKey,
                    source: email == nil ? "config.jwt" : "config.jwt+credentials.user_info"
                )
            }
        }

        if let credentialsText,
           let rawCredentials = try? JSONSupport.parseDictionary(credentialsText) {
            let activeProviderValue = JSONSupport.string(rawCredentials["oauth:active_provider"]) ?? ""
            let hash = Self.simpleHash(activeProviderValue)
            let shortId = String(hash.prefix(8))
            let email = profile?.email
            let emailShortId = email.map { "em-" + Self.simpleHash($0.lowercased()).prefixString(10) } ?? shortId
            return AccountFingerprint(
                userId: profile?.credentialUserId ?? profile?.accessUserId ?? "enc-\(hash)",
                shortId: shortId,
                emailShortId: emailShortId,
                provider: profile?.activeProvider ?? "(encrypted)",
                label: profile?.email ?? profile?.name ?? "Account-\(shortId)",
                email: email,
                name: profile?.name,
                avatar: profile?.avatar,
                customerId: profile?.customerId,
                userKey: profile?.userKey,
                source: email == nil ? "credentials.fallback" : "credentials.user_info"
            )
        }

        return nil
    }

    public func readCredentialProfile(credentialsText: String?) -> CredentialProfile? {
        guard let credentialsText,
              let rawCredentials = try? JSONSupport.parseDictionary(credentialsText)
        else { return nil }

        let activeProviderRaw = JSONSupport.string(rawCredentials["oauth:active_provider"])
        let activeProvider = (try? ZCodeCredentialCrypto.decrypt(activeProviderRaw)) ?? activeProviderRaw ?? "zai"
        let userInfoKey = "oauth:\(activeProvider):user_info"
        let userInfo = ZCodeCredentialCrypto.decryptJSON(JSONSupport.string(rawCredentials[userInfoKey]))

        let accessTokenKey = "oauth:\(activeProvider):access_token"
        let accessTokenRaw = JSONSupport.string(rawCredentials[accessTokenKey])
        let accessToken = (try? ZCodeCredentialCrypto.decrypt(accessTokenRaw)) ?? accessTokenRaw
        let accessPayload = JWTSupport.decodePayload(accessToken)
        let zcodeJWTRaw = JSONSupport.string(rawCredentials["zcodejwttoken"])
        let zcodeJWT = (try? ZCodeCredentialCrypto.decrypt(zcodeJWTRaw)) ?? zcodeJWTRaw
        let zcodePayload = JWTSupport.decodePayload(zcodeJWT)

        return CredentialProfile(
            activeProvider: activeProvider,
            email: JSONSupport.string(userInfo?["email"]),
            name: JSONSupport.string(userInfo?["name"])
                ?? JSONSupport.string(userInfo?["username"])
                ?? JSONSupport.string(userInfo?["displayName"]),
            avatar: JSONSupport.string(userInfo?["avatar"]),
            credentialUserId: JSONSupport.string(userInfo?["user_id"]),
            zcodeUserId: JSONSupport.string(zcodePayload?["user_id"] ?? zcodePayload?["sub"]),
            customerId: JSONSupport.string(zcodePayload?["customer_id"] ?? accessPayload?["customer_id"]),
            accessUserId: JSONSupport.string(accessPayload?["user_id"] ?? accessPayload?["sub"]),
            userKey: JSONSupport.string(zcodePayload?["user_key"] ?? accessPayload?["user_key"]),
            zcodeJWT: zcodeJWT
        )
    }

    public static func simpleHash(_ value: String) -> String {
        var hash: UInt32 = 5381
        for scalar in value.unicodeScalars {
            hash = ((hash &* 33) ^ UInt32(scalar.value)) & 0xffff_ffff
        }
        return String(hash, radix: 16)
    }
}

private extension String {
    func prefixString(_ count: Int) -> String {
        String(prefix(count))
    }
}
