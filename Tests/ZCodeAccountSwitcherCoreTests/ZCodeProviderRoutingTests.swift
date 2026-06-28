import XCTest
@testable import ZCodeAccountSwitcherCore

final class ZCodeProviderRoutingTests: XCTestCase {
    func testZaiOAuthRoutingWritesJWTOnlyToStartPlan() throws {
        let secret = ZCodeCredentialCrypto.defaultCredentialSecret()
        let jwt = "\(TestSupport.base64URL(#"{"alg":"none"}"#)).\(TestSupport.base64URL(#"{"user_id":"credential-user"}"#)).signature"
        let credentials = """
        {
          "oauth:active_provider": "\(try ZCodeCredentialCrypto.encrypt("zai", secret: secret))",
          "zcodejwttoken": "\(try ZCodeCredentialCrypto.encrypt(jwt, secret: secret))"
        }
        """
        let config = """
        {
          "provider": {
            "builtin:zai-start-plan": {
              "enabled": false,
              "systemDisabledReason": "coding_plan_not_entitled",
              "options": { "apiKey": "old", "baseURL": "https://zcode.z.ai/api/v1/zcode-plan/anthropic" }
            },
            "builtin:zai-coding-plan": {
              "enabled": true,
              "options": { "apiKey": "eyJstale.jwt.signature", "baseURL": "https://api.z.ai/api/anthropic" }
            },
            "builtin:zai": {
              "enabled": true,
              "options": { "apiKey": "real-user-api-key", "baseURL": "https://api.z.ai/api/anthropic" }
            }
          }
        }
        """

        let data = try ZCodeProviderRouting.patchedConfigData(credentialsText: credentials, configText: config)
        let patched = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let providers = patched?["provider"] as? [String: Any]

        let start = providers?["builtin:zai-start-plan"] as? [String: Any]
        let startOptions = start?["options"] as? [String: Any]
        XCTAssertEqual(start?["enabled"] as? Bool, true)
        XCTAssertNil(start?["systemDisabledReason"])
        XCTAssertEqual(startOptions?["apiKey"] as? String, jwt)

        let coding = providers?["builtin:zai-coding-plan"] as? [String: Any]
        let codingOptions = coding?["options"] as? [String: Any]
        XCTAssertEqual(codingOptions?["apiKey"] as? String, "")

        let apiKey = providers?["builtin:zai"] as? [String: Any]
        let apiKeyOptions = apiKey?["options"] as? [String: Any]
        XCTAssertEqual(apiKeyOptions?["apiKey"] as? String, "real-user-api-key")
    }
}
