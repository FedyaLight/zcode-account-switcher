import AppKit
import CoreServices
import SwiftUI

@main
struct ZCodeAccountSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AccountAppModel()

    var body: some Scene {
        WindowGroup("ZCode Account Switcher") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 680)
                .onAppear {
                    appDelegate.model = model
                    Task { await model.refresh() }
                }
                .onOpenURL { url in
                    model.handleIncomingURL(url)
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r")

                Button("Rollback") {
                    Task { await model.rollback() }
                }
                .disabled(!model.status.hasLastBackup)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AccountAppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        registerZCodeURLHandler()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            model?.handleIncomingURL(url)
        }
    }

    private func registerZCodeURLHandler() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        LSSetDefaultHandlerForURLScheme("zcode" as CFString, bundleIdentifier as CFString)
    }
}
