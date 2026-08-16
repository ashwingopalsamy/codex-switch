import Foundation

public struct LaunchContext: Hashable, Sendable {
    public let profileID: UUID
    public let environment: [String: String]
    public let arguments: [String]

    public init(profile: CodexProfile, inheritedEnvironment: [String: String] = LaunchEnvironment.sanitized()) {
        var environment = inheritedEnvironment
        environment["CODEX_HOME"] = profile.codexHomePath
        self.profileID = profile.id
        self.environment = environment
        self.arguments = [
            "--user-data-dir=\(profile.electronDataPath)",
            "--disk-cache-dir=\(profile.electronCachePath)"
        ]
    }
}

public struct ChatGPTApplication: Hashable, Sendable {
    public let bundleURL: URL
    public let executableURL: URL
    public let codexExecutableURL: URL
    public let bundleIdentifier: String
    public let version: String
    public let teamIdentifier: String

    public init(
        bundleURL: URL,
        executableURL: URL,
        codexExecutableURL: URL,
        bundleIdentifier: String,
        version: String,
        teamIdentifier: String
    ) {
        self.bundleURL = bundleURL
        self.executableURL = executableURL
        self.codexExecutableURL = codexExecutableURL
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.teamIdentifier = teamIdentifier
    }
}
