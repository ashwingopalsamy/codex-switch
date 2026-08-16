import Foundation

public struct RecoveryResult: Equatable, Sendable {
    public let recovered: Bool
    public let message: String

    public init(recovered: Bool, message: String) {
        self.recovered = recovered
        self.message = message
    }
}

public enum SwitchOutcome: Equatable, Sendable {
    case unchanged
    case committed
}

public enum LiveSessionHandoff: Equatable, Sendable {
    case requireConfirmation
    case confirmedGracefulQuit
}

public final class SwitchTransaction: @unchecked Sendable {
    private let store: ProfileStore
    private let journal: RecoveryJournal
    private let liveWriterDetector: LiveWriterDetector
    private let processController: any ChatGPTProcessControlling
    private let verifier: any AccountVerifying
    private let probe: any CompatibilityProbing
    private let configManager: CodexConfigManager
    private let compatibilityPolicy: CompatibilityPolicy
    private let operationLock: OperationLock

    public init(
        store: ProfileStore,
        liveWriterDetector: LiveWriterDetector = LiveWriterDetector(),
        processController: any ChatGPTProcessControlling = CodexProcessController(),
        verifier: any AccountVerifying = AccountVerifier(),
        probe: (any CompatibilityProbing)? = nil,
        configManager: CodexConfigManager = CodexConfigManager(),
        compatibilityPolicy: CompatibilityPolicy = CompatibilityPolicy()
    ) {
        self.store = store
        self.journal = RecoveryJournal(url: store.journalURL)
        self.liveWriterDetector = liveWriterDetector
        self.processController = processController
        self.verifier = verifier
        self.probe = probe ?? CompatibilityProbe(managedRoot: store.root)
        self.configManager = configManager
        self.compatibilityPolicy = compatibilityPolicy
        self.operationLock = OperationLock(url: store.operationLockURL)
    }

    public func prepareGuidedValidation(
        profileIDs: Set<UUID>
    ) async throws -> GuidedValidationAuthorization {
        try await Task.detached(priority: .userInitiated) { [self] in
            try operationLock.acquire()
            defer { operationLock.release() }
            try requireNoPendingRecovery()

            let document = try store.load()
            guard profileIDs.count == 2 else {
                throw ProfileError.guidedValidationInvalidated(
                    "Guided validation requires exactly two identity-bound profiles."
                )
            }
            let profiles = document.profiles.filter { profileIDs.contains($0.id) }
            guard profiles.count == 2,
                  profiles.allSatisfy({ $0.expectedIdentityHash != nil }),
                  let committedID = document.lastCommittedProfileID ?? document.activeProfileID,
                  let committed = profiles.first(where: { $0.id == committedID }) else {
                throw ProfileError.guidedValidationInvalidated(
                    "Guided validation requires two identity-bound profiles including the committed profile."
                )
            }

            let app = try probe.app()
            guard let authorization = GuidedValidationAuthorization(app: app, profileIDs: profileIDs) else {
                throw ProfileError.guidedValidationInvalidated(
                    "Guided validation could not authorize the selected profile pair."
                )
            }

            if let snapshot = try processController.inspectSession() {
                let candidates = profiles.filter { snapshot.exposes(profile: $0) }
                guard candidates.count == 1 else {
                    SwitchLogger.switchRejected(.sourceMappingAmbiguous)
                    throw ProfileError.guidedValidationInvalidated(
                        "The running ChatGPT session does not map safely to one validation profile."
                    )
                }
                guard candidates[0].id == committed.id else {
                    SwitchLogger.switchRejected(.committedSourceMismatch)
                    throw ProfileError.guidedValidationInvalidated(
                        "The running ChatGPT profile differs from the committed profile."
                    )
                }
            } else {
                try configManager.ensureFileCredentialStorage(for: committed, backupRoot: store.configBackupsURL)
                _ = try await verifier.verify(committed)
                try await processController.launchAndConfirm(profile: committed)
            }
            return authorization
        }.value
    }

