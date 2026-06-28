import CryptoKit
import Foundation

public enum ZCodeCredentialCrypto {
    public static let prefix = "enc:v1:"
    private static let nonceSize = 12
    private static let credentialSecretEnvironmentKey = "ZCODE_CREDENTIAL_SECRET"

    public static func isEncrypted(_ value: String?) -> Bool {
        value?.hasPrefix(prefix) == true
    }

    public static func defaultCredentialSecret(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        username: String = NSUserName()
    ) -> String {
        if let secret = environment[credentialSecretEnvironmentKey], !secret.isEmpty {
            return secret
        }
        return "zcode-credential-fallback:darwin:\(home.path):\(username.isEmpty ? "unknown" : username)"
    }

    public static func decrypt(_ value: String?, secret: String = defaultCredentialSecret()) throws -> String? {
        guard let value else { return nil }
        guard isEncrypted(value) else { return value }

        let body = String(value.dropFirst(prefix.count))
        let parts = body.split(separator: ".").map(String.init)
        guard parts.count == 3,
              let nonceData = Base64URL.decode(parts[0]),
              let tag = Base64URL.decode(parts[1]),
              let cipherText = Base64URL.decode(parts[2]),
              nonceData.count == nonceSize
        else {
            throw AccountError.invalidSnapshot
        }

        let key = symmetricKey(secret: secret)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: cipherText, tag: tag)
        let plainData = try AES.GCM.open(sealedBox, using: key)
        return String(decoding: plainData, as: UTF8.self)
    }

    public static func encrypt(_ plainText: String, secret: String = defaultCredentialSecret()) throws -> String {
        let key = symmetricKey(secret: secret)
        let sealedBox = try AES.GCM.seal(Data(plainText.utf8), using: key)
        guard let nonceData = sealedBox.nonce.data else {
            throw AccountError.invalidSnapshot
        }
        return [
            prefix,
            Base64URL.encode(nonceData),
            ".",
            Base64URL.encode(sealedBox.tag),
            ".",
            Base64URL.encode(sealedBox.ciphertext)
        ].joined()
    }

    public static func decryptJSON(_ value: String?) -> [String: Any]? {
        guard let plain = try? decrypt(value) else { return nil }
        return (try? JSONSupport.parseText(plain)) as? [String: Any]
    }

    private static func symmetricKey(secret: String) -> SymmetricKey {
        let digest = SHA256.hash(data: Data(secret.utf8))
        return SymmetricKey(data: Data(digest))
    }
}

private extension AES.GCM.Nonce {
    var data: Data? {
        withUnsafeBytes { pointer in
            guard let baseAddress = pointer.baseAddress else { return nil }
            return Data(bytes: baseAddress, count: pointer.count)
        }
    }
}
