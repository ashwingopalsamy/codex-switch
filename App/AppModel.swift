import AppKit
import CodexSwitchCore
import Foundation
import Observation

struct PendingLiveSessionHandoff: Identifiable, Equatable {
    let targetProfileID: UUID
    let targetDisplayName: String
    let sourceDisplayName: String

    var id: UUID { targetProfileID }
}

enum PendingCompatibilityAction: Equatable {
    case switchProfile(id: UUID, displayName: String)
    case openChatGPT

    var description: String {
        switch self {
        case .switchProfile(_, let displayName): return "switch to \(displayName)"
        case .openChatGPT: return "open ChatGPT"
        }
    }
}

struct PendingCompatibilityAcknowledgement: Identifiable, Equatable {
    let id = UUID()
    let action: PendingCompatibilityAction
    let appVersion: String
    let bundleIdentifier: String
    let teamIdentifier: String

    func matches(_ app: ChatGPTApplication) -> Bool {
        app.version == appVersion &&
            app.bundleIdentifier == bundleIdentifier &&
            app.teamIdentifier == teamIdentifier
    }
}

@MainActor
@Observable
final class AppModel {
    let store: ProfileStore
    private let transaction: SwitchTransaction
    private let verifier: AccountVerifier
    private let locateApplication: @Sendable () throws -> ChatGPTApplication
    private let configManager: CodexConfigManager
    private let authentication: AuthenticationCoordinator
    private let compatibilityPolicy: CompatibilityPolicy
    private let presentManagementWindow: @MainActor @Sendable () -> Void

    var document = ProfileStoreDocument()
    var isWorking = false
    var canCancelCurrentOperation = false
    var statusMessage = "Ready"
    var lastError: String?
    var authenticationState: AuthenticationState = .idle
    var authenticationProfileID: UUID?
    var canOpenBrowserAgain = false
    var canCheckPendingSignIn = false
    var isCheckingPendingSignIn = false
    var recoveryMessage: String?
    var transientIdentity: String?
    var transientIdentities: [UUID: String] = [:]
    var isChatGPTRunning = false
    var compatibilityStatus: CompatibilityStatus = .provisional
    var compatibilitySummary: String?
    var isProvisionalCompatibilityAcknowledged = false
    var isCompatibilitySelectable = true
    var validationHistory: [UUID] = []
    var pendingLiveSessionHandoff: PendingLiveSessionHandoff?
    var pendingCompatibilityAcknowledgement: PendingCompatibilityAcknowledgement?

    @ObservationIgnored private var operationTask: Task<Void, Never>?
    private var validationAuthorization: GuidedValidationAuthorization?
    private var installedApplication: ChatGPTApplication?
    @ObservationIgnored private var didStart = false

    init(
        store: ProfileStore = ProfileStore(),
        transaction: SwitchTransaction? = nil,
        compatibilityPolicy: CompatibilityPolicy = CompatibilityPolicy(),
        locateApplication: @escaping @Sendable () throws -> ChatGPTApplication = {
            try ChatGPTLocator().locate()
        },
        presentManagementWindow: @escaping @MainActor @Sendable () -> Void = {
            ManagementWindowPresenter.presentExisting()
        }
    ) {
        self.store = store
        verifier = AccountVerifier()
        self.locateApplication = locateApplication
        configManager = CodexConfigManager()
        self.compatibilityPolicy = compatibilityPolicy
        self.transaction = transaction ?? SwitchTransaction(store: store)
        self.presentManagementWindow = presentManagementWindow
        authentication = AuthenticationCoordinator(browserOpener: { url in
            NSWorkspace.shared.open(url)
        })
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        SwitchLogger.started()
        setupWorkspaceObservers()
        updateProcessRunningState()
        do {
            document = try store.ensureAdoptedDefaultProfile()
        } catch {
            lastError = error.localizedDescription
        }
        isWorking = true
        statusMessage = "Checking recovery…"
        operationTask = Task { @MainActor [weak self] in
            await self?.recoverStartup()
        }
    }

