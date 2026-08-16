@testable import CodexSwitch
@testable import CodexSwitchCore
import Darwin
import Foundation
import XCTest

@MainActor
final class AppModelHandoffTests: XCTestCase {
    func testProvisionalAcknowledgementCancelsCleanlyThenPersistsAndContinuesSwitch() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexSwitchAppModelCompatibilityTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(root: root)
        var source = try store.createManagedProfile(named: "Personal").1
        source.expectedIdentityHash = "source-identity"
        _ = try store.update(source)
        var target = try store.createManagedProfile(named: "Secondary").1
        target.expectedIdentityHash = "target-identity"
        _ = try store.update(target)
        _ = try store.setActive(source.id, committed: true)

        let application = appModelFixtureApplication()
        let process = AppModelProcessController(
            snapshot: appModelSnapshot(profile: source),
            onQuit: {}
        )
        let transaction = SwitchTransaction(
            store: store,
            processController: process,
            verifier: AppModelAccountVerifier(),
            probe: AppModelCompatibilityProbe(application: application)
        )
        var presentationCount = 0
        let model = AppModel(
            store: store,
            transaction: transaction,
            locateApplication: { application },
            presentManagementWindow: { presentationCount += 1 }
        )
        model.document = try store.load()

        model.switchTo(target)
        XCTAssertNotNil(model.pendingCompatibilityAcknowledgement)
        XCTAssertEqual(process.events, [])
        model.cancelProvisionalCompatibility()
        XCTAssertNil(model.pendingCompatibilityAcknowledgement)
        XCTAssertNil(try store.compatibility(for: application).provisionalAcknowledgedAt)
        XCTAssertEqual(try store.load().lastCommittedProfileID, source.id)

        model.switchTo(target)
        XCTAssertNotNil(model.pendingCompatibilityAcknowledgement)
        model.confirmProvisionalCompatibility()
        let switchCommitted = await waitUntil {
            !model.isWorking && model.activeProfileID == target.id
        }

