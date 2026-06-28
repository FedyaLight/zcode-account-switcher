import Foundation

public final class AccountStore {
    public let paths: ZCodePaths
    private let fingerprintExtractor: FingerprintExtractor
    private let healthValidator: SnapshotHealthValidator
    private let processService: ZCodeProcessService

    public init(
        paths: ZCodePaths = ZCodePaths(),
        fingerprintExtractor: FingerprintExtractor? = nil,
        healthValidator: SnapshotHealthValidator = SnapshotHealthValidator(),
        processService: ZCodeProcessService = ZCodeProcessService()
    ) {
        self.paths = paths
        self.fingerprintExtractor = fingerprintExtractor ?? FingerprintExtractor(paths: paths)
        self.healthValidator = healthValidator
        self.processService = processService
    }

    public func status() -> AppStatus {
        AppStatus(
            current: fingerprintExtractor.currentFingerprint(),
            zcodeRunning: processService.isRunning(),
            hasLastBackup: hasLastBackup()
        )
    }

    public func list() throws -> [AccountRecord] {
        try ensureStore()
        let files = try FileManager.default.contentsOfDirectory(
            at: paths.accountsDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasSuffix(".meta.json") }

        var records: [AccountRecord] = []
        for file in files {
            do {
                let meta = try JSONSupport.readDecodable(AccountMeta.self, from: file)
                let snapURL = snapshotURL(id: meta.id)
                let sizeKb = (try? FileManager.default.attributesOfItem(atPath: snapURL.path)[.size] as? NSNumber)
                    .map { Int(round($0.doubleValue / 1024.0)) } ?? 0
                let health: SnapshotHealth
                if let snapshot = try? load(id: meta.id) {
                    health = healthValidator.validate(snapshot: snapshot, meta: meta)
                } else {
                    health = SnapshotHealth(
                        status: .error,
                        summary: "Snapshot file is missing or unreadable.",
                        errors: ["Snapshot file is missing or unreadable."]
                    )
                }
                records.append(AccountRecord(meta: meta, sizeKb: sizeKb, health: health))
            } catch {
                continue
            }
        }

        return records.sorted {
            ($0.meta.capturedAt ?? 0) < ($1.meta.capturedAt ?? 0)
        }
    }

    public func capture(label: String? = nil, note: String = "", overwrite: Bool = false) throws -> CaptureResult {
        try ensureStore()
        guard let fingerprint = fingerprintExtractor.currentFingerprint() else {
            throw AccountError.missingLoginState("Could not extract an account fingerprint. Log in to ZCode first.")
        }

        let id = fingerprint.emailShortId.isEmpty ? fingerprint.shortId : fingerprint.emailShortId
        let metaURL = metadataURL(id: id)
        let exists = FileManager.default.fileExists(atPath: metaURL.path)
        if exists, !overwrite {
            let old = try JSONSupport.readDecodable(AccountMeta.self, from: metaURL)
            return CaptureResult(
                id: id,
                meta: old,
                created: false,
                message: "This account already exists as \(old.displayName)."
            )
        }

        let snapshot = try readSnapshot()
        try JSONSupport.writeEncodable(snapshot, to: snapshotURL(id: id), pretty: false)

        let meta = AccountMeta(
            id: id,
            shortId: fingerprint.shortId,
            emailShortId: fingerprint.emailShortId,
            userId: fingerprint.userId,
            provider: fingerprint.provider,
            label: clean(label) ?? fingerprint.label,
            email: fingerprint.email,
            name: fingerprint.name,
            avatar: fingerprint.avatar,
            customerId: fingerprint.customerId,
            userKey: fingerprint.userKey,
            source: fingerprint.source,
            note: note,
            capturedAt: TimeSupport.millisecondsNow
        )
        try JSONSupport.writeEncodable(meta, to: metaURL, pretty: true)
        return CaptureResult(id: id, meta: meta, created: true, message: nil)
    }

    public func load(id: String) throws -> AccountSnapshot {
        let id = try safeId(id)
        let url = snapshotURL(id: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AccountError.missingAccount(id)
        }
        return try JSONSupport.readDecodable(AccountSnapshot.self, from: url)
    }

    public func use(id: String, restart: Bool = true, force: Bool = true) async throws -> SwitchResult {
        let snapshot = try load(id: id)
        return try await switchTo(snapshot: snapshot, restart: restart, force: force)
    }