    private func setupWorkspaceObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateProcessRunningState()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateProcessRunningState()
            }
        }
    }

    func updateProcessRunningState() {
        guard let app = installedApplication ?? (try? locateApplication()) else {
            isChatGPTRunning = false
            return
        }
        isChatGPTRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).isEmpty
    }

    var activeProfile: CodexProfile? {
        guard let id = activeProfileID else { return nil }
        return document.profiles.first(where: { $0.id == id })
    }

    var activeProfileID: UUID? {
        document.lastCommittedProfileID ?? document.activeProfileID
    }

    var currentAppVersion: String? {
        installedApplication?.version
    }

    var validationMode: Bool {
        validationAuthorization != nil
    }

    var hasPendingLiveSessionHandoff: Bool {
        pendingLiveSessionHandoff != nil
    }

    var hasPendingSwitchConfirmation: Bool {
        pendingLiveSessionHandoff != nil || pendingCompatibilityAcknowledgement != nil
    }

    func isReady(_ profile: CodexProfile) -> Bool {
        return recoveryMessage == nil &&
            profile.expectedIdentityHash != nil &&
            isCompatibilitySelectable
    }

    func refresh() {
        do {
            document = try store.ensureAdoptedDefaultProfile()
            updateCompatibilityStatus()
            if recoveryMessage == nil {
                statusMessage = "Ready"
            }
            lastError = nil
        } catch {
            statusMessage = "Setup unavailable"
            lastError = error.localizedDescription
        }
    }

    func switchTo(_ profile: CodexProfile) {
        guard !hasPendingSwitchConfirmation else { return }
        requestCompatibility(for: .switchProfile(id: profile.id, displayName: profile.displayName))
    }

    func confirmProvisionalCompatibility() {
        guard !isWorking, let pendingCompatibilityAcknowledgement else { return }
        do {
            let app = try locateApplication()
            guard pendingCompatibilityAcknowledgement.matches(app) else {
                self.pendingCompatibilityAcknowledgement = nil
                updateCompatibilityStatus()
                lastError = "The installed ChatGPT version changed. Review provisional compatibility again."
                statusMessage = "Compatibility changed"
                return
            }
            let record = try store.compatibility(for: app)
            let acknowledged = compatibilityPolicy.acknowledging(record)
            guard compatibilityPolicy.decision(for: acknowledged) == .allowed else {
                self.pendingCompatibilityAcknowledgement = nil
                updateCompatibilityStatus()
                lastError = "This ChatGPT version can no longer be acknowledged for provisional switching."
                statusMessage = "Compatibility changed"
                return
            }
            document = try store.setCompatibility(acknowledged)
            self.pendingCompatibilityAcknowledgement = nil
            updateCompatibilityStatus()
            SwitchLogger.compatibility(.provisional)
            perform(pendingCompatibilityAcknowledgement.action)
        } catch {
            self.pendingCompatibilityAcknowledgement = nil
            lastError = error.localizedDescription
            statusMessage = "Could not save compatibility choice"
        }
    }

    func cancelProvisionalCompatibility() {
        guard !isWorking else { return }
        pendingCompatibilityAcknowledgement = nil
        lastError = nil
        statusMessage = activeProfile.map { "Active: \($0.displayName)" } ?? "Compatibility confirmation cancelled"
    }

    func confirmLiveSessionHandoff() {
        guard !isWorking,
              let pendingLiveSessionHandoff,
              let profile = document.profiles.first(where: { $0.id == pendingLiveSessionHandoff.targetProfileID }) else {
            cancelLiveSessionHandoff()
            return
        }
        self.pendingLiveSessionHandoff = nil
        startSwitch(to: profile, liveSessionHandoff: .confirmedGracefulQuit)
    }

    func cancelLiveSessionHandoff() {
        guard !isWorking else { return }
        pendingLiveSessionHandoff = nil
        lastError = nil
        if let activeProfile {
            statusMessage = "Active: \(activeProfile.displayName)"
        } else {
            statusMessage = "Switch cancelled"
        }
    }

    private func startSwitch(
        to profile: CodexProfile,
        liveSessionHandoff: LiveSessionHandoff
    ) {
        guard !isWorking, recoveryMessage == nil else { return }
        isWorking = true
        canCancelCurrentOperation = false
        statusMessage = "Switching to \(profile.displayName)…"
        lastError = nil
        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let outcome = try await transaction.switchTo(
                    profile.id,
                    validation: validationAuthorization,
                    liveSessionHandoff: liveSessionHandoff
                )
                pendingLiveSessionHandoff = nil
                document = try store.load()
                if validationMode, outcome == .committed {
                    validationHistory.append(profile.id)
                }
                statusMessage = outcome == .committed ? "Active: \(profile.displayName)" : "Already active: \(profile.displayName)"
                updateCompatibilityStatus()
            } catch is CancellationError {
                lastError = nil
                statusMessage = "Switch cancelled"
            } catch let error as ProfileError {
                let operationError = error.localizedDescription
                if error.requiresLiveSessionHandoffConfirmation {
                    pendingLiveSessionHandoff = PendingLiveSessionHandoff(
                        targetProfileID: profile.id,
                        targetDisplayName: profile.displayName,
                        sourceDisplayName: activeProfile?.displayName ?? "the active profile"
                    )
                    statusMessage = "Confirmation required"
                    lastError = nil
                    presentManagementWindow()
                } else if error.invalidatesGuidedValidation {
                    validationAuthorization = nil
                    validationHistory = []
                    statusMessage = "Guided diagnostics stopped"
                    lastError = operationError
                } else if error.requiresRecovery {
                    recoveryMessage = operationError
                    statusMessage = "Recovery required"
                    lastError = operationError
                } else {
                    statusMessage = "Switch failed"
                    lastError = operationError
                }
                do {
                    document = try store.load()
                    updateCompatibilityStatus()
                } catch {
                    lastError = error.localizedDescription
                }
            } catch {
                let operationError = Task.isCancelled ? nil : error.localizedDescription
                statusMessage = Task.isCancelled ? "Switch cancelled" : "Switch failed"
                do {
                    document = try store.load()
                    updateCompatibilityStatus()
                } catch {
                    lastError = error.localizedDescription
                }
                lastError = operationError ?? lastError
            }
            isWorking = false
            canCancelCurrentOperation = false
            operationTask = nil
        }
    }

    private func requestCompatibility(for action: PendingCompatibilityAction) {
        guard !isWorking, recoveryMessage == nil else { return }
        do {
            let app = try locateApplication()
            installedApplication = app
            let record = try store.compatibility(for: app)
            compatibilityStatus = record.status
            compatibilitySummary = record.summary
            isProvisionalCompatibilityAcknowledged = record.provisionalAcknowledgedAt != nil
            isCompatibilitySelectable = compatibilityPolicy.canSelectProfile(with: record)
            switch compatibilityPolicy.decision(for: record) {
            case .allowed:
                perform(action)
            case .requiresAcknowledgement:
                pendingCompatibilityAcknowledgement = PendingCompatibilityAcknowledgement(
                    action: action,
                    appVersion: app.version,
                    bundleIdentifier: app.bundleIdentifier,
                    teamIdentifier: app.teamIdentifier
                )
                statusMessage = "Compatibility confirmation required"
                lastError = nil
                presentManagementWindow()
            case .blocked(let message):
                statusMessage = "ChatGPT version blocked"
                lastError = message
            }
        } catch {
            statusMessage = "Compatibility unavailable"
            lastError = error.localizedDescription
        }
    }

    private func perform(_ action: PendingCompatibilityAction) {
        switch action {
        case .switchProfile(let id, _):
            guard let profile = document.profiles.first(where: { $0.id == id }) else {
                lastError = ProfileError.missingProfile.localizedDescription
                return
            }
            startSwitch(to: profile, liveSessionHandoff: .requireConfirmation)
        case .openChatGPT:
            startOpenChatGPT()
        }
    }

    func openChatGPT() {
        guard !hasPendingSwitchConfirmation, !isChatGPTRunning else { return }
        requestCompatibility(for: .openChatGPT)
    }

    private func startOpenChatGPT() {
        guard !isWorking, recoveryMessage == nil, !isChatGPTRunning else { return }
        isWorking = true
        canCancelCurrentOperation = false
        statusMessage = "Preparing ChatGPT…"
        lastError = nil
        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await transaction.launchActive(validation: validationAuthorization)
                statusMessage = "ChatGPT opened"
            } catch is CancellationError {
                lastError = nil
                statusMessage = "Open cancelled"
            } catch {
                lastError = Task.isCancelled ? nil : error.localizedDescription
                statusMessage = Task.isCancelled ? "Open cancelled" : "Could not open ChatGPT"
            }
            isWorking = false
            canCancelCurrentOperation = false
            operationTask = nil
        }
    }

    func createProfile(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "Enter a profile name first."
            return
        }
        do {
            let result = try store.createManagedProfile(named: trimmed)
            try configManager.ensureFileCredentialStorage(for: result.1, backupRoot: store.configBackupsURL)
            document = result.0
            statusMessage = "Created \(trimmed). Choose Sign In to open the browser."
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func rename(_ profile: CodexProfile, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != profile.displayName else { return }
        var updated = profile
        updated.displayName = trimmed
        do {
            document = try store.update(updated)
            statusMessage = "Renamed to \(trimmed)"
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signIn(_ profile: CodexProfile) {
        guard !isWorking else { return }
        isWorking = true
        canCancelCurrentOperation = true
        authenticationState = .preparing
        authenticationProfileID = profile.id
        canOpenBrowserAgain = false
        canCheckPendingSignIn = false
        isCheckingPendingSignIn = false
        SwitchLogger.authenticationStage("preparing")
        statusMessage = "Preparing browser sign-in for \(profile.displayName)…"
        lastError = nil
        transientIdentity = nil
        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isWorking = false
                self.canCancelCurrentOperation = false
                self.isCheckingPendingSignIn = false
                self.authenticationProfileID = nil
                self.operationTask = nil
            }
            do {
                try configManager.ensureFileCredentialStorage(for: profile, backupRoot: store.configBackupsURL)
                let identity = try await authentication.signIn(profile: profile) { [weak self] state in
                    await self?.applyAuthenticationProgress(state, profileName: profile.displayName)
                }
                if let expected = profile.expectedIdentityHash, expected != identity.identityHash {
                    throw ProfileError.identityMismatch
                }
                var updated = profile
                updated.expectedIdentityHash = identity.identityHash
                updated.lastValidatedAppVersion = try locateApplication().version
                updated.lastValidatedAt = Date()
                document = try store.update(updated)
                transientIdentity = identity.email
                transientIdentities[profile.id] = identity.email
                authenticationState = .completed
                canOpenBrowserAgain = false
                canCheckPendingSignIn = false
                SwitchLogger.authenticationFinished(success: true)
                statusMessage = "Identity verified. Ready for the next step."
            } catch is CancellationError {
                authenticationState = .cancelled
                canOpenBrowserAgain = false
                canCheckPendingSignIn = false
                statusMessage = "Browser sign-in cancelled"
            } catch {
                authenticationState = Task.isCancelled ? .cancelled : .failed(error.localizedDescription)
                canOpenBrowserAgain = false
                canCheckPendingSignIn = false
                SwitchLogger.authenticationFinished(success: false)
                if Task.isCancelled {
                    statusMessage = "Browser sign-in cancelled"
                } else {
                    lastError = error.localizedDescription
                    statusMessage = "Sign-in failed"
                }
            }
        }
    }

    func cancelCurrentOperation() {
        guard canCancelCurrentOperation else { return }
        operationTask?.cancel()
        if isWorking {
            statusMessage = "Cancelling operation…"
        }
        Task { [authentication] in
            await authentication.cancel()
        }
    }

    func retryRecovery() {
        guard !isWorking, recoveryMessage != nil else { return }
        isWorking = true
        canCancelCurrentOperation = false
        statusMessage = "Checking recovery…"
        lastError = nil
        operationTask = Task { @MainActor [weak self] in
            await self?.recoverStartup()
        }
    }

    func openBrowserAgain() {
        guard isWorking, canOpenBrowserAgain else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if await authentication.openBrowserAgain() {
                statusMessage = "Opened the browser again; finish sign-in there."
            } else {
                lastError = "The active browser sign-in is no longer available. Choose Sign In to restart it."
            }
        }
    }

    func checkPendingSignIn() {
        guard isWorking, canCheckPendingSignIn, !isCheckingPendingSignIn else { return }
        isCheckingPendingSignIn = true
        statusMessage = "Checking the signed-in account…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            let accepted = await authentication.checkPendingSignIn()
            isCheckingPendingSignIn = false
            guard authenticationState == .awaitingCallback else { return }
            if accepted {
                statusMessage = "Verifying identity…"
            } else {
                statusMessage = "No account found yet. Finish browser sign-in."
            }
        }
    }

    private func applyAuthenticationProgress(_ state: AuthenticationState, profileName: String) {
        authenticationState = state
        switch state {
        case .preparing:
            canOpenBrowserAgain = false
            canCheckPendingSignIn = false
            SwitchLogger.authenticationStage("preparing")
            statusMessage = "Preparing sign-in for \(profileName)…"
        case .requestingLoginURL:
            canOpenBrowserAgain = false
            canCheckPendingSignIn = false
            SwitchLogger.authenticationStage("requesting-login-url")
            statusMessage = "Requesting browser sign-in…"
        case .openingBrowser:
            SwitchLogger.authenticationStage("opening-browser")
            statusMessage = "Opening default browser…"
        case .awaitingCallback:
            canOpenBrowserAgain = true
            canCheckPendingSignIn = true
            SwitchLogger.authenticationStage("awaiting-callback")
            statusMessage = "Waiting for browser sign-in…"
        case .verifying:
            canOpenBrowserAgain = false
            canCheckPendingSignIn = false
            SwitchLogger.authenticationStage("verifying")
            statusMessage = "Verifying account identity…"
        case .completed, .cancelled, .failed, .idle:
            canOpenBrowserAgain = false
            canCheckPendingSignIn = false
        }
    }

    func verify(_ profile: CodexProfile) {
        guard !isWorking else { return }
        isWorking = true
        canCancelCurrentOperation = true
        statusMessage = "Verifying \(profile.displayName)…"
        lastError = nil
        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try configManager.ensureFileCredentialStorage(for: profile, backupRoot: store.configBackupsURL)
                let identity = try await verifier.verify(profile)
                var updated = profile
                updated.expectedIdentityHash = identity.identityHash
                updated.lastValidatedAppVersion = try locateApplication().version
                updated.lastValidatedAt = Date()
                document = try store.update(updated)
                transientIdentity = identity.email
                transientIdentities[profile.id] = identity.email
                statusMessage = "Identity verified"
            } catch is CancellationError {
                lastError = nil
                statusMessage = "Verification cancelled"
            } catch {
                lastError = Task.isCancelled ? nil : error.localizedDescription
                statusMessage = Task.isCancelled ? "Verification cancelled" : "Verification failed"
            }
            isWorking = false
            canCancelCurrentOperation = false
            operationTask = nil
        }
    }

    func remove(_ profile: CodexProfile) {
        guard profile.storageKind == .managed, profile.id != activeProfileID, !isWorking else { return }
        do {
            var updated = try store.load()
            let profileRoot = profile.codexHomeURL.deletingLastPathComponent()
            try store.validate(profile)
            guard SecureFileSystem.isPath(profileRoot, inside: store.profilesRoot) else {
                throw ProfileError.invalidPath(profileRoot.path)
            }
            updated.profiles.removeAll { $0.id == profile.id }
            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: profileRoot, resultingItemURL: &trashedURL)
            do {
                try store.save(updated)
                document = updated
            } catch {
                if let trashedURL, let trashedPath = trashedURL.path, FileManager.default.fileExists(atPath: trashedPath) {
                    try? FileManager.default.moveItem(at: URL(fileURLWithPath: trashedPath), to: profileRoot)
                }
                throw error
            }
            statusMessage = "Removed \(profile.displayName)"
        } catch {
            lastError = error.localizedDescription
        }
    }

    func openProfile(_ profile: CodexProfile) {
        NSWorkspace.shared.open(profile.codexHomeURL)
    }

    func beginGuidedValidation() {
        guard !isWorking, recoveryMessage == nil else { return }
        let bound = document.profiles.filter { $0.expectedIdentityHash != nil }
        guard bound.count == 2, let activeID = activeProfileID,
              bound.contains(where: { $0.id == activeID }) else {
            lastError = "Guided diagnostics require exactly two identity-bound profiles, including the active profile."
            return
        }
        let profileIDs = Set(bound.map(\.id))
        isWorking = true
        canCancelCurrentOperation = false
        statusMessage = "Checking the committed ChatGPT profile…"
        lastError = nil
        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let authorization = try await transaction.prepareGuidedValidation(profileIDs: profileIDs)
                validationAuthorization = authorization
                validationHistory = [activeID]
                updateCompatibilityStatus()
                statusMessage = "Guided diagnostics: complete ten alternating switches and inspect canaries."
            } catch let error as ProfileError {
                validationAuthorization = nil
                validationHistory = []
                lastError = error.localizedDescription
                statusMessage = "Could not start guided diagnostics"
            } catch {
                validationAuthorization = nil
                validationHistory = []
                lastError = error.localizedDescription
                statusMessage = "Could not start guided diagnostics"
            }
            isWorking = false
            canCancelCurrentOperation = false
            operationTask = nil
        }
    }

    func completeGuidedValidation() {
        guard !isWorking, let validationAuthorization, validationHistory.count >= 11 else {
            lastError = "Complete at least ten alternating A → B switches before recording verified compatibility."
            return
        }
        let distinct = Set(validationHistory)
        guard distinct == validationAuthorization.profileIDs,
              zip(validationHistory, validationHistory.dropFirst()).allSatisfy({ $0 != $1 }) else {
            lastError = "Validation must alternate between the authorized profile pair."
            return
        }
        let transitionCount = validationHistory.count - 1
        isWorking = true
        canCancelCurrentOperation = false
        statusMessage = "Confirming the final guided-validation state…"
        lastError = nil
        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await transaction.confirmActive(validation: validationAuthorization)
                let app = try locateApplication()
                guard validationAuthorization.matches(app: app) else {
                    throw ProfileError.compatibilityAcknowledgementRequired(
                        "The installed ChatGPT version changed. Restart guided diagnostics."
                    )
                }
                _ = try store.setCompatibility(CompatibilityRecord(
                    appVersion: app.version,
                    bundleIdentifier: app.bundleIdentifier,
                    teamIdentifier: app.teamIdentifier,
                    status: .verified,
                    checkedAt: Date(),
                    summary: "Human-confirmed guided isolation validation (\(transitionCount) transitions)."
                ))
                SwitchLogger.compatibility(.verified)
                self.validationAuthorization = nil
                validationHistory = []
                updateCompatibilityStatus()
                statusMessage = "Verified compatibility recorded for ChatGPT \(app.version)"
            } catch {
                self.validationAuthorization = nil
                validationHistory = []
                lastError = error.localizedDescription
                statusMessage = "Guided diagnostics must be restarted"
            }
            isWorking = false
            canCancelCurrentOperation = false
            operationTask = nil
        }
    }

    func markDiagnosticsBlocked() {
        guard let validationAuthorization else { return }
        do {
            let app = try locateApplication()
            guard validationAuthorization.matches(app: app) else {
                self.validationAuthorization = nil
                validationHistory = []
                lastError = "The installed ChatGPT version changed. Restart guided diagnostics."
                return
            }
            _ = try store.setCompatibility(CompatibilityRecord(
                appVersion: app.version,
                bundleIdentifier: app.bundleIdentifier,
                teamIdentifier: app.teamIdentifier,
                status: .blocked,
                checkedAt: Date(),
                summary: "Manual validation found account-specific state outside the controlled roots."
            ))
            SwitchLogger.compatibility(.blocked)
            self.validationAuthorization = nil
            validationHistory = []
            updateCompatibilityStatus()
            statusMessage = "ChatGPT version blocked"
        } catch {
            lastError = error.localizedDescription
        }
    }

    func exitValidationMode() {
        validationAuthorization = nil
        validationHistory = []
        statusMessage = "Guided diagnostics cancelled"
    }

    private func recoverStartup() async {
        let result = await transaction.recoverIfNeeded()
        SwitchLogger.recovery(result.recovered ? "recovered" : "required")
        isWorking = false
        canCancelCurrentOperation = false
        operationTask = nil
        if !result.recovered {
            updateCompatibilityStatus()
            recoveryMessage = result.message
            statusMessage = "Recovery required"
            lastError = nil
        } else {
            recoveryMessage = nil
            refresh()
            for profile in document.profiles where profile.expectedIdentityHash != nil {
                if let identity = try? await verifier.verify(profile) {
                    transientIdentities[profile.id] = identity.email
                    if profile.id == activeProfileID {
                        transientIdentity = identity.email
                    }
                }
            }
            if result.message != "No interrupted switch was found." {
                statusMessage = result.message
            }
        }
    }

    private func updateCompatibilityStatus() {
        do {
            let app = try locateApplication()
            installedApplication = app
            let record = try store.compatibility(for: app)
            compatibilityStatus = record.status
            compatibilitySummary = record.summary
            isProvisionalCompatibilityAcknowledged = record.provisionalAcknowledgedAt != nil
            isCompatibilitySelectable = compatibilityPolicy.canSelectProfile(with: record)
        } catch {
            installedApplication = nil
            compatibilityStatus = .provisional
            compatibilitySummary = nil
            isProvisionalCompatibilityAcknowledged = false
            isCompatibilitySelectable = false
        }
        updateProcessRunningState()
    }
}

private extension ProfileError {
    var requiresLiveSessionHandoffConfirmation: Bool {
        if case .liveSessionHandoffRequired = self { return true }
        return false
    }

    var invalidatesGuidedValidation: Bool {
        if case .guidedValidationInvalidated = self { return true }
        return false
    }

    var requiresRecovery: Bool {
        if case .recoveryRequired = self { return true }
        return false
    }
}
