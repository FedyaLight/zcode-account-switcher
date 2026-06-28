import AppKit
import Foundation
import ZCodeAccountSwitcherCore

@MainActor
extension AccountAppModel {
    func exportAccounts() async {
        await runBusy {
            let payload = try store.exportAccounts()
            guard !payload.accounts.isEmpty else {
                showToast(.info, "No accounts to export.")
                return
            }
            let panel = NSSavePanel()
            panel.title = "Export Account Snapshots"
            panel.nameFieldStringValue = "zcode-accounts-\(TimeSupport.timestampName()).zcas.json"
            panel.allowedContentTypes = [.json]
            let response = panel.runModal()
            guard response == .OK, let url = panel.url else { return }
            try JSONSupport.writeEncodable(payload, to: url, pretty: true)
            showToast(.success, "Exported \(payload.accounts.count) account\(payload.accounts.count == 1 ? "" : "s").")
        }
    }

    func importAccounts() async {
        await runBusy {
            let panel = NSOpenPanel()
            panel.title = "Import Account Snapshots"
            panel.allowedContentTypes = [.json]
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            let response = panel.runModal()
            guard response == .OK else { return }

            var totalImported = 0
            var totalUpdated = 0
            var totalSkipped = 0
            var failureMessages: [String] = []
            for url in panel.urls {
                do {
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
