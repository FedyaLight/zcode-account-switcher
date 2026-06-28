import Foundation

public enum AccountError: LocalizedError {
    case missingLoginState(String)
    case invalidSnapshot
    case missingAccount(String)
    case invalidAccountId(String)
    case zcodeStillRunning
    case zcodeCloseTimeout
    case zcodeNotFound
    case oauthStateMismatch
    case oauthMissingCode
    case oauthTokenResponse(String)

    public var errorDescription: String? {
        switch self {
        case .missingLoginState(let name):
            return "Missing ZCode login state file: \(name)"
        case .invalidSnapshot:
            return "The account snapshot is incomplete."
        case .missingAccount(let id):
            return "Account snapshot not found: \(id)"
        case .invalidAccountId(let id):
            return "Invalid account id: \(id)"
        case .zcodeStillRunning:
            return "ZCode is running. Close it first, or allow the switcher to close it."
        case .zcodeCloseTimeout:
            return "Timed out while closing ZCode. The switch was cancelled to avoid corrupting login state."
        case .zcodeNotFound:
            return "ZCode.app was not found. Install ZCode or launch it manually after switching."
        case .oauthStateMismatch:
            return "OAuth callback state does not match the current login session."
        case .oauthMissingCode:
            return "OAuth callback does not contain an authorization code."
        case .oauthTokenResponse(let message):
            return message
        }
    }
}