    public func switchTo(
        _ targetID: UUID,
        validation: GuidedValidationAuthorization? = nil,
        liveSessionHandoff: LiveSessionHandoff = .requireConfirmation
    ) async throws -> SwitchOutcome {
        try operationLock.acquire()
        defer { operationLock.release() }
        try requireNoPendingRecovery()

        let document = try store.load()
        guard let committedSourceID = document.lastCommittedProfileID ?? document.activeProfileID,
              let committedSource = document.profiles.first(where: { $0.id == committedSourceID }),
              let target = document.profiles.first(where: { $0.id == targetID }) else {
            throw ProfileError.missingProfile
        }
        let liveSnapshot = try processController.inspectSession()
        let source: CodexProfile
        if let liveSnapshot {
            let candidates = document.profiles.filter { liveSnapshot.exposes(profile: $0) }
            guard candidates.count == 1 else {
                SwitchLogger.switchRejected(.sourceMappingAmbiguous)
                if validation != nil {
                    throw ProfileError.guidedValidationInvalidated(
                        "ChatGPT no longer maps safely to the committed validation profile. Guided validation was stopped."
                    )
                }
                throw ProfileError.transactionFailed("The running ChatGPT session cannot be mapped unambiguously to a profile.")
            }
            source = candidates[0]
        } else {
            source = committedSource
        }
        if validation != nil {
            guard liveSnapshot != nil else {
                SwitchLogger.switchRejected(.sourceNotRunning)
                throw ProfileError.guidedValidationInvalidated(
                    "ChatGPT stopped after guided validation began. Guided validation was stopped; start it again."
                )
            }
            guard source.id == committedSource.id else {
                SwitchLogger.switchRejected(.committedSourceMismatch)
                throw ProfileError.guidedValidationInvalidated(
                    "The running ChatGPT profile changed after guided validation began. Guided validation was stopped."
                )
            }
        }
        guard source.id != target.id else { return .unchanged }

        let app = try probe.app()
        let compatibility = try store.compatibility(for: app)
        if let validation {
            guard validation.permitsTransition(sourceID: source.id, targetID: target.id, app: app) else {
                SwitchLogger.switchRejected(.validationAuthorizationChanged)
                throw ProfileError.guidedValidationInvalidated(
                    "Guided validation no longer matches this ChatGPT installation or profile pair. Start it again."
                )
            }
        }
        try requireCompatibility(compatibility, app: app)

        SwitchLogger.switchStage("preflight")
        do {
            _ = try probe.check(profile: target)
        } catch {
            SwitchLogger.switchRejected(.targetPreflight)
            throw error
        }
        SwitchLogger.switchStage("checking-live-writer")
        var sourceHasLiveWriter: Bool
        if liveWriterDetector.status(for: source) == .present {
            sourceHasLiveWriter = true
        } else {
            sourceHasLiveWriter = false
        }
        if sourceHasLiveWriter, liveSessionHandoff == .requireConfirmation {
            SwitchLogger.switchRejected(.liveWriterConfirmationRequired)
            throw ProfileError.liveSessionHandoffRequired(
                "A Codex conversation is open in the active profile. Confirm a safe ChatGPT handoff before switching."
            )
        }
        if sourceHasLiveWriter {
            SwitchLogger.switchStage("live-writer-handoff-confirmed")
        }

        try configManager.ensureFileCredentialStorage(for: source, backupRoot: store.configBackupsURL)
        try configManager.ensureFileCredentialStorage(for: target, backupRoot: store.configBackupsURL)
        do {
            _ = try await verifier.verify(target)
        } catch {
            SwitchLogger.switchRejected(.targetIdentity)
            throw error
        }
        if liveWriterDetector.status(for: source) == .present {
            sourceHasLiveWriter = true
            if liveSessionHandoff == .requireConfirmation {
                SwitchLogger.switchRejected(.liveWriterConfirmationRequired)
                throw ProfileError.liveSessionHandoffRequired(
                    "A Codex conversation is open in the active profile. Confirm a safe ChatGPT handoff before switching."
                )
            }
        }

        let hadSourceRunning = liveSnapshot != nil
        var transaction = SwitchJournal(sourceProfileID: source.id, targetProfileID: target.id, phase: .quittingSource)
        var targetLaunchAttempted = false
        try journal.save(transaction)
        do {

            SwitchLogger.switchStage("quitting-source")
            if hadSourceRunning {
                try await processController.quitGracefully()
            }
            if liveWriterDetector.status(for: source) == .present {
                SwitchLogger.switchRejected(.liveWriterDidNotRelease)
                throw ProfileError.transactionFailed(
                    "ChatGPT closed, but its live Codex conversation did not release safely. The previous profile will be restored."
                )
            }

            transaction.phase = .launchingTarget
            SwitchLogger.switchStage("launching-target")
            try journal.save(transaction)
            targetLaunchAttempted = true
            try await processController.launchAndConfirm(profile: target)

            transaction.phase = .confirmingRoots
            SwitchLogger.switchStage("confirming-roots")
            try journal.save(transaction)
            _ = try probe.check(profile: target)
            _ = try store.setActive(target.id, committed: true)
            transaction.phase = .committed
            SwitchLogger.switchStage("committed")
            try journal.save(transaction)
            try journal.clear()
            return .committed
        } catch {
            let originalError = error
            transaction.phase = .rollingBack
            SwitchLogger.switchStage("rolling-back")
            transaction.message = sanitizedMessage(error)
            try? journal.save(transaction)
            do {
                let rollback = Task.detached { [self] in
                    if targetLaunchAttempted, try processController.inspectSession() != nil {
                        try await processController.quitGracefully()
                    }
                    try await restore(source: source, shouldRun: hadSourceRunning)
                    _ = try store.setActive(source.id, committed: true)
                    try journal.clear()
                }
                try await rollback.value
            } catch {
                transaction.phase = .failed
                SwitchLogger.switchStage("rollback-failed")
                try? journal.save(transaction)
                throw ProfileError.recoveryRequired(
                    "The switch failed and CodexSwitch could not restore the last committed profile. Close ChatGPT, then retry recovery."
                )
            }
            throw originalError
        }
    }

