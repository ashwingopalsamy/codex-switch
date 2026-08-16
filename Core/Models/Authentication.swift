import Foundation

public enum AuthenticationState: Equatable, Sendable {
    case idle
    case preparing
    case requestingLoginURL
    case openingBrowser
    case awaitingCallback
    case verifying
    case completed
    case cancelled
    case failed(String)
}

public struct LoginAttempt: Equatable, Sendable {
    public let loginID: String
    public let authURL: URL

    public init(loginID: String, authURL: URL) {
        self.loginID = loginID
        self.authURL = authURL
    }
}

public enum AuthenticationEvent: Equatable, Sendable {
    case loginCompleted(loginID: String, success: Bool)
    case accountUpdated(authMode: String?)
}
