import Foundation

struct OAuthSession: Equatable {
    var state: String
    var label: String?
    var authURL: URL
    var redirectURI: String
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    var style: ToastStyle
    var message: String
}

enum ToastStyle: Equatable {
    case success
    case error
    case info
}
