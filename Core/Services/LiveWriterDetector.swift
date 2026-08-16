import Darwin
import Foundation

public struct LiveWriterDetector: Sendable {
    public init() {}

    public func status(for profile: CodexProfile, fileManager: FileManager = .default) -> LiveWriterStatus {
        let lockDirectory = profile.codexHomeURL.appendingPathComponent("thread-writer-locks", isDirectory: true)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: lockDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .absent
        }

        for entry in entries where entry.pathExtension == "lock" {
            if isHeld(entry) {
                return .present
            }
        }
        return .absent
    }

    private func isHeld(_ url: URL) -> Bool {
        let descriptor = open(url.path, O_RDWR | O_CLOEXEC)
        guard descriptor >= 0 else { return true }
        defer { close(descriptor) }
        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            return true
        }
        _ = flock(descriptor, LOCK_UN)
        return false
    }
}

public enum LiveWriterStatus: Equatable, Sendable {
    case absent
    case present
}
