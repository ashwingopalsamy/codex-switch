import Foundation

public final class ProfileStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    public let root: URL

    public init(root: URL = CodexSwitchPaths.applicationSupport, fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public var documentURL: URL { root.appendingPathComponent("profiles.json") }
    public var profilesRoot: URL { root.appendingPathComponent("p", isDirectory: true) }
    public var legacyProfilesRoot: URL { root.appendingPathComponent("Profiles", isDirectory: true) }
    public var journalURL: URL { root.appendingPathComponent("switch-transaction.json") }
    public var operationLockURL: URL { root.appendingPathComponent("switch-operation.lock") }
    public var configBackupsURL: URL { root.appendingPathComponent("Config Backups", isDirectory: true) }

    public func managedProfileRoot(for id: UUID) -> URL {
        profilesRoot.appendingPathComponent(compactDirectoryName(for: id), isDirectory: true)
    }

    public func load() throws -> ProfileStoreDocument {
        try SecureFileSystem.rejectSymlink(documentURL, fileManager: fileManager)
        guard fileManager.fileExists(atPath: documentURL.path) else { return ProfileStoreDocument() }
        let data = try Data(contentsOf: documentURL)
        var document = try decoder.decode(ProfileStoreDocument.self, from: data)
        for profile in document.profiles {
            try validate(profile)
        }
        if document.schemaVersion < 3 {
            document.schemaVersion = 3
            try save(document)
        }
        return document
    }

    public func save(_ document: ProfileStoreDocument) throws {
        let data = try encoder.encode(document)
        try SecureFileSystem.writeAtomically(data, to: documentURL, fileManager: fileManager)
    }

    @discardableResult
    public func ensureAdoptedDefaultProfile(named name: String = "Personal") throws -> ProfileStoreDocument {
        var document = try load()
        if document.profiles.contains(where: { $0.storageKind == .adoptedDefault }) {
            return document
        }

        let profile = CodexProfile(
            displayName: name,
            codexHomePath: CodexSwitchPaths.defaultCodexHome.path,
            electronDataPath: CodexSwitchPaths.defaultElectronData.path,
            electronCachePath: CodexSwitchPaths.defaultElectronCache.path,
            storageKind: .adoptedDefault
        )
        document.profiles.append(profile)
        document.activeProfileID = document.activeProfileID ?? profile.id
        document.lastCommittedProfileID = document.lastCommittedProfileID ?? profile.id
        try save(document)
        return document
    }

    public func createManagedProfile(named name: String) throws -> (ProfileStoreDocument, CodexProfile) {
        var document = try load()
        let id = UUID()
        let profileRoot = managedProfileRoot(for: id)
        guard !fileManager.fileExists(atPath: profileRoot.path) else {
            throw ProfileError.transactionFailed("A managed profile storage collision was detected.")
        }
        let codexHome = profileRoot.appendingPathComponent("codex-home", isDirectory: true)
        let electronData = profileRoot.appendingPathComponent("electron-data", isDirectory: true)
        let electronCache = profileRoot.appendingPathComponent("electron-cache", isDirectory: true)

        try SecureFileSystem.createDirectory(codexHome, fileManager: fileManager)
        try SecureFileSystem.createDirectory(electronData, fileManager: fileManager)
        try SecureFileSystem.createDirectory(electronCache, fileManager: fileManager)

        let profile = CodexProfile(
            id: id,
            displayName: name,
            codexHomePath: codexHome.path,
            electronDataPath: electronData.path,
            electronCachePath: electronCache.path,
            storageKind: .managed
        )
        document.profiles.append(profile)
        try save(document)
        return (document, profile)
    }

    @discardableResult
    public func compactManagedProfile(_ profileID: UUID) throws -> ProfileStoreDocument {
        var document = try load()
        guard let index = document.profiles.firstIndex(where: { $0.id == profileID }) else {
            throw ProfileError.missingProfile
        }
        let profile = document.profiles[index]
        guard profile.storageKind == .managed else { return document }

        let currentRoot = profile.codexHomeURL.deletingLastPathComponent()
        let targetRoot = managedProfileRoot(for: profile.id)
        if currentRoot.standardizedFileURL == targetRoot.standardizedFileURL {
            return document
        }

        try validate(profile)
        try SecureFileSystem.createDirectory(profilesRoot, fileManager: fileManager)

        let currentExists = fileManager.fileExists(atPath: currentRoot.path)
        let targetExists = fileManager.fileExists(atPath: targetRoot.path)
        if currentExists && targetExists {
            throw ProfileError.transactionFailed("Both legacy and compact storage exist for a managed profile.")
        }
        guard currentExists || targetExists else {
            throw ProfileError.transactionFailed("Managed profile storage is missing.")
        }

        var moved = false
        if currentExists {
            try SecureFileSystem.rejectSymlink(currentRoot, fileManager: fileManager)
            try fileManager.moveItem(at: currentRoot, to: targetRoot)
            moved = true
        } else {
            try SecureFileSystem.rejectSymlink(targetRoot, fileManager: fileManager)
        }

        var compacted = profile
        compacted.codexHomePath = targetRoot.appendingPathComponent("codex-home", isDirectory: true).path
        compacted.electronDataPath = targetRoot.appendingPathComponent("electron-data", isDirectory: true).path
        compacted.electronCachePath = targetRoot.appendingPathComponent("electron-cache", isDirectory: true).path
        do {
            try validate(compacted)
            document.profiles[index] = compacted
            try save(document)
        } catch {
            if moved {
                try? fileManager.moveItem(at: targetRoot, to: currentRoot)
            }
            throw error
        }
        return document
    }

    public func update(_ profile: CodexProfile) throws -> ProfileStoreDocument {
        var document = try load()
        guard let index = document.profiles.firstIndex(where: { $0.id == profile.id }) else {
            throw ProfileError.missingProfile
        }
        try validate(profile)
        document.profiles[index] = profile
        try save(document)
        return document
    }

    public func setActive(_ profileID: UUID, committed: Bool = false) throws -> ProfileStoreDocument {
        var document = try load()
        guard document.profiles.contains(where: { $0.id == profileID }) else {
            throw ProfileError.missingProfile
        }
        document.activeProfileID = profileID
        if committed { document.lastCommittedProfileID = profileID }
        try save(document)
        return document
    }

    public func profile(id: UUID) throws -> CodexProfile {
        guard let profile = try load().profiles.first(where: { $0.id == id }) else {
            throw ProfileError.missingProfile
        }
        return profile
    }

    public func validate(_ profile: CodexProfile) throws {
        let paths = [profile.codexHomeURL, profile.electronDataURL, profile.electronCacheURL]
        if profile.storageKind == .adoptedDefault {
            guard profile.codexHomeURL.standardizedFileURL == CodexSwitchPaths.defaultCodexHome.standardizedFileURL,
                  profile.electronDataURL.standardizedFileURL == CodexSwitchPaths.defaultElectronData.standardizedFileURL,
                  profile.electronCacheURL.standardizedFileURL == CodexSwitchPaths.defaultElectronCache.standardizedFileURL else {
                throw ProfileError.invalidPath(profile.codexHomePath)
            }
            for path in paths {
                try SecureFileSystem.rejectSymlink(path, fileManager: fileManager)
            }
            return
        }

        if profile.storageKind == .managed {
            let profileRoot = profile.codexHomeURL.deletingLastPathComponent()
            let isCompactRoot = SecureFileSystem.isPath(profileRoot, inside: profilesRoot) &&
                profileRoot.lastPathComponent == compactDirectoryName(for: profile.id)
            let isLegacyRoot = SecureFileSystem.isPath(profileRoot, inside: legacyProfilesRoot) &&
                profileRoot.lastPathComponent == profile.id.uuidString
            guard isCompactRoot || isLegacyRoot,
                  profile.codexHomeURL.lastPathComponent == "codex-home",
                  profile.electronDataURL.lastPathComponent == "electron-data",
                  profile.electronCacheURL.lastPathComponent == "electron-cache",
                  profile.electronDataURL.deletingLastPathComponent().standardizedFileURL == profileRoot.standardizedFileURL,
                  profile.electronCacheURL.deletingLastPathComponent().standardizedFileURL == profileRoot.standardizedFileURL,
                  paths.dropFirst().allSatisfy({ SecureFileSystem.isPath($0, inside: profileRoot) }) else {
                throw ProfileError.invalidPath(profile.codexHomePath)
            }
            for path in paths {
                try SecureFileSystem.rejectSymlink(path, fileManager: fileManager)
            }
        }
    }

    private func compactDirectoryName(for id: UUID) -> String {
        String(id.uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased()
    }

    public func compatibility(for app: ChatGPTApplication) throws -> CompatibilityRecord {
        let document = try load()
        return document.compatibilityRecords.first(where: {
            $0.appVersion == app.version &&
            $0.bundleIdentifier == app.bundleIdentifier &&
            $0.teamIdentifier == app.teamIdentifier
        }) ?? CompatibilityRecord(
            appVersion: app.version,
            bundleIdentifier: app.bundleIdentifier,
            teamIdentifier: app.teamIdentifier
        )
    }

    @discardableResult
    public func setCompatibility(_ record: CompatibilityRecord) throws -> ProfileStoreDocument {
        var document = try load()
        if let index = document.compatibilityRecords.firstIndex(where: { $0.id == record.id }) {
            document.compatibilityRecords[index] = record
        } else {
            document.compatibilityRecords.append(record)
        }
        document.schemaVersion = max(document.schemaVersion, 3)
        try save(document)
        return document
    }
}
