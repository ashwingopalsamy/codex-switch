import Foundation

public struct CompatibilityReport: Codable, Hashable, Sendable {
    public let passed: Bool
    public let appVersion: String
    public let checkedPaths: [String]
    public let message: String

    public init(passed: Bool, appVersion: String, checkedPaths: [String], message: String) {
        self.passed = passed
        self.appVersion = appVersion
        self.checkedPaths = checkedPaths
        self.message = message
    }
}

public protocol CompatibilityProbing: Sendable {
    func app() throws -> ChatGPTApplication
    func check(profile: CodexProfile) throws -> CompatibilityReport
}

public struct CompatibilityProbe: CompatibilityProbing, Sendable {
    private let locator: ChatGPTLocator
    private let managedRoot: URL

    public init(locator: ChatGPTLocator = ChatGPTLocator(), managedRoot: URL = CodexSwitchPaths.applicationSupport) {
        self.locator = locator
        self.managedRoot = managedRoot
    }

    public func app() throws -> ChatGPTApplication {
        try locator.locate()
    }

    public func check(profile: CodexProfile) throws -> CompatibilityReport {
        let app = try locator.locate()
        let paths = [profile.codexHomeURL, profile.electronDataURL, profile.electronCacheURL]
        for path in paths {
            try SecureFileSystem.rejectSymlink(path)
            if profile.storageKind == .managed && !SecureFileSystem.isPath(path, inside: managedRoot) {
                throw ProfileError.invalidPath(path.path)
            }
        }
        return CompatibilityReport(
            passed: true,
            appVersion: app.version,
            checkedPaths: paths.map(\.path),
            message: "Structural checks passed. Runtime root isolation still requires the manual probe."
        )
    }
}
