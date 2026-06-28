import XCTest
@testable import ZCodeAccountSwitcherCore

final class ZCodePathsAndStoreTests: XCTestCase {
    func testZCodePathsHonorSettingDataBaseDir() throws {
        let home = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let dataBaseDir = home.appendingPathComponent("ZCodeData", isDirectory: true)
        let settingFile = home
            .appendingPathComponent(".zcode/v2", isDirectory: true)
            .appendingPathComponent("setting.json")
        try JSONSupport.writeJSONObject(["dataBaseDir": dataBaseDir.path], to: settingFile)

        let paths = ZCodePaths(home: home, environment: [:])
        XCTAssertEqual(paths.settingFile.path, settingFile.path)
        XCTAssertEqual(
            paths.zcodeV2Directory.path,
            dataBaseDir.appendingPathComponent(".zcode/v2", isDirectory: true).path
        )
    }

    func testWriteSnapshotRestoresExactConfigAndClearsPlanCache() throws {
        let home = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let paths = ZCodePaths(home: home, environment: [:])
        let store = AccountStore(paths: paths)
        try FileManager.default.createDirectory(at: paths.zcodeV2Directory, withIntermediateDirectories: true)

        let secret = ZCodeCredentialCrypto.defaultCredentialSecret()
        let credentials = """
        {
          "oauth:active_provider": "\(try ZCodeCredentialCrypto.encrypt("zai", secret: secret))",
          "zcodejwttoken": "\(try ZCodeCredentialCrypto.encrypt("header.payload.signature", secret: secret))"
        }
        """
        let config = #"{"provider":{"builtin:zai":{"enabled":false,"options":{"apiKey":"snapshot-only"}}}}"#
        try Data("stale".utf8).write(to: paths.codingPlanCacheFile)
        try JSONSupport.writeJSONObject(
            [
                "providerFamilyDomain": "bigmodel",
                "modelProviderFamilyModes": ["zai": "apikey"]
            ],
            to: paths.settingFile
        )

        try store.writeSnapshot(AccountSnapshot(credentials: credentials, config: config))

        let writtenConfig = try JSONSupport.readDictionary(from: paths.configFile)
        let originalConfig = try JSONSupport.parseDictionary(config)
        XCTAssertEqual(
            JSONSupport.bool(((writtenConfig["provider"] as? [String: Any])?["builtin:zai"] as? [String: Any])?["enabled"]),
            JSONSupport.bool(((originalConfig["provider"] as? [String: Any])?["builtin:zai"] as? [String: Any])?["enabled"])
        )
        XCTAssertEqual(
            (((writtenConfig["provider"] as? [String: Any])?["builtin:zai"] as? [String: Any])?["options"] as? [String: Any])?["apiKey"] as? String,
            "snapshot-only"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.codingPlanCacheFile.path))

        let setting = try JSONSupport.readDictionary(from: paths.settingFile)
        XCTAssertEqual(setting["providerFamilyDomain"] as? String, "zai")
        XCTAssertEqual((setting["modelProviderFamilyModes"] as? [String: Any])?["zai"] as? String, "oauth")
    }
}
