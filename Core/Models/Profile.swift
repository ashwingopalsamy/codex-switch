import Foundation

public enum ProfileStorageKind: String, Codable, Sendable {
    case adoptedDefault
    case managed
}

public struct CodexProfile: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var displayName: String
    public var codexHomePath: String
    public var electronDataPath: String
    public var electronCachePath: String
    public var storageKind: ProfileStorageKind
    public var expectedIdentityHash: String?
    public var lastValidatedAppVersion: String?
    public var lastValidatedAt: Date?

    public init(
        id: UUID = UUID(),
        displayName: String,
        codexHomePath: String,
        electronDataPath: String,
        electronCachePath: String,
        storageKind: ProfileStorageKind,
        expectedIdentityHash: String? = nil,
        lastValidatedAppVersion: String? = nil,
        lastValidatedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.codexHomePath = codexHomePath
        self.electronDataPath = electronDataPath
        self.electronCachePath = electronCachePath
        self.storageKind = storageKind
        self.expectedIdentityHash = expectedIdentityHash
        self.lastValidatedAppVersion = lastValidatedAppVersion
        self.lastValidatedAt = lastValidatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, codexHomePath, electronDataPath, electronCachePath
        case storageKind, expectedIdentityHash, lastValidatedAppVersion, lastValidatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        codexHomePath = try container.decode(String.self, forKey: .codexHomePath)
        electronDataPath = try container.decode(String.self, forKey: .electronDataPath)
        electronCachePath = try container.decode(String.self, forKey: .electronCachePath)
        storageKind = try container.decode(ProfileStorageKind.self, forKey: .storageKind)
        expectedIdentityHash = try container.decodeIfPresent(String.self, forKey: .expectedIdentityHash)
        lastValidatedAppVersion = try container.decodeIfPresent(String.self, forKey: .lastValidatedAppVersion)
        lastValidatedAt = try container.decodeIfPresent(Date.self, forKey: .lastValidatedAt)
        // v1's free-form lastValidationMessage is intentionally ignored. It was
        // capable of persisting a plaintext account email.
    }

    public var codexHomeURL: URL { URL(fileURLWithPath: codexHomePath, isDirectory: true) }
    public var electronDataURL: URL { URL(fileURLWithPath: electronDataPath, isDirectory: true) }
    public var electronCacheURL: URL { URL(fileURLWithPath: electronCachePath, isDirectory: true) }

    public var isBound: Bool { expectedIdentityHash != nil }
}

public struct ProfileStoreDocument: Codable, Sendable {
    public var schemaVersion: Int
    public var profiles: [CodexProfile]
    public var activeProfileID: UUID?
    public var lastCommittedProfileID: UUID?
    public var compatibilityRecords: [CompatibilityRecord]

    public init(
        schemaVersion: Int = 3,
        profiles: [CodexProfile] = [],
        activeProfileID: UUID? = nil,
        lastCommittedProfileID: UUID? = nil,
        compatibilityRecords: [CompatibilityRecord] = []
    ) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.lastCommittedProfileID = lastCommittedProfileID
        self.compatibilityRecords = compatibilityRecords
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, profiles, activeProfileID, lastCommittedProfileID, compatibilityRecords
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        profiles = try container.decodeIfPresent([CodexProfile].self, forKey: .profiles) ?? []
        activeProfileID = try container.decodeIfPresent(UUID.self, forKey: .activeProfileID)
        lastCommittedProfileID = try container.decodeIfPresent(UUID.self, forKey: .lastCommittedProfileID)
        compatibilityRecords = try container.decodeIfPresent([CompatibilityRecord].self, forKey: .compatibilityRecords) ?? []
    }
}

public enum CompatibilityStatus: String, Codable, Sendable {
    case provisional
    case verified
    case blocked

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "provisional", "unverified": self = .provisional
        case "verified", "supported": self = .verified
        case "blocked", "unsupported": self = .blocked
        default:
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unknown compatibility status: \(value)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct CompatibilityRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "\(appVersion)|\(bundleIdentifier)|\(teamIdentifier)" }
    public let appVersion: String
    public let bundleIdentifier: String
    public let teamIdentifier: String
    public var status: CompatibilityStatus
    public var provisionalAcknowledgedAt: Date?
    public var checkedAt: Date?
    public var summary: String?

    public init(
        appVersion: String,
        bundleIdentifier: String,
        teamIdentifier: String,
        status: CompatibilityStatus = .provisional,
        provisionalAcknowledgedAt: Date? = nil,
        checkedAt: Date? = nil,
        summary: String? = nil
    ) {
        self.appVersion = appVersion
        self.bundleIdentifier = bundleIdentifier
        self.teamIdentifier = teamIdentifier
        self.status = status
        self.provisionalAcknowledgedAt = provisionalAcknowledgedAt
        self.checkedAt = checkedAt
        self.summary = summary
    }
}

public struct AccountIdentity: Codable, Hashable, Sendable {
    public let email: String
    public let planType: String?
    public let identityHash: String

    public init(email: String, planType: String? = nil, identityHash: String) {
        self.email = email
        self.planType = planType
        self.identityHash = identityHash
    }
}

public enum ProfileError: LocalizedError, Sendable {
    case missingProfile
    case invalidPath(String)
    case unsupportedProfile(String)
    case identityUnverified
    case identityMismatch
    case appNotFound
    case appSignatureInvalid
    case compatibilityAcknowledgementRequired(String)
    case compatibilityBlocked(String)
    case guidedValidationInvalidated(String)
    case liveSessionHandoffRequired(String)
    case recoveryRequired(String)
    case transactionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingProfile: return "The selected profile does not exist."
        case .invalidPath(let path): return "The profile path is invalid: \(path)"
        case .unsupportedProfile(let message): return message
        case .identityUnverified: return "Identity unverified. Complete sign-in and verify the profile first."
        case .identityMismatch: return "The authenticated identity does not match this profile."
        case .appNotFound: return "The ChatGPT desktop application could not be located."
        case .appSignatureInvalid: return "The ChatGPT application signature could not be verified."
        case .compatibilityAcknowledgementRequired(let message): return message
        case .compatibilityBlocked(let message): return message
        case .guidedValidationInvalidated(let message): return message
        case .liveSessionHandoffRequired(let message): return message
        case .recoveryRequired(let message): return message
        case .transactionFailed(let message): return message
        }
    }
}
