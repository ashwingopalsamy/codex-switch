import Darwin
import Foundation

public enum CodexSwitchPaths {
    public static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    public static var applicationSupport: URL {
        home.appendingPathComponent("Library/Application Support/CodexSwitch", isDirectory: true)
    }

    public static var profiles: URL {
        applicationSupport.appendingPathComponent("Profiles", isDirectory: true)
    }

    public static var profileDocument: URL {
        applicationSupport.appendingPathComponent("profiles.json")
    }

    public static var journal: URL {
        applicationSupport.appendingPathComponent("switch-transaction.json")
    }

    public static var configBackups: URL {
        applicationSupport.appendingPathComponent("Config Backups", isDirectory: true)
    }

    public static var defaultCodexHome: URL {
        home.appendingPathComponent(".codex", isDirectory: true)
    }

    public static var defaultElectronData: URL {
        home.appendingPathComponent("Library/Application Support/Codex", isDirectory: true)
    }

    public static var defaultElectronCache: URL {
        home.appendingPathComponent("Library/Caches/Codex", isDirectory: true)
    }
}

public enum SecureFileSystem {
    public static func createDirectory(_ url: URL, fileManager: FileManager = .default) throws {
        try rejectSymlinkComponents(url, fileManager: fileManager)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try rejectSymlinkComponents(url, fileManager: fileManager)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    public static func writeAtomically(_ data: Data, to url: URL, fileManager: FileManager = .default) throws {
        try rejectSymlink(url, fileManager: fileManager)
        let directory = url.deletingLastPathComponent()
        try createDirectory(directory, fileManager: fileManager)
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: temporary, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)

        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: url)
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func isPath(_ candidate: URL, inside root: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
            return false
        }
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        return resolvedCandidate == resolvedRoot || resolvedCandidate.hasPrefix(resolvedRoot + "/")
    }

    public static func rejectSymlink(_ url: URL, fileManager: FileManager = .default) throws {
        try rejectSymlinkComponents(url, fileManager: fileManager)
    }

    public static func rejectSymlinkComponents(_ url: URL, fileManager: FileManager = .default) throws {
        let path = url.standardizedFileURL.path
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            current.appendPathComponent(String(component), isDirectory: false)
            var info = stat()
            guard lstat(current.path, &info) == 0 else { continue }
            if (info.st_mode & S_IFMT) == S_IFLNK {
                // macOS exposes temporary storage through the stable /var
                // alias (and /tmp through /private/var). Those system aliases
                // are not profile-controlled links and are safe to resolve.
                let systemAlias = current.path == "/var" || current.path == "/tmp"
                if !systemAlias {
                    throw ProfileError.invalidPath(current.path)
                }
            }
        }
    }
}