        XCTAssertTrue(switchCommitted)
        XCTAssertNil(model.pendingCompatibilityAcknowledgement)
        XCTAssertNotNil(try store.compatibility(for: application).provisionalAcknowledgedAt)
        XCTAssertEqual(process.events.filter { $0 == "quit" }.count, 1)
        XCTAssertEqual(process.events.filter { $0 == "launch:\(target.id.uuidString)" }.count, 1)
        XCTAssertEqual(presentationCount, 2)
    }

    func testCancellationAndRepeatedConfirmationPreserveHistoryAndRunOneTransaction() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexSwitchAppModelTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(root: root)
        _ = try store.ensureAdoptedDefaultProfile(named: "Adopted")

        var source = try store.createManagedProfile(named: "Personal").1
        source.expectedIdentityHash = "source-identity"
        _ = try store.update(source)
        var target = try store.createManagedProfile(named: "Secondary").1
        target.expectedIdentityHash = "target-identity"
        _ = try store.update(target)
        _ = try store.setActive(source.id, committed: true)

        let application = appModelFixtureApplication()
        _ = try store.setCompatibility(CompatibilityRecord(
            appVersion: application.version,
            bundleIdentifier: application.bundleIdentifier,
            teamIdentifier: application.teamIdentifier,
            status: .verified
        ))

        let lockDirectory = source.codexHomeURL
            .appendingPathComponent("thread-writer-locks", isDirectory: true)
        try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
        let lockURL = lockDirectory.appendingPathComponent("private-app-model-fixture.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        guard descriptor >= 0 else { return }
        defer {
            _ = flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)

        let process = AppModelProcessController(
            snapshot: appModelSnapshot(profile: source),
            onQuit: {
                _ = flock(descriptor, LOCK_UN)
            }
        )
        let transaction = SwitchTransaction(
            store: store,
            processController: process,
            verifier: AppModelAccountVerifier(),
            probe: AppModelCompatibilityProbe(application: application)
        )
        var presentationCount = 0
        let model = AppModel(
            store: store,
            transaction: transaction,
            locateApplication: { application },
            presentManagementWindow: { presentationCount += 1 }
        )
        model.document = try store.load()
        model.beginGuidedValidation()
        let validationPrepared = await waitUntil { !model.isWorking && model.validationMode }
        XCTAssertTrue(validationPrepared)
        let originalHistory = model.validationHistory
        XCTAssertEqual(originalHistory, [source.id])

        model.switchTo(target)
        let firstConfirmationPresented = await waitUntil {
            !model.isWorking && model.hasPendingLiveSessionHandoff
        }
        XCTAssertTrue(firstConfirmationPresented)
        model.cancelLiveSessionHandoff()

        XCTAssertFalse(model.hasPendingLiveSessionHandoff)
        XCTAssertTrue(model.validationMode)
        XCTAssertEqual(model.validationHistory, originalHistory)
        XCTAssertEqual(process.events.filter { $0 == "quit" }.count, 0)
        XCTAssertEqual(process.events.filter { $0.hasPrefix("launch:") }.count, 0)
        XCTAssertTrue(try XCTUnwrap(process.snapshot).exposes(profile: source))

        model.switchTo(target)
        let secondConfirmationPresented = await waitUntil {
            !model.isWorking && model.hasPendingLiveSessionHandoff
        }
        XCTAssertTrue(secondConfirmationPresented)
        model.confirmLiveSessionHandoff()
        model.confirmLiveSessionHandoff()
        let switchCommitted = await waitUntil {
            !model.isWorking && model.activeProfileID == target.id
        }
        XCTAssertTrue(switchCommitted)

        XCTAssertEqual(process.events.filter { $0 == "quit" }.count, 1)
        XCTAssertEqual(process.events.filter { $0 == "launch:\(target.id.uuidString)" }.count, 1)
        XCTAssertTrue(model.validationMode)
        XCTAssertEqual(model.validationHistory, originalHistory + [target.id])
        XCTAssertFalse(model.hasPendingLiveSessionHandoff)
        XCTAssertEqual(presentationCount, 2)
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        attempts: Int = 200
    ) async -> Bool {
        for _ in 0..<attempts {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

private func appModelFixtureApplication() -> ChatGPTApplication {
    ChatGPTApplication(
        bundleURL: URL(fileURLWithPath: "/Applications/ChatGPT.app"),
        executableURL: URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT"),
        codexExecutableURL: URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
        bundleIdentifier: "com.openai.codex",
        version: "app-model-fixture",
        teamIdentifier: "fixture-team"
    )
}

private func appModelSnapshot(profile: CodexProfile) -> ChatGPTProcessSnapshot {
    ChatGPTProcessSnapshot(
        mainPID: 4242,
        accountBearingPIDs: [4242],
        commandLines: [],
        userDataRoots: [profile.electronDataURL.standardizedFileURL.path],
        cacheRoots: [profile.electronCacheURL.standardizedFileURL.path],
        codexHomeRoots: [profile.codexHomeURL.standardizedFileURL.path],
        mainArgumentsReadable: true,
        mainHasExplicitCacheOverride: true
    )
}

private struct AppModelAccountVerifier: AccountVerifying {
    func verify(_ profile: CodexProfile) async throws -> AccountIdentity {
        guard let identityHash = profile.expectedIdentityHash else {
            throw ProfileError.identityUnverified
        }
        return AccountIdentity(email: "fixture@example.invalid", identityHash: identityHash)
    }
}

private struct AppModelCompatibilityProbe: CompatibilityProbing {
    let application: ChatGPTApplication

    func app() throws -> ChatGPTApplication {
        application
    }

    func check(profile: CodexProfile) throws -> CompatibilityReport {
        CompatibilityReport(
            passed: true,
            appVersion: application.version,
            checkedPaths: [],
            message: "fixture"
        )
    }
}

private final class AppModelProcessController: ChatGPTProcessControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var storedSnapshot: ChatGPTProcessSnapshot?
    private var storedEvents: [String] = []
    private let onQuit: @Sendable () -> Void

    init(snapshot: ChatGPTProcessSnapshot?, onQuit: @escaping @Sendable () -> Void) {
        storedSnapshot = snapshot
        self.onQuit = onQuit
    }

    var snapshot: ChatGPTProcessSnapshot? {
        lock.withLock { storedSnapshot }
    }

    var events: [String] {
        lock.withLock { storedEvents }
    }

    func inspectSession() throws -> ChatGPTProcessSnapshot? {
        lock.withLock {
            storedEvents.append("inspect")
            return storedSnapshot
        }
    }

    func quitGracefully() async throws {
        lock.withLock {
            storedEvents.append("quit")
            storedSnapshot = nil
        }
        onQuit()
    }

    func launchAndConfirm(profile: CodexProfile) async throws {
        lock.withLock {
            storedEvents.append("launch:\(profile.id.uuidString)")
            storedSnapshot = appModelSnapshot(profile: profile)
        }
    }
}
