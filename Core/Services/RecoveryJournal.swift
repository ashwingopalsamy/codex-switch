import Foundation

public enum SwitchPhase: String, Codable, Sendable {
    case preflight
    case checkingIdle
    case quittingSource
    case verifyingTarget
    case launchingTarget
    case confirmingRoots
    case rollingBack
    case committed
    case failed
}

public struct SwitchJournal: Codable, Sendable {
    public let sourceProfileID: UUID
    public let targetProfileID: UUID
    public var phase: SwitchPhase
    public var message: String?
    public let startedAt: Date

    public init(sourceProfileID: UUID, targetProfileID: UUID, phase: SwitchPhase, message: String? = nil, startedAt: Date = Date()) {
        self.sourceProfileID = sourceProfileID
        self.targetProfileID = targetProfileID
        self.phase = phase
        self.message = message
        self.startedAt = startedAt
    }
}

public final class RecoveryJournal: @unchecked Sendable {
    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(url: URL) {
        self.url = url
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func load() throws -> SwitchJournal? {
        try SecureFileSystem.rejectSymlink(url)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var journal = try decoder.decode(SwitchJournal.self, from: Data(contentsOf: url))
        if journal.message != nil {
            // Older builds could persist free-form failure text. Recovery only
            // needs the phase and profile IDs, so discard that text on read.
            journal.message = nil
            try save(journal)
        }
        return journal
    }

    public func save(_ journal: SwitchJournal) throws {
        try SecureFileSystem.writeAtomically(try encoder.encode(journal), to: url)
    }

    public func clear() throws {
        try SecureFileSystem.rejectSymlink(url)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
