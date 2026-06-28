import XCTest
@testable import ZCodeAccountSwitcherCore

final class ZCodePathsAndStoreTests: XCTestCase {
    func testExportImportRoundTripWritesSnapshotsAndSkipsDuplicates() throws {
        let sourceHome = try TestSupport.temporaryDirectory()
        let destinationHome = try TestSupport.temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: sourceHome)
            try? FileManager.default.removeItem(at: destinationHome)
        }

        let sourceStore = AccountStore(paths: ZCodePaths(home: sourceHome, environment: [:]))
        let destinationStore = AccountStore(paths: ZCodePaths(home: destinationHome, environment: [:]))
        let meta = AccountMeta(
            id: "acct_1234",
            shortId: "acct",
            emailShortId: "acct_1234",
            provider: "zai",
            label: "Personal",
            email: "person@example.com",
            capturedAt: 1_000
        )
        let snapshot = AccountSnapshot(
            credentials: #"{"oauth:active_provider":"zai","zcodejwttoken":"token"}"#,
            config: #"{"provider":{"builtin:zai":{"enabled":true}}}"#
        )

        let firstImport = try sourceStore.importAccounts(AccountsExportPayload(exportedAt: 1_000, accounts: [
            ExportedAccount(meta: meta, snapshot: snapshot)
        ]))
        XCTAssertEqual(firstImport.imported.map(\.id), ["acct_1234"])
        XCTAssertTrue(firstImport.updated.isEmpty)
        XCTAssertTrue(firstImport.skipped.isEmpty)

        let exported = try sourceStore.exportAccounts()
        XCTAssertEqual(exported.accounts.count, 1)
        XCTAssertEqual(exported.accounts.first?.meta, meta)
        XCTAssertEqual(exported.accounts.first?.snapshot, snapshot)

        let destinationImport = try destinationStore.importAccounts(exported)
        XCTAssertEqual(destinationImport.imported.map(\.id), ["acct_1234"])
        XCTAssertTrue(destinationImport.updated.isEmpty)
        XCTAssertTrue(destinationImport.skipped.isEmpty)
        XCTAssertEqual(try destinationStore.load(id: "acct_1234"), snapshot)

        let duplicateImport = try destinationStore.importAccounts(exported)
        XCTAssertTrue(duplicateImport.imported.isEmpty)
        XCTAssertTrue(duplicateImport.updated.isEmpty)
        XCTAssertEqual(duplicateImport.skipped.count, 1)
        XCTAssertEqual(duplicateImport.skipped.first?.id, "acct_1234")

        let overwriteImport = try destinationStore.importAccounts(exported, overwrite: true)
        XCTAssertTrue(overwriteImport.imported.isEmpty)
        XCTAssertEqual(overwriteImport.updated.map(\.id), ["acct_1234"])
        XCTAssertTrue(overwriteImport.skipped.isEmpty)
    }

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
