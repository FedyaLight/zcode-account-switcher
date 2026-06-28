import AppKit
import Darwin
import Foundation

public struct ZCodeProcessService {
    public init() {}

    public func runningApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                return false
            }
            return Self.isZCodeApplication(
                localizedName: app.localizedName,
                bundleURL: app.bundleURL,
                bundleIdentifier: app.bundleIdentifier
            )
        }
    }

    public static func isZCodeApplication(
        localizedName: String?,
        bundleURL: URL?,
        bundleIdentifier: String?
    ) -> Bool {
        if bundleIdentifier?.lowercased() == "dev.zcode.app" {
            return true
        }
        if localizedName?.caseInsensitiveCompare("ZCode") == .orderedSame {
            return true
        }
        return bundleURL?.lastPathComponent.caseInsensitiveCompare("ZCode.app") == .orderedSame
    }

    public func isRunning() -> Bool {
        !runningApplications().isEmpty || !runningProcessIDs().isEmpty
    }

    @discardableResult
    public func closeZCode(waitSeconds: TimeInterval = 8) async -> Bool {
        let apps = runningApplications()
        guard !apps.isEmpty || !runningProcessIDs().isEmpty else { return true }

        for app in apps {
            app.terminate()
        }

        let softDeadline = Date().addingTimeInterval(min(3, waitSeconds))
        while Date() < softDeadline {
            if !isRunning() { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        signalRunningProcesses(SIGTERM)
        for app in runningApplications() {
            app.forceTerminate()
        }

        let forceDeadline = Date().addingTimeInterval(min(3, max(0, waitSeconds - 3)))
        while Date() < forceDeadline {
            if !isRunning() { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        signalRunningProcesses(SIGKILL)

        let deadline = Date().addingTimeInterval(max(0, waitSeconds - 3))
        while Date() < deadline {
            if !isRunning() { return true }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return !isRunning()
    }

    @discardableResult
    public func launchZCode() async throws -> Bool {
        for candidate in ZCodePaths.candidateZCodeApplications() {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try await openApplication(at: candidate)
            }
        }

        return try await openByName()
    }

    private func openApplication(at url: URL) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: app != nil)
            }
        }
    }

    private func openByName() async throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "ZCode"]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            return true
        }
        throw AccountError.zcodeNotFound
    }

    public func runningProcessIDs() -> [pid_t] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return output
            .split(separator: "\n")
            .compactMap { line -> pid_t? in
                parseProcessLine(String(line)).flatMap { pid, command in
                    guard pid != currentPID, Self.isZCodeProcessCommand(command) else {
                        return nil
                    }
                    return pid
                }
            }
    }

    public static func isZCodeProcessCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.contains("ZCodeAccountSwitcher.app/") || trimmed.contains("/Codex.app/") {
            return false
        }
        if trimmed == "ZCode" || trimmed.hasPrefix("ZCode ") {
            return true
        }
        if trimmed.hasPrefix("zcode-host-local-") {
            return true
        }
        if trimmed.contains("/ZCode.app/") {
            return true
        }
        if trimmed.contains("_productName=ZCode") {
            return true
        }
        if trimmed.contains("app-server"),
           trimmed.contains("--stdio"),
           trimmed.contains("zcode.cjs") {
            return true
        }
        return false
    }

    private func signalRunningProcesses(_ signal: Int32) {
        for pid in runningProcessIDs() {
            _ = Darwin.kill(pid, signal)
        }
    }

    private func parseProcessLine(_ line: String) -> (pid_t, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let split = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
            return nil
        }
        let pidPart = trimmed[..<split]
        let command = trimmed[split...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = pid_t(pidPart) else {
            return nil
        }
        return (pid, command)
    }
}
