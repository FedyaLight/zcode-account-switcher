import Foundation

public struct ZCodePaths {
    public let home: URL
    public let settingsDirectory: URL
    public let settingFile: URL
    public let zcodeDataBaseDirectory: URL
    public let zcodeV2Directory: URL
    public let credentialsFile: URL
    public let configFile: URL
    public let codingPlanCacheFile: URL
    public let dataDirectory: URL
    public let accountsDirectory: URL
    public let lastBackupDirectory: URL

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.home = home
        self.settingsDirectory = home.appendingPathComponent(".zcode/v2", isDirectory: true)
        self.settingFile = settingsDirectory.appendingPathComponent("setting.json")
        self.zcodeDataBaseDirectory = Self.resolveZCodeDataBaseDirectory(
            home: home,
            settingFile: settingFile,
            environment: environment
        )
        self.zcodeV2Directory = zcodeDataBaseDirectory.appendingPathComponent(".zcode/v2", isDirectory: true)
        self.credentialsFile = zcodeV2Directory.appendingPathComponent("credentials.json")
        self.configFile = zcodeV2Directory.appendingPathComponent("config.json")
        self.codingPlanCacheFile = zcodeV2Directory.appendingPathComponent("coding-plan-cache.json")

        if let customDataDir = environment["ZCAS_DATA_DIR"], !customDataDir.isEmpty {
            self.dataDirectory = URL(fileURLWithPath: customDataDir, isDirectory: true)
        } else {
            self.dataDirectory = home
                .appendingPathComponent("Library/Application Support/ZCode Account Switcher", isDirectory: true)
        }

        self.accountsDirectory = dataDirectory.appendingPathComponent("accounts", isDirectory: true)
        self.lastBackupDirectory = dataDirectory.appendingPathComponent(".last", isDirectory: true)
    }

    public func ensureDataDirectories() throws {
        try FileManager.default.createDirectory(at: accountsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: lastBackupDirectory, withIntermediateDirectories: true)
    }

    public static func candidateZCodeApplications(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications/ZCode.app", isDirectory: true),
            home.appendingPathComponent("Applications/ZCode.app", isDirectory: true)
        ]
    }

    private static func resolveZCodeDataBaseDirectory(
        home: URL,
        settingFile: URL,
        environment: [String: String]
    ) -> URL {
        if let settingDataBaseDir = dataBaseDir(from: settingFile) {
            return settingDataBaseDir
        }

        if let environmentDataBaseDir = nativeAbsoluteURL(environment["ZCODE_DATA_BASE_DIR"]) {
            return environmentDataBaseDir
        }

        return home
    }

    private static func dataBaseDir(from settingFile: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: settingFile.path),
              let data = try? Data(contentsOf: settingFile),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["dataBaseDir"] as? String
        else {
            return nil
        }
        return nativeAbsoluteURL(raw)
    }

    private static func nativeAbsoluteURL(_ value: String?) -> URL? {
        guard let value else { return nil }
        let path = (value as NSString).expandingTildeInPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, path.hasPrefix("/") else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