    public func launchActive(validation: GuidedValidationAuthorization? = nil) async throws {
        try operationLock.acquire()
        defer { operationLock.release() }
        try requireNoPendingRecovery()

        let document = try store.load()
        guard let id = document.lastCommittedProfileID ?? document.activeProfileID,
              let profile = document.profiles.first(where: { $0.id == id }) else {
            throw ProfileError.missingProfile
        }
        let app = try probe.app()
        let compatibility = try store.compatibility(for: app)
        if let validation {
            guard validation.permits(profileID: profile.id, app: app) else {
                SwitchLogger.switchRejected(.validationAuthorizationChanged)
                throw ProfileError.guidedValidationInvalidated(
                    "Guided validation no longer matches this ChatGPT installation or profile pair. Start it again."
                )
            }
        }
        try requireCompatibility(compatibility, app: app)
        try configManager.ensureFileCredentialStorage(for: profile, backupRoot: store.configBackupsURL)
        _ = try await verifier.verify(profile)
        if let liveSnapshot = try processController.inspectSession() {
            let candidates = document.profiles.filter { liveSnapshot.exposes(profile: $0) }
            guard candidates.count == 1, candidates[0].id == profile.id else {
                throw ProfileError.transactionFailed("The running ChatGPT session does not expose the selected profile roots.")
            }
        } else {
            try await processController.launchAndConfirm(profile: profile)
        }
    }

    public func confirmActive(validation: GuidedValidationAuthorization) async throws {
        try operationLock.acquire()
        defer { operationLock.release() }
        try requireNoPendingRecovery()

        let document = try store.load()
        guard let id = document.lastCommittedProfileID ?? document.activeProfileID,
              let profile = document.profiles.first(where: { $0.id == id }) else {
            throw ProfileError.missingProfile
        }
        let app = try probe.app()
        guard validation.permits(profileID: profile.id, app: app) else {
            SwitchLogger.switchRejected(.validationAuthorizationChanged)
            throw ProfileError.guidedValidationInvalidated(
                "Guided validation no longer matches this ChatGPT installation or profile pair. Start it again."
            )
        }
        guard let snapshot = try processController.inspectSession() else {
            SwitchLogger.switchRejected(.sourceNotRunning)
            throw ProfileError.guidedValidationInvalidated(
                "ChatGPT is no longer running. Guided validation was stopped."
            )
        }
        let candidates = document.profiles.filter { snapshot.exposes(profile: $0) }
        guard candidates.count == 1, candidates[0].id == profile.id else {
            SwitchLogger.switchRejected(.committedSourceMismatch)
            throw ProfileError.guidedValidationInvalidated(
                "The running ChatGPT session no longer exposes the committed profile roots. Guided validation was stopped."
            )
        }
        _ = try await verifier.verify(profile)
    }

