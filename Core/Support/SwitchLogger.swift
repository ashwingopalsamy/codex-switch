import Foundation
import OSLog

public enum SwitchRejectionReason: String, Sendable {
    case sourceNotRunning = "source-not-running"
    case sourceMappingAmbiguous = "source-mapping-ambiguous"
    case committedSourceMismatch = "committed-source-mismatch"
    case validationAuthorizationChanged = "validation-authorization-changed"
    case liveWriterConfirmationRequired = "live-writer-confirmation-required"
    case liveWriterDidNotRelease = "live-writer-did-not-release"
    case targetPreflight = "target-preflight"
    case targetIdentity = "target-identity"
}

public enum SwitchLogger {
    private static let subsystem = "in.ashwingopalsamy.codexswitch"
    private static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    private static let authentication = Logger(subsystem: subsystem, category: "authentication")
    private static let switching = Logger(subsystem: subsystem, category: "switching")
    private static let compatibility = Logger(subsystem: subsystem, category: "compatibility")
    private static let recovery = Logger(subsystem: subsystem, category: "recovery")

    public static func started() {
        lifecycle.notice("CodexSwitch started")
    }

    public static func authenticationStage(_ stage: String) {
        authentication.notice("Authentication stage: \(stage, privacy: .public)")
    }

    public static func authenticationFinished(success: Bool) {
        authentication.notice("Authentication finished: success=\(success, privacy: .public)")
    }

    public static func authenticationHelperExited(status: Int32, wroteToStderr: Bool) {
        authentication.notice("Authentication helper exited: status=\(status, privacy: .public), stderr=\(wroteToStderr, privacy: .public)")
    }

    public static func switchStage(_ stage: String) {
        switching.notice("Switch stage: \(stage, privacy: .public)")
    }

    public static func switchRejected(_ reason: SwitchRejectionReason) {
        switching.notice("Switch rejected: \(reason.rawValue, privacy: .public)")
    }

    public static func compatibility(_ status: CompatibilityStatus) {
        compatibility.notice("Compatibility status: \(status.rawValue, privacy: .public)")
    }

    public static func recovery(_ outcome: String) {
        recovery.notice("Recovery outcome: \(outcome, privacy: .public)")
    }
}
