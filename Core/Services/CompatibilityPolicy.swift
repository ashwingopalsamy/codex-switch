import Foundation

public enum CompatibilityDecision: Equatable, Sendable {
    case allowed
    case requiresAcknowledgement
    case blocked(String)
}

public struct CompatibilityPolicy: Sendable {
    public init() {}

    public func decision(for record: CompatibilityRecord) -> CompatibilityDecision {
        switch record.status {
        case .verified:
            return .allowed
        case .provisional:
            return record.provisionalAcknowledgedAt == nil ? .requiresAcknowledgement : .allowed
        case .blocked:
            return .blocked(record.summary ?? "Profile switching is blocked for this ChatGPT version.")
        }
    }

    public func canSelectProfile(with record: CompatibilityRecord) -> Bool {
        if case .blocked = decision(for: record) { return false }
        return true
    }

    public func acknowledging(_ record: CompatibilityRecord, at date: Date = Date()) -> CompatibilityRecord {
        guard record.status == .provisional else { return record }
        var acknowledged = record
        acknowledged.provisionalAcknowledgedAt = date
        return acknowledged
    }
}
