import Foundation

public final class CodexConfigManager: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    @discardableResult
    public func ensureFileCredentialStorage(for profile: CodexProfile, backupRoot: URL) throws -> URL? {
        let configURL = profile.codexHomeURL.appendingPathComponent("config.toml")
        try SecureFileSystem.rejectSymlink(configURL, fileManager: fileManager)
        try SecureFileSystem.rejectSymlink(backupRoot, fileManager: fileManager)
        let existingData = fileManager.fileExists(atPath: configURL.path) ? try Data(contentsOf: configURL) : nil
        let existingText = existingData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let updatedText = replacingCredentialStore(in: existingText)

        if updatedText == existingText, existingData != nil {
            return nil
        }

        var backupURL: URL?
        if let existingData {
            try SecureFileSystem.createDirectory(backupRoot, fileManager: fileManager)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let name = "\(profile.id.uuidString)-\(stamp)-config.toml"
            let candidate = backupRoot.appendingPathComponent(name)
            try SecureFileSystem.writeAtomically(existingData, to: candidate, fileManager: fileManager)
            backupURL = candidate
        }

        let data = Data(updatedText.utf8)
        try SecureFileSystem.writeAtomically(data, to: configURL, fileManager: fileManager)
        return backupURL
    }

    private func replacingCredentialStore(in text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var found = false
        var rewritten: [String] = []
        var tableStarted = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.hasPrefix("#"), trimmed.hasPrefix("[") {
                tableStarted = true
            }

            let isTopLevelKey: Bool = {
                guard !tableStarted, !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else {
                    return false
                }
                return trimmed[..<equals].trimmingCharacters(in: .whitespaces) == "cli_auth_credentials_store"
            }()

            if isTopLevelKey {
                if found {
                    // Duplicate top-level keys are invalid TOML. Keep one
                    // canonical setting while preserving all unrelated text.
                    continue
                }
                let equals = trimmed.firstIndex(of: "=")!
                let valueStart = trimmed.index(after: equals)
                let comment = trimmed[valueStart...].firstIndex(of: "#").map { String(trimmed[$0...]) } ?? ""
                let keyPrefix = String(trimmed[..<equals])
                rewritten.append("\(keyPrefix)= \"file\"\(comment.isEmpty ? "" : " \(comment)")")
                found = true
            } else {
                rewritten.append(line)
            }
        }

        if found {
            return rewritten.joined(separator: "\n")
        }
        let insertion = "cli_auth_credentials_store = \"file\""
        if let firstTable = rewritten.firstIndex(where: {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return !trimmed.hasPrefix("#") && trimmed.hasPrefix("[")
        }) {
            rewritten.insert(insertion, at: firstTable)
            return rewritten.joined(separator: "\n")
        }
        let prefix = text.isEmpty || text.hasSuffix("\n") ? text : text + "\n"
        return prefix + insertion + "\n"
    }
}
