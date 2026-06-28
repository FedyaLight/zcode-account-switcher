import Foundation

public struct OAuthTokenSet: Equatable {
    public var token: String
    public var zaiAccessToken: String?
    public var refreshToken: String?
    public var user: [String: Any]

    public init(token: String, zaiAccessToken: String?, refreshToken: String?, user: [String: Any]) {
        self.token = token
        self.zaiAccessToken = zaiAccessToken
        self.refreshToken = refreshToken
        self.user = user
    }

    public static func == (lhs: OAuthTokenSet, rhs: OAuthTokenSet) -> Bool {
        lhs.token == rhs.token &&
        lhs.zaiAccessToken == rhs.zaiAccessToken &&
        lhs.refreshToken == rhs.refreshToken
    }
}
