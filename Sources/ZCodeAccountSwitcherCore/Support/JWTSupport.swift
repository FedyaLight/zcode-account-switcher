import Foundation

public enum JWTSupport {
    public static func decodePayload(_ jwt: String?) -> [String: Any]? {
        guard let jwt, !jwt.isEmpty else { return nil }
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        guard let data = Base64URL.decode(String(parts[1])) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
