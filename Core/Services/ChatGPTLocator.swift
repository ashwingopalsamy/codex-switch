import AppKit
import Foundation

public final class ChatGPTLocator: @unchecked Sendable {
    public static let expectedBundleIdentifier = "com.openai.codex"
    public static let expectedTeamIdentifier = "2DC432GLL2"
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func locate() throws -> ChatGPTApplication {
        let candidates: [URL] = [
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.expectedBundleIdentifier),
            URL(fileURLWithPath: "/Applications/ChatGPT.app")
        ].compactMap { $0 }

        guard let bundleURL = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }),
              let bundle = Bundle(url: bundleURL),
              let executableURL = bundle.executableURL,
              let bundleIdentifier = bundle.bundleIdentifier,
              bundleIdentifier == Self.expectedBundleIdentifier else {
            throw ProfileError.appNotFound
        }

        let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "unknown"
        let teamIdentifier = try signingTeamIdentifier(for: bundleURL)
        guard teamIdentifier == Self.expectedTeamIdentifier else {
            throw ProfileError.appSignatureInvalid
        }

        let codexExecutableURL = bundleURL
            .appendingPathComponent("Contents/Resources/codex")
        guard fileManager.isExecutableFile(atPath: codexExecutableURL.path) else {
            throw ProfileError.appNotFound
        }
        try verifyExecutableSignature(codexExecutableURL)

        return ChatGPTApplication(
            bundleURL: bundleURL,
            executableURL: executableURL,
            codexExecutableURL: codexExecutableURL,
            bundleIdentifier: bundleIdentifier,
            version: version,
            teamIdentifier: teamIdentifier
        )
    }

    private func signingTeamIdentifier(for bundleURL: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", "--verbose=4", bundleURL.path]
        let output = Pipe()
        process.standardError = output
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix("TeamIdentifier=") }) else {
            throw ProfileError.appSignatureInvalid
        }
        return String(line.dropFirst("TeamIdentifier=".count))
    }

    private func verifyExecutableSignature(_ executableURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--strict", executableURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ProfileError.appSignatureInvalid
        }
    }
}