    public func recoverIfNeeded() async -> RecoveryResult {
        do {
            try operationLock.acquire()
            defer { operationLock.release() }

            guard let pending = try journal.load() else {
                return RecoveryResult(recovered: true, message: "No interrupted switch was found.")
            }
            let document = try store.load()
            guard let source = document.profiles.first(where: { $0.id == pending.sourceProfileID }) else {
                throw ProfileError.recoveryRequired("The recovery journal refers to a missing source profile.")
            }

            if let liveSnapshot = try processController.inspectSession() {
                let candidates = document.profiles.filter { liveSnapshot.exposes(profile: $0) }
                guard candidates.count == 1 else {
                    throw ProfileError.recoveryRequired(
                        "The running ChatGPT session cannot be mapped safely. Close ChatGPT, then retry recovery."
                    )
                }
                if candidates[0].id == source.id {
                    _ = try store.setActive(source.id, committed: true)
                    try journal.clear()
                    return RecoveryResult(recovered: true, message: "Confirmed the last committed profile.")
                }
                guard candidates[0].id == pending.targetProfileID else {
                    throw ProfileError.recoveryRequired(
                        "A different ChatGPT profile is running. Close ChatGPT, then retry recovery."
                    )
                }
                try await processController.quitGracefully()
            }
            try configManager.ensureFileCredentialStorage(for: source, backupRoot: store.configBackupsURL)
            _ = try await verifier.verify(source)
            try await processController.launchAndConfirm(profile: source)
            _ = try store.setActive(source.id, committed: true)
            try journal.clear()
            return RecoveryResult(recovered: true, message: "Recovered the last committed profile.")
        } catch {
            return RecoveryResult(
                recovered: false,
                message: "Recovery could not restore the last committed profile. Close ChatGPT, then retry recovery."
            )
        }
    }

    private func restore(source: CodexProfile, shouldRun: Bool) async throws {
        guard shouldRun else { return }
        if let liveSnapshot = try processController.inspectSession() {
            if liveSnapshot.exposes(profile: source) { return }
            try await processController.quitGracefully()
        }
        _ = try await verifier.verify(source)
        try await processController.launchAndConfirm(profile: source)
    }

    private func requireNoPendingRecovery() throws {
        guard try journal.load() == nil else {
            throw ProfileError.recoveryRequired(
                "Complete the pending recovery before launching or switching profiles."
            )
        }
    }

    private func requireCompatibility(_ record: CompatibilityRecord, app: ChatGPTApplication) throws {
        switch compatibilityPolicy.decision(for: record) {
        case .allowed:
            return
        case .requiresAcknowledgement:
            throw ProfileError.compatibilityAcknowledgementRequired(
                "Review and acknowledge provisional compatibility for ChatGPT \(app.version) before continuing."
            )
        case .blocked(let message):
            throw ProfileError.compatibilityBlocked(message)
        }
    }

    private func sanitizedMessage(_ error: Error) -> String {
        if let profileError = error as? ProfileError {
            switch profileError {
            case .identityMismatch:
                return "The target identity did not match its bound profile."
            case .identityUnverified:
                return "The target identity could not be verified."
            case .compatibilityAcknowledgementRequired:
                return "The installed ChatGPT version needs provisional acknowledgement."
            case .compatibilityBlocked:
                return "The installed ChatGPT version is blocked."
            case .guidedValidationInvalidated:
                return "Guided validation was invalidated by a source or installation change."
            case .liveSessionHandoffRequired:
                return "The source profile has an open Codex conversation that requires confirmation."
            case .invalidPath, .unsupportedProfile:
                return "A profile root failed validation."
            case .recoveryRequired:
                return "Automatic recovery requires attention."
            case .missingProfile:
                return "The profile required for recovery no longer exists."
            case .appNotFound, .appSignatureInvalid:
                return "The installed ChatGPT application failed validation."
            case .transactionFailed:
                return "The switch transaction failed. Retry after reviewing the current operation state."
            }
        }
        return "The switch transaction failed. Inspect sanitized diagnostics for the operation stage."
    }
}
