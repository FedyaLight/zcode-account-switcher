import AppKit
import Foundation
import ZCodeAccountSwitcherCore

@MainActor
extension AccountAppModel {
    func startOAuth(label: String?) async {
        await runBusy {
            oauthCallbackServer?.stop()
            let state = Self.randomState()
            let callbackServer = try await OAuthCallbackServer.start()
            oauthCallbackServer = callbackServer
            let authURL = oauthService.buildAuthorizeURL(state: state, redirectURI: callbackServer.redirectURI)
            oauthSession = OAuthSession(
                state: state,
                label: label,
                authURL: authURL,
                redirectURI: callbackServer.redirectURI
            )
            NSWorkspace.shared.open(authURL)
            showToast(.info, "Browser login opened.")

            Task { [weak self, callbackServer] in
                do {
                    let callbackURL = try await callbackServer.waitForCallback()
                    await self?.completeOAuth(callbackURLString: callbackURL.absoluteString)
                } catch {
                    self?.finishOAuthWithError(error)
                }
            }
        }
    }

    func completeOAuth(callbackURLString: String? = nil) async {
        guard let session = oauthSession else { return }
        await runBusy {
            defer {
                oauthCallbackServer?.stop()
                oauthCallbackServer = nil
            }

            let url: URL
            if let callbackURLString, let parsed = URL(string: callbackURLString.trimmingCharacters(in: .whitespacesAndNewlines)) {
                url = parsed
            } else {
                throw AccountError.oauthMissingCode
            }
            let callback = try oauthService.parseCallback(url, expectedState: session.state)
            let tokenSet = try await oauthService.exchangeCode(
                callback.code,
                state: session.state,
                redirectURI: session.redirectURI
            )
            let result = try await oauthService.finishLogin(tokenSet: tokenSet, label: session.label, overwrite: true)
            oauthSession = nil
            showingAddSheet = false
            showToast(.success, "Added \(result.meta.displayName).")
            await reloadStatusAndList()
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard (url.scheme == "zcode" || url.scheme == "http"), oauthSession != nil else { return }
        Task {
            await completeOAuth(callbackURLString: url.absoluteString)
        }
    }

    func cancelOAuth() {
        oauthCallbackServer?.stop()
        oauthCallbackServer = nil
        oauthSession = nil
    }

    func finishOAuthWithError(_ error: Error) {
        guard oauthSession != nil else { return }
        oauthCallbackServer?.stop()
        oauthCallbackServer = nil
        oauthSession = nil
        showToast(.error, error.localizedDescription)
    }
}
