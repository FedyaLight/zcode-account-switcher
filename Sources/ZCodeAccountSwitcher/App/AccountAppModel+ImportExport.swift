import AppKit
import Foundation
import ZCodeAccountSwitcherCore

@MainActor
extension AccountAppModel {
    func exportAccounts() async {
        do {
            let payload = try store.exportAccounts()
            guard !payload.accounts.isEmpty else {
                showToast(.info, "No accounts to export.")
                return
            }
            let panel = NSSavePanel()
            panel.title = "Export Account Snapshots"
            panel.nameFieldStringValue = "zcode-accounts-\(TimeSupport.timestampName()).zcas.json"
            panel.allowedContentTypes = [.json]
            panel.level = .modalPanel
            NSApp.activate(ignoringOtherApps: true)
            let response = panel.runModal()
            guard response == .OK, let url = panel.url else { return }
            await runBusy {
                try JSONSupport.writeEncodable(payload, to: url, pretty: true)
                showToast(.success, "Exported \(payload.accounts.count) account\(payload.accounts.count == 1 ? "" : "s").")
            }
        } catch {
            showToast(.error, error.localizedDescription)
        }
    }

    func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import Account Snapshots"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.level = .modalPanel

        activeImportPanel = panel
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            let urls = activeImportPanel?.urls ?? []
            activeImportPanel = nil
            guard response == .OK, !urls.isEmpty else { return }
            Task { @MainActor in
                await self.importAccounts(from: urls)
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                panel.beginSheetModal(for: window, completionHandler: completion)
            } else {
                panel.begin(completionHandler: completion)
            }
        }
    }

    private func importAccounts(from urls: [URL]) async {
        guard !urls.isEmpty else { return }

        await runBusy {
            var totalImported = 0
            var totalUpdated = 0
            var totalSkipped = 0
            var failureMessages: [String] = []
            for url in urls {
                do {
                    let accessStarted = url.startAccessingSecurityScopedResource()
                    defer {
                        if accessStarted {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    let payload = try JSONSupport.readDecodable(AccountsExportPayload.self, from: url)
                    let result = try store.importAccounts(payload, overwrite: true)
                    totalImported += result.imported.count
                    totalUpdated += result.updated.count
                    totalSkipped += result.skipped.count
                    if let skipped = result.skipped.first {
                        failureMessages.append("\(skipped.id ?? url.lastPathComponent): \(skipped.reason)")
                    }
                } catch {
                    totalSkipped += 1
                    failureMessages.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            await reloadStatusAndList()
            let summary = "Imported \(totalImported), updated \(totalUpdated), skipped \(totalSkipped)."
            if totalImported + totalUpdated == 0, totalSkipped > 0 {
                showToast(.error, [summary, failureMessages.first].compactMap { $0 }.joined(separator: " "))
            } else if totalSkipped > 0 {
                showToast(.info, [summary, failureMessages.first].compactMap { $0 }.joined(separator: " "))
            } else {
                showToast(.success, summary)
            }
        }
    }
}