    public func remove(id: String) throws -> Bool {
        let id = try safeId(id)
        var removed = false
        for url in [metadataURL(id: id), snapshotURL(id: id)] {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
                removed = true
            }
        }
        return removed
    }

    public func rename(id: String, label: String, note: String? = nil) throws -> AccountMeta {
        let id = try safeId(id)
        let url = metadataURL(id: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AccountError.missingAccount(id)
        }
        var meta = try JSONSupport.readDecodable(AccountMeta.self, from: url)
        if let cleanLabel = clean(label) {
            meta.label = cleanLabel
        }
        if let note {
            meta.note = note
        }
        try JSONSupport.writeEncodable(meta, to: url, pretty: true)
        return meta
    }

    public func rollback(restart: Bool = true, force: Bool = true) async throws -> SwitchResult {
        let credentialsBackup = paths.lastBackupDirectory.appendingPathComponent("credentials.json")
        let configBackup = paths.lastBackupDirectory.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: credentialsBackup.path),
              FileManager.default.fileExists(atPath: configBackup.path)
        else {
            throw AccountError.missingLoginState("No .last backup exists.")
        }

        if processService.isRunning(), !force {
            throw AccountError.zcodeStillRunning
        }
        if processService.isRunning() {
            let ok = await processService.closeZCode()
            guard ok else { throw AccountError.zcodeCloseTimeout }
        }

        try writeSnapshotExact(AccountSnapshot(
            credentials: String(contentsOf: credentialsBackup, encoding: .utf8),
            config: String(contentsOf: configBackup, encoding: .utf8)
        ))
        try restoreLastSettingIfPresent()

        var launched = false
        if restart {
            launched = (try? await processService.launchZCode()) ?? false
        }
        return SwitchResult(restarted: launched)
    }

    public func exportAccounts(ids: [String]? = nil) throws -> AccountsExportPayload {
        let wanted = ids.map { Set($0) }
        let accounts = try list().compactMap { record -> ExportedAccount? in
            guard wanted == nil || wanted?.contains(record.id) == true else { return nil }
            let snapshot = try load(id: record.id)
            return ExportedAccount(meta: record.meta, snapshot: snapshot)
        }
        return AccountsExportPayload(exportedAt: TimeSupport.millisecondsNow, accounts: accounts)
    }

    public func importAccounts(_ payload: AccountsExportPayload, overwrite: Bool = false) throws -> ImportResult {
        try ensureStore()
        var imported: [AccountMeta] = []
        var skipped: [(id: String?, reason: String)] = []

        for account in payload.accounts {
            do {
                let id = try safeId(account.meta.id)
                guard !account.snapshot.credentials.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !account.snapshot.config.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    throw AccountError.invalidSnapshot
                }
                _ = try JSONSupport.parseDictionary(account.snapshot.credentials)
                _ = try JSONSupport.parseDictionary(account.snapshot.config)

                if !overwrite,
                   FileManager.default.fileExists(atPath: metadataURL(id: id).path) ||
                    FileManager.default.fileExists(atPath: snapshotURL(id: id).path) {
                    skipped.append((id: id, reason: "Already exists."))
                    continue
                }

                var meta = account.meta
                meta.id = id
                try JSONSupport.writeEncodable(account.snapshot, to: snapshotURL(id: id), pretty: false)
                try JSONSupport.writeEncodable(meta, to: metadataURL(id: id), pretty: true)
                imported.append(meta)
            } catch {
                skipped.append((id: account.meta.id, reason: error.localizedDescription))
            }
        }

        return ImportResult(imported: imported, skipped: skipped)
    }

    public func readSnapshot() throws -> AccountSnapshot {
        guard FileManager.default.fileExists(atPath: paths.credentialsFile.path) else {
            throw AccountError.missingLoginState(paths.credentialsFile.path)
        }
        guard FileManager.default.fileExists(atPath: paths.configFile.path) else {
            throw AccountError.missingLoginState(paths.configFile.path)
        }
        return AccountSnapshot(
            credentials: try String(contentsOf: paths.credentialsFile, encoding: .utf8),
            config: try String(contentsOf: paths.configFile, encoding: .utf8)
        )
    }

    public func writeSnapshot(_ snapshot: AccountSnapshot) throws {
        guard !snapshot.credentials.isEmpty, !snapshot.config.isEmpty else {
            throw AccountError.invalidSnapshot
        }
        try FileManager.default.createDirectory(at: paths.zcodeV2Directory, withIntermediateDirectories: true)
        let configData = try ZCodeProviderRouting.patchedConfigData(
            credentialsText: snapshot.credentials,
            configText: snapshot.config
        )
        try JSONSupport.atomicWrite(Data(snapshot.credentials.utf8), to: paths.credentialsFile)
        try JSONSupport.atomicWrite(configData, to: paths.configFile)
        try? updateZCodeRoutingForOAuthIfNeeded(snapshot: snapshot)
        clearCodingPlanCache()
    }

    public func metadataURL(id: String) -> URL {
        paths.accountsDirectory.appendingPathComponent("\(id).meta.json")
    }

    public func snapshotURL(id: String) -> URL {
        paths.accountsDirectory.appendingPathComponent("\(id).snap.json")
    }

    private func switchTo(snapshot: AccountSnapshot, restart: Bool, force: Bool) async throws -> SwitchResult {
        guard !snapshot.credentials.isEmpty, !snapshot.config.isEmpty else {
            throw AccountError.invalidSnapshot
        }

        let wasRunning = processService.isRunning()
        if wasRunning, !force {
            throw AccountError.zcodeStillRunning
        }
        if wasRunning {
            let ok = await processService.closeZCode()
            guard ok else { throw AccountError.zcodeCloseTimeout }
        }

        do {
            try backupCurrentLoginState()
            try writeSnapshot(snapshot)
        } catch {
            try? restoreLast()
            throw error
        }

        var launched = false
        if restart {
            if wasRunning {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            launched = (try? await processService.launchZCode()) ?? false
        }
        return SwitchResult(restarted: launched)
    }

    private func backupCurrentLoginState() throws {
        try FileManager.default.createDirectory(at: paths.lastBackupDirectory, withIntermediateDirectories: true)
        let snapshot = try readSnapshot()
        try JSONSupport.atomicWrite(Data(snapshot.credentials.utf8), to: paths.lastBackupDirectory.appendingPathComponent("credentials.json"))
        try JSONSupport.atomicWrite(Data(snapshot.config.utf8), to: paths.lastBackupDirectory.appendingPathComponent("config.json"))
        if FileManager.default.fileExists(atPath: paths.settingFile.path) {
            try JSONSupport.atomicWrite(
                Data(contentsOf: paths.settingFile),
                to: paths.lastBackupDirectory.appendingPathComponent("setting.json")
            )
        }
    }

    private func restoreLast() throws {
        let credentials = try String(contentsOf: paths.lastBackupDirectory.appendingPathComponent("credentials.json"), encoding: .utf8)
        let config = try String(contentsOf: paths.lastBackupDirectory.appendingPathComponent("config.json"), encoding: .utf8)
        try writeSnapshotExact(AccountSnapshot(credentials: credentials, config: config))
        try restoreLastSettingIfPresent()
    }

    private func writeSnapshotExact(_ snapshot: AccountSnapshot) throws {
        guard !snapshot.credentials.isEmpty, !snapshot.config.isEmpty else {
            throw AccountError.invalidSnapshot
        }
        try FileManager.default.createDirectory(at: paths.zcodeV2Directory, withIntermediateDirectories: true)
        try JSONSupport.atomicWrite(Data(snapshot.credentials.utf8), to: paths.credentialsFile)
        try JSONSupport.atomicWrite(Data(snapshot.config.utf8), to: paths.configFile)
    }

    private func updateZCodeRoutingForOAuthIfNeeded(snapshot: AccountSnapshot) throws {
        guard FileManager.default.fileExists(atPath: paths.settingFile.path),
              let profile = fingerprintExtractor.readCredentialProfile(credentialsText: snapshot.credentials),
              profile.activeProvider == "zai",
              profile.zcodeJWT?.isEmpty == false
        else {
            return
        }

        var setting = try JSONSupport.readDictionary(from: paths.settingFile, fallback: [:])
        var changed = false
        if JSONSupport.string(setting["providerFamilyDomain"]) != "zai" {
            setting["providerFamilyDomain"] = "zai"
            changed = true
        }

        var modes = (setting["modelProviderFamilyModes"] as? [String: Any]) ?? [:]
        if JSONSupport.string(modes["zai"]) != "oauth" {
            modes["zai"] = "oauth"
            setting["modelProviderFamilyModes"] = modes
            changed = true
        }

        if changed {
            try JSONSupport.writeJSONObject(setting, to: paths.settingFile, pretty: true)
        }
    }

    private func clearCodingPlanCache() {
        guard FileManager.default.fileExists(atPath: paths.codingPlanCacheFile.path) else {
            return
        }
        try? FileManager.default.removeItem(at: paths.codingPlanCacheFile)
    }

    private func restoreLastSettingIfPresent() throws {
        let backup = paths.lastBackupDirectory.appendingPathComponent("setting.json")
        guard FileManager.default.fileExists(atPath: backup.path) else {
            return
        }
        try FileManager.default.createDirectory(at: paths.settingFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSupport.atomicWrite(Data(contentsOf: backup), to: paths.settingFile)
    }

    private func hasLastBackup() -> Bool {
        FileManager.default.fileExists(atPath: paths.lastBackupDirectory.appendingPathComponent("credentials.json").path) &&
        FileManager.default.fileExists(atPath: paths.lastBackupDirectory.appendingPathComponent("config.json").path)
    }

    private func ensureStore() throws {
        try paths.ensureDataDirectories()
    }

    private func safeId(_ raw: String) throws -> String {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let regex = try NSRegularExpression(pattern: #"^[a-zA-Z0-9_-]{4,64}$"#)
        let range = NSRange(id.startIndex..<id.endIndex, in: id)
        guard regex.firstMatch(in: id, range: range) != nil else {
            throw AccountError.invalidAccountId(id)
        }
        return id
    }

    private func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
