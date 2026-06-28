import Foundation

public struct OAuthService {
    public static let appId = "client_P8X5CMWmlaRO9gyO-KSqtg"
    public static let redirectURI = "zcode://zai-auth/callback"
    public static let authorizeURL = URL(string: "https://chat.z.ai/api/oauth/authorize")!
    public static let tokenURL = URL(string: "https://zcode.z.ai/api/v1/oauth/token")!
    public static let businessLoginURL = URL(string: "https://api.z.ai/api/auth/z/login")!

    private let accountStore: AccountStore
    private let quotaService: QuotaService
    private let session: URLSession

    public init(
        accountStore: AccountStore,
        quotaService: QuotaService = QuotaService(),
        session: URLSession = .shared
    ) {
        self.accountStore = accountStore
        self.quotaService = quotaService
        self.session = session
    }

    public func buildAuthorizeURL(state: String, redirectURI: String = Self.redirectURI) -> URL {
        var components = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Self.appId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state)
        ]
        return components.url ?? Self.authorizeURL
    }

    public func parseCallback(_ url: URL, expectedState: String?) throws -> (code: String, state: String?) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty
        else {
            throw AccountError.oauthMissingCode
        }
        let state = components.queryItems?.first(where: { $0.name == "state" })?.value
        if let expectedState, let state, state != expectedState {
            throw AccountError.oauthStateMismatch
        }
        return (code, state)
    }

    public func exchangeCode(_ code: String, state: String, redirectURI: String = Self.redirectURI) async throws -> OAuthTokenSet {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "provider": "zai",
            "code": code,
            "redirect_uri": redirectURI,
            "state": state
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(statusCode), let json, (json["code"] as? Int) == 0 else {
            let message = JSONSupport.string(json?["msg"] ?? json?["message"])
                ?? "OAuth token exchange failed (HTTP \(statusCode))."
            throw AccountError.oauthTokenResponse(message)
        }
        guard let dataObject = json["data"] as? [String: Any],
              let token = JSONSupport.string(dataObject["token"]),
              let zai = dataObject["zai"] as? [String: Any],
              let accessToken = JSONSupport.string(zai["access_token"])
        else {
            throw AccountError.oauthTokenResponse("OAuth token response is missing data.token or data.zai.access_token.")
        }

        return OAuthTokenSet(
            token: token,
            zaiAccessToken: accessToken,
            refreshToken: JSONSupport.string(zai["refresh_token"]),
            user: (dataObject["user"] as? [String: Any]) ?? [:]
        )
    }

    @discardableResult
    public func finishLogin(tokenSet: OAuthTokenSet, label: String?, note: String = "", overwrite: Bool = true) async throws -> CaptureResult {
        let previousCredentials = try? String(contentsOf: accountStore.paths.credentialsFile, encoding: .utf8)
        let previousConfig = try? String(contentsOf: accountStore.paths.configFile, encoding: .utf8)

        try writeOAuthCredentials(tokenSet: tokenSet, userInfo: normalizeUserInfo(tokenSet.user))
        let captured = try accountStore.capture(label: label, note: note, overwrite: overwrite)

        if let previousCredentials {
            try JSONSupport.atomicWrite(Data(previousCredentials.utf8), to: accountStore.paths.credentialsFile)
        }
        if let previousConfig {
            try JSONSupport.atomicWrite(Data(previousConfig.utf8), to: accountStore.paths.configFile)
        }

        Task.detached { [tokenSet, quotaService, session] in
            await Self.triggerBusinessLogin(
                zaiAccessToken: tokenSet.zaiAccessToken,
                zcodeJWT: tokenSet.token,
                quotaService: quotaService,
                session: session
            )
        }

        return captured
    }

    public func writeOAuthCredentials(tokenSet: OAuthTokenSet, userInfo: [String: Any]) throws {
        try backupCurrentLoginState(reason: "oauth")

        var credentials = try JSONSupport.readDictionary(from: accountStore.paths.credentialsFile, fallback: [:])
        var config = try JSONSupport.readDictionary(from: accountStore.paths.configFile, fallback: [:])

        credentials["oauth:active_provider"] = try ZCodeCredentialCrypto.encrypt("zai")
        if let accessToken = tokenSet.zaiAccessToken {
            credentials["oauth:zai:access_token"] = try ZCodeCredentialCrypto.encrypt(accessToken)
        }
        if let refreshToken = tokenSet.refreshToken {
            credentials["oauth:zai:refresh_token"] = try ZCodeCredentialCrypto.encrypt(refreshToken)
        }
        credentials["zcodejwttoken"] = try ZCodeCredentialCrypto.encrypt(tokenSet.token)
        credentials["oauth:zai:user_info"] = try ZCodeCredentialCrypto.encrypt(try JSONSupport.compactJSONString(userInfo))

        ZCodeProviderRouting.applyZaiOAuthRouting(config: &config, zcodeJWT: tokenSet.token)

        try JSONSupport.writeJSONObject(credentials, to: accountStore.paths.credentialsFile, pretty: true)
        try JSONSupport.writeJSONObject(config, to: accountStore.paths.configFile, pretty: true)
    }

    public func normalizeUserInfo(_ user: [String: Any]) -> [String: Any] {
        [
            "email": JSONSupport.string(user["email"] ?? user["mail"]) ?? "",
            "name": JSONSupport.string(user["name"] ?? user["username"] ?? user["nickName"] ?? user["displayName"]) ?? "",
            "avatar": JSONSupport.string(user["avatar"] ?? user["avatarUrl"] ?? user["picture"]) ?? "",
            "user_id": JSONSupport.string(user["user_id"] ?? user["userId"] ?? user["id"] ?? user["customerNumber"] ?? user["sub"]) ?? ""
        ]
    }

    private func backupCurrentLoginState(reason: String) throws {
        let backupDirectory = accountStore.paths.lastBackupDirectory
            .appendingPathComponent("\(reason)-\(TimeSupport.timestampName())", isDirectory: true)
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: accountStore.paths.credentialsFile.path) {
            try FileManager.default.copyItem(
                at: accountStore.paths.credentialsFile,
                to: backupDirectory.appendingPathComponent("credentials.json")
            )
        }
        if FileManager.default.fileExists(atPath: accountStore.paths.configFile.path) {
            try FileManager.default.copyItem(
                at: accountStore.paths.configFile,
                to: backupDirectory.appendingPathComponent("config.json")
            )
        }
    }

    private static func triggerBusinessLogin(
        zaiAccessToken: String?,
        zcodeJWT: String,
        quotaService: QuotaService,
        session: URLSession
    ) async {
        if let zaiAccessToken {
            var request = URLRequest(url: businessLoginURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue("application/json", forHTTPHeaderField: "accept")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["token": zaiAccessToken])
            _ = try? await session.data(for: request)
        }

        _ = try? await quotaService.queryQuota(tokens: [zcodeJWT])
    }
}
