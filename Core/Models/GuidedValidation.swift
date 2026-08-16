import Foundation

public struct GuidedValidationAuthorization: Hashable, Sendable {
    public let appVersion: String
    public let bundleIdentifier: String
    public let teamIdentifier: String
    public let profileIDs: Set<UUID>

    public init?(app: ChatGPTApplication, profileIDs: Set<UUID>) {
        guard profileIDs.count == 2 else { return nil }
        self.appVersion = app.version
        self.bundleIdentifier = app.bundleIdentifier
        self.teamIdentifier = app.teamIdentifier
        self.profileIDs = profileIDs
    }

    public func matches(app: ChatGPTApplication) -> Bool {
        app.version == appVersion &&
            app.bundleIdentifier == bundleIdentifier &&
            app.teamIdentifier == teamIdentifier
    }

    public func permits(profileID: UUID, app: ChatGPTApplication) -> Bool {
        matches(app: app) && profileIDs.contains(profileID)
    }

    public func permitsTransition(sourceID: UUID, targetID: UUID, app: ChatGPTApplication) -> Bool {
        sourceID != targetID &&
            matches(app: app) &&
            profileIDs == Set([sourceID, targetID])
    }
}
