import XCTest
@testable import ZCodeAccountSwitcherCore

final class CryptoAndFingerprintTests: XCTestCase {
    func testCredentialCryptoRoundTrip() throws {
        let secret = "unit-test-secret"
        let encrypted = try ZCodeCredentialCrypto.encrypt("hello", secret: secret)
        XCTAssertTrue(ZCodeCredentialCrypto.isEncrypted(encrypted))
        XCTAssertEqual(try ZCodeCredentialCrypto.decrypt(encrypted, secret: secret), "hello")
    }

    func testDecodeJWTPayload() throws {
        let payload = #"{"user_id":"user-123","customer_id":"customer-456"}"#
        let jwt = "header.\(TestSupport.base64URL(payload)).signature"
        let decoded = JWTSupport.decodePayload(jwt)
        XCTAssertEqual(decoded?["user_id"] as? String, "user-123")
        XCTAssertEqual(decoded?["customer_id"] as? String, "customer-456")
    }

    func testFingerprintFromConfigJWT() throws {
        let jwt = "header.\(TestSupport.base64URL(#"{"user_id":"abcdef123456"}"#)).signature"
        let credentials = #"{"oauth:active_provider":"zai"}"#
        let config = """
        {
          "provider": {
            "builtin:zai": {
              "enabled": true,
              "options": { "apiKey": "\(jwt)" }
            }
          }
        }
        """

        let fingerprint = FingerprintExtractor().extractFingerprint(credentialsText: credentials, configText: config)
        XCTAssertEqual(fingerprint?.userId, "abcdef123456")
        XCTAssertEqual(fingerprint?.shortId, "abcdef12")
        XCTAssertEqual(fingerprint?.provider, "builtin:zai")
    }

    func testFingerprintPrefersCredentialsOverStaleConfig() throws {
        let secret = ZCodeCredentialCrypto.defaultCredentialSecret()
        let credentialsJWT = "header.\(TestSupport.base64URL(#"{"user_id":"credential-user"}"#)).signature"
        let configJWT = "header.\(TestSupport.base64URL(#"{"user_id":"config-user"}"#)).signature"
        let userInfo = #"{"email":"credential@example.com","user_id":"credential-user"}"#
        let credentials = """
        {
          "oauth:active_provider": "\(try ZCodeCredentialCrypto.encrypt("zai", secret: secret))",
          "oauth:zai:user_info": "\(try ZCodeCredentialCrypto.encrypt(userInfo, secret: secret))",
          "zcodejwttoken": "\(try ZCodeCredentialCrypto.encrypt(credentialsJWT, secret: secret))"
        }
        """
        let config = """
        {
          "provider": {
            "builtin:zai": {
              "enabled": true,
              "options": { "apiKey": "\(configJWT)" }
            }
          }
        }
        """

        let fingerprint = FingerprintExtractor().extractFingerprint(credentialsText: credentials, configText: config)
        XCTAssertEqual(fingerprint?.userId, "credential-user")
        XCTAssertEqual(fingerprint?.email, "credential@example.com")
        XCTAssertEqual(fingerprint?.source, "credentials.zcodejwttoken+user_info")
    }
}
