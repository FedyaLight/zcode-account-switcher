import Foundation

public enum ZCodeProviderRouting {
    private static let zaiFamily = "zai"
    private static let startPlanProvider = "builtin:zai-start-plan"
    private static let codingPlanProvider = "builtin:zai-coding-plan"
    private static let apiKeyProvider = "builtin:zai"
    private static let planBaseURL = "https://zcode.z.ai/api/v1/zcode-plan/anthropic"

    public static func patchedConfigData(credentialsText: String, configText: String) throws -> Data {
        var config = try JSONSupport.parseDictionary(configText)
        _ = try applyOAuthRouting(credentialsText: credentialsText, config: &config)
        return try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
    }

    @discardableResult
    public static func applyOAuthRouting(credentialsText: String, config: inout [String: Any]) throws -> Bool {
        guard activeProvider(credentialsText: credentialsText) == zaiFamily,
              let token = zcodeJWT(credentialsText: credentialsText),
              token.starts(with: "eyJ")
        else {
            return false
        }
        return applyZaiOAuthRouting(config: &config, zcodeJWT: token)
    }

    @discardableResult
    public static func applyZaiOAuthRouting(config: inout [String: Any], zcodeJWT: String) -> Bool {
        var changed = false
        var providers = (config["provider"] as? [String: Any]) ?? [:]

        var startPlan = (providers[startPlanProvider] as? [String: Any]) ?? [:]
        var startOptions = (startPlan["options"] as? [String: Any]) ?? [:]
        if JSONSupport.string(startOptions["apiKey"]) != zcodeJWT {
            startOptions["apiKey"] = zcodeJWT
            changed = true
        }
        if JSONSupport.string(startOptions["baseURL"]) == nil {
            startOptions["baseURL"] = planBaseURL
            changed = true
        }
        if JSONSupport.bool(startPlan["enabled"]) == false {
            startPlan["enabled"] = true
            changed = true
        }
        if startPlan.removeValue(forKey: "systemDisabledReason") != nil {
            changed = true
        }
        startPlan["options"] = startOptions
        providers[startPlanProvider] = startPlan

        for id in [codingPlanProvider, apiKeyProvider] {
            guard var provider = providers[id] as? [String: Any],
                  var options = provider["options"] as? [String: Any],
                  let apiKey = JSONSupport.string(options["apiKey"]),
                  apiKey.starts(with: "eyJ")
            else {
                continue
            }
            options["apiKey"] = ""
            provider["options"] = options
            providers[id] = provider
            changed = true
        }

        config["provider"] = providers
        return changed
    }

    public static func activeProvider(credentialsText: String) -> String? {
        guard let credentials = try? JSONSupport.parseDictionary(credentialsText) else {
            return nil
        }
        let raw = JSONSupport.string(credentials["oauth:active_provider"])
        return (try? ZCodeCredentialCrypto.decrypt(raw)) ?? raw ?? zaiFamily
    }

    public static func zcodeJWT(credentialsText: String) -> String? {
        guard let credentials = try? JSONSupport.parseDictionary(credentialsText) else {
            return nil
        }
        let raw = JSONSupport.string(credentials["zcodejwttoken"])
        return ((try? ZCodeCredentialCrypto.decrypt(raw)) ?? raw)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
