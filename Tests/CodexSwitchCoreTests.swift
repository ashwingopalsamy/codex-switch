@testable import CodexSwitchCore
import Darwin
import Foundation
import XCTest

final class CodexSwitchCoreTests: XCTestCase {
    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CodexSwitchTests-\(UUID().uuidString)", isDirectory: true)
    }

    func testProfileStoreCreatesAdoptedAndManagedProfiles() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(root: root)

        let first = try store.ensureAdoptedDefaultProfile(named: "Personal")
        XCTAssertEqual(first.profiles.count, 1)
        XCTAssertEqual(first.profiles[0].storageKind, .adoptedDefault)

        let result = try store.createManagedProfile(named: "Secondary")
        XCTAssertEqual(result.0.profiles.count, 2)
        XCTAssertEqual(result.1.storageKind, .managed)
        XCTAssertTrue(SecureFileSystem.isPath(result.1.codexHomeURL, inside: root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.1.codexHomePath))
    }

    func testProfileRenamePreservesSecurityBoundariesAndPaths() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(root: root)

        let initial = try store.ensureAdoptedDefaultProfile(named: "Personal")
        let adopted = initial.profiles[0]
        var updatedAdopted = adopted
        updatedAdopted.displayName = "Main Personal Account"
        let updatedDoc = try store.update(updatedAdopted)
        XCTAssertEqual(updatedDoc.profiles[0].displayName, "Main Personal Account")
        XCTAssertEqual(updatedDoc.profiles[0].id, adopted.id)
        XCTAssertEqual(updatedDoc.profiles[0].codexHomePath, adopted.codexHomePath)
        XCTAssertEqual(updatedDoc.profiles[0].storageKind, .adoptedDefault)

        let managedResult = try store.createManagedProfile(named: "Work")
        let managed = managedResult.1
        var updatedManaged = managed
        updatedManaged.displayName = "Work Profile (Renamed)"
        let managedDoc = try store.update(updatedManaged)
        let foundManaged = try XCTUnwrap(managedDoc.profiles.first(where: { $0.id == managed.id }))
        XCTAssertEqual(foundManaged.displayName, "Work Profile (Renamed)")
        XCTAssertEqual(foundManaged.codexHomePath, managed.codexHomePath)
        XCTAssertEqual(foundManaged.electronDataPath, managed.electronDataPath)
        XCTAssertEqual(foundManaged.storageKind, .managed)
    }

    func testLaunchContextScopesEnvironmentAndDesktopRoots() throws {
        let profile = CodexProfile(
            displayName: "Fixture",
            codexHomePath: "/tmp/profile/codex-home",
            electronDataPath: "/tmp/profile/electron-data",
            electronCachePath: "/tmp/profile/electron-cache",
            storageKind: .managed
        )
        let context = LaunchContext(profile: profile, inheritedEnvironment: ["PATH": "/usr/bin"])
        XCTAssertEqual(context.environment["PATH"], "/usr/bin")
        XCTAssertEqual(context.environment["CODEX_HOME"], profile.codexHomePath)
        XCTAssertTrue(context.arguments.contains("--user-data-dir=/tmp/profile/electron-data"))
        XCTAssertTrue(context.arguments.contains("--disk-cache-dir=/tmp/profile/electron-cache"))
    }

    func testGuidedValidationAuthorizationRequiresExactlyTwoProfiles() {
        let app = fixtureChatGPTApplication()
        XCTAssertNil(GuidedValidationAuthorization(app: app, profileIDs: []))
        XCTAssertNil(GuidedValidationAuthorization(app: app, profileIDs: [UUID()]))
        XCTAssertNil(GuidedValidationAuthorization(app: app, profileIDs: [UUID(), UUID(), UUID()]))
        XCTAssertNotNil(GuidedValidationAuthorization(app: app, profileIDs: [UUID(), UUID()]))
    }

    func testGuidedValidationAuthorizationPinsInstallationAndProfilePair() throws {
        let sourceID = UUID()
        let targetID = UUID()
        let authorization = try XCTUnwrap(GuidedValidationAuthorization(
            app: fixtureChatGPTApplication(),
            profileIDs: [sourceID, targetID]
        ))
        XCTAssertTrue(authorization.permitsTransition(
            sourceID: sourceID,
            targetID: targetID,
            app: fixtureChatGPTApplication()
        ))
        XCTAssertFalse(authorization.permitsTransition(
            sourceID: sourceID,
            targetID: UUID(),
            app: fixtureChatGPTApplication()
        ))
        XCTAssertFalse(authorization.permitsTransition(
            sourceID: sourceID,
            targetID: targetID,
            app: ChatGPTApplication(
                bundleURL: fixtureChatGPTApplication().bundleURL,
                executableURL: fixtureChatGPTApplication().executableURL,
                codexExecutableURL: fixtureChatGPTApplication().codexExecutableURL,
                bundleIdentifier: fixtureChatGPTApplication().bundleIdentifier,
                version: "different-version",
                teamIdentifier: fixtureChatGPTApplication().teamIdentifier
            )
        ))
    }

    func testIdentityHasherNormalizesEmail() {
        XCTAssertEqual(IdentityHasher.normalizeEmail("  USER@Example.COM "), "user@example.com")
        XCTAssertEqual(IdentityHasher.hashEmail("USER@example.com"), IdentityHasher.hashEmail(" user@EXAMPLE.com "))
    }

    func testLiveWriterDetectorDetectsOpenConversation() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let lockDirectory = root.appendingPathComponent("thread-writer-locks", isDirectory: true)
        try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
        let lockURL = lockDirectory.appendingPathComponent("thread.lock")
        FileManager.default.createFile(atPath: lockURL.path, contents: nil)
        let descriptor = open(lockURL.path, O_RDWR | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)

        let profile = CodexProfile(
            displayName: "Fixture",
            codexHomePath: root.path,
            electronDataPath: root.appendingPathComponent("data").path,
            electronCachePath: root.appendingPathComponent("cache").path,
            storageKind: .managed
        )
        XCTAssertEqual(LiveWriterDetector().status(for: profile), .present)
    }

    func testRecoveryJournalRoundTrips() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = RecoveryJournal(url: root.appendingPathComponent("journal.json"))
        let value = SwitchJournal(sourceProfileID: UUID(), targetProfileID: UUID(), phase: .launchingTarget)
        try journal.save(value)
        XCTAssertEqual(try journal.load()?.phase, .launchingTarget)
        try journal.clear()
        XCTAssertNil(try journal.load())
    }

    func testRecoveryJournalDiscardsLegacyFreeFormMessage() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = RecoveryJournal(url: root.appendingPathComponent("journal.json"))
        let value = SwitchJournal(sourceProfileID: UUID(), targetProfileID: UUID(), phase: .failed, message: "user@example.com")
        try journal.save(value)
        let loaded = try journal.load()
        XCTAssertNil(loaded?.message)
        let persisted = try String(contentsOf: root.appendingPathComponent("journal.json"), encoding: .utf8)
        XCTAssertFalse(persisted.contains("user@example.com"))
    }

    func testOperationLockSerializesConcurrentSwitches() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("switch.lock")
        let first = OperationLock(url: url)
        let second = OperationLock(url: url)
        try first.acquire()
        XCTAssertThrowsError(try second.acquire())
        first.release()
        XCTAssertNoThrow(try second.acquire())
        second.release()
    }

    func testManagedProfileSymlinkIsRejected() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        XCTAssertThrowsError(try SecureFileSystem.rejectSymlink(link))
    }

    func testConfigManagerForcesFileCredentialStorageAndBacksUpExistingConfig() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let codexHome = root.appendingPathComponent("codex-home", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let configURL = codexHome.appendingPathComponent("config.toml")
        let original = "model = \"gpt-5\"\ncli_auth_credentials_store = \"keyring\"\n"
        try Data(original.utf8).write(to: configURL)
        let profile = CodexProfile(
            displayName: "Fixture",
            codexHomePath: codexHome.path,
            electronDataPath: root.appendingPathComponent("data").path,
            electronCachePath: root.appendingPathComponent("cache").path,
            storageKind: .managed
        )
        let backupRoot = root.appendingPathComponent("backups", isDirectory: true)
        let manager = CodexConfigManager()
        let backup = try manager.ensureFileCredentialStorage(for: profile, backupRoot: backupRoot)
        XCTAssertNotNil(backup)
        let updated = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(updated.contains("cli_auth_credentials_store = \"file\""))
        XCTAssertFalse(updated.contains("keyring"))
    }

    func testManagedProfileRootsMustStayTogether() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(root: root)
        _ = try store.ensureAdoptedDefaultProfile()
        let result = try store.createManagedProfile(named: "Secondary")
        var invalid = result.1
        invalid.electronDataPath = root.appendingPathComponent("elsewhere").path
        XCTAssertThrowsError(try store.update(invalid))
    }

    func testConfigManagerInsertsCredentialSettingBeforeFirstTable() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let codexHome = root.appendingPathComponent("codex-home", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let configURL = codexHome.appendingPathComponent("config.toml")
        try Data("model = \"gpt-5\"\n[profiles]\ncli_auth_credentials_store = \"keyring\"\n".utf8).write(to: configURL)
        let profile = CodexProfile(
            displayName: "Fixture",
            codexHomePath: codexHome.path,
            electronDataPath: root.appendingPathComponent("data").path,
            electronCachePath: root.appendingPathComponent("cache").path,
            storageKind: .managed
        )
        _ = try CodexConfigManager().ensureFileCredentialStorage(for: profile, backupRoot: root.appendingPathComponent("backups"))
        let text = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("model = \"gpt-5\"\ncli_auth_credentials_store = \"file\"\n[profiles]"))
        XCTAssertTrue(text.contains("[profiles]\ncli_auth_credentials_store = \"keyring\""))
    }

    func testConfigManagerPreservesTopLevelCommentsAndRemovesDuplicateKey() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let codexHome = root.appendingPathComponent("codex-home", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let configURL = codexHome.appendingPathComponent("config.toml")
        let original = "# keep this comment\ncli_auth_credentials_store = \"keyring\" # keep this note\ncli_auth_credentials_store = \"file\"\n[profiles]\nname = \"fixture\"\n"
        try Data(original.utf8).write(to: configURL)
        let profile = CodexProfile(
            displayName: "Fixture",
            codexHomePath: codexHome.path,
            electronDataPath: root.appendingPathComponent("data").path,
            electronCachePath: root.appendingPathComponent("cache").path,
            storageKind: .managed
        )
        _ = try CodexConfigManager().ensureFileCredentialStorage(for: profile, backupRoot: root.appendingPathComponent("backups"))
        let text = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(text.contains("# keep this comment"))
        XCTAssertTrue(text.contains("cli_auth_credentials_store = \"file\" # keep this note"))
        XCTAssertEqual(text.components(separatedBy: "cli_auth_credentials_store").count - 1, 1)
    }

    func testProfileDocumentMigratesAwayFromLegacyValidationMessage() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let profileID = "B30412D1-8BBB-4B5D-9756-5EEC5523563E"
        let profileRoot = root.appendingPathComponent("Profiles/\(profileID)")
        let legacy = """
        {"schemaVersion":1,"profiles":[{"id":"\(profileID)","displayName":"Personal","codexHomePath":"\(profileRoot.path)/codex-home","electronDataPath":"\(profileRoot.path)/electron-data","electronCachePath":"\(profileRoot.path)/electron-cache","storageKind":"managed","lastValidationMessage":"Verified user@example.com"}],"activeProfileID":"\(profileID)","lastCommittedProfileID":"\(profileID)"}
        """
        try Data(legacy.utf8).write(to: root.appendingPathComponent("profiles.json"))
        let document = try ProfileStore(root: root).load()
        XCTAssertEqual(document.schemaVersion, 3)
        XCTAssertNil(document.profiles.first?.lastValidatedAt)
        let migrated = try String(contentsOf: root.appendingPathComponent("profiles.json"), encoding: .utf8)
        XCTAssertFalse(migrated.contains("lastValidationMessage"))
        XCTAssertFalse(migrated.contains("user@example.com"))
    }

    func testCompatibilitySchemaMigratesLegacyStatusesToVersionThree() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let legacy = """
        {"schemaVersion":2,"profiles":[],"compatibilityRecords":[
          {"appVersion":"one","bundleIdentifier":"com.openai.codex","teamIdentifier":"team","status":"unverified"},
          {"appVersion":"two","bundleIdentifier":"com.openai.codex","teamIdentifier":"team","status":"supported"},
          {"appVersion":"three","bundleIdentifier":"com.openai.codex","teamIdentifier":"team","status":"unsupported"}
        ]}
        """
        try Data(legacy.utf8).write(to: root.appendingPathComponent("profiles.json"))

        let document = try ProfileStore(root: root).load()

        XCTAssertEqual(document.schemaVersion, 3)
        XCTAssertEqual(document.compatibilityRecords.map(\.status), [.provisional, .verified, .blocked])
        XCTAssertTrue(document.compatibilityRecords.allSatisfy { $0.provisionalAcknowledgedAt == nil })
        let migrated = try String(contentsOf: root.appendingPathComponent("profiles.json"), encoding: .utf8)
        XCTAssertTrue(migrated.contains("\"provisional\""))
        XCTAssertTrue(migrated.contains("\"verified\""))
        XCTAssertTrue(migrated.contains("\"blocked\""))
        XCTAssertFalse(migrated.contains("\"unverified\""))
    }

    func testCompatibilityPolicyRequiresOneProvisionalAcknowledgement() {
        let policy = CompatibilityPolicy()
        let provisional = CompatibilityRecord(
            appVersion: "fixture",
            bundleIdentifier: "com.openai.codex",
            teamIdentifier: "team"
        )
        XCTAssertEqual(policy.decision(for: provisional), .requiresAcknowledgement)
        XCTAssertTrue(policy.canSelectProfile(with: provisional))

        let date = Date(timeIntervalSince1970: 123)
        let acknowledged = policy.acknowledging(provisional, at: date)
        XCTAssertEqual(acknowledged.provisionalAcknowledgedAt, date)
        XCTAssertEqual(policy.decision(for: acknowledged), .allowed)

        var verified = provisional
        verified.status = .verified
        XCTAssertEqual(policy.decision(for: verified), .allowed)

        var blocked = provisional
        blocked.status = .blocked
        blocked.summary = "fixture block"
        XCTAssertEqual(policy.decision(for: blocked), .blocked("fixture block"))
        XCTAssertFalse(policy.canSelectProfile(with: blocked))
    }

    func testLaunchEnvironmentStripsCredentialVariables() {
        let environment = LaunchEnvironment.sanitized([
            "PATH": "/usr/bin",
            "OPENAI_API_KEY": "secret",
            "GITHUB_TOKEN": "secret",
            "CODEX_HOME": "/tmp/old"
        ])
        XCTAssertEqual(environment["PATH"], "/usr/bin")
        XCTAssertNil(environment["OPENAI_API_KEY"])
        XCTAssertNil(environment["GITHUB_TOKEN"])
        XCTAssertNil(environment["CODEX_HOME"])
    }

    func testAuthenticationCoordinatorOpensOfficialBrowserFlow() async throws {
        let fake = FakeAppServerSession()
        let opened = LockedURL()
        let fakeApp = ChatGPTApplication(
            bundleURL: URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            executableURL: URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT"),
            codexExecutableURL: URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            bundleIdentifier: "com.openai.codex",
            version: "fixture",
            teamIdentifier: "fixture-team"
        )
        let coordinator = AuthenticationCoordinator(
            timeoutNanoseconds: 1_000_000_000,
            browserOpener: { url in
                opened.set(url)
                return true
            },
            appProvider: { fakeApp },
            sessionFactory: { _, _ in fake }
        )
        let profile = CodexProfile(
            displayName: "Fixture",
            codexHomePath: "/tmp/codex-home",
            electronDataPath: "/tmp/electron-data",
            electronCachePath: "/tmp/electron-cache",
            storageKind: .managed
        )

        let identity = try await coordinator.signIn(profile: profile)
        XCTAssertEqual(opened.value?.host, "chatgpt.com")
        XCTAssertEqual(identity.identityHash, IdentityHasher.hashEmail("user@example.com"))
        let methods = await fake.methods
        XCTAssertEqual(methods, ["account/login/start", "account/read", "stop"])
    }

    func testAuthenticationCoordinatorReportsProgressOnlyWhenTheBrowserFlowAdvances() async throws {
        let fake = FakeAppServerSession()
        let events = LockedStrings()
        let coordinator = AuthenticationCoordinator(
            timeoutNanoseconds: 1_000_000_000,
            browserOpener: { _ in
                events.append("browser-opened")
                return true
            },
            appProvider: { fixtureChatGPTApplication() },
            sessionFactory: { _, _ in fake }
        )

        _ = try await coordinator.signIn(profile: fixtureProfile()) { state in
            switch state {
            case .preparing: events.append("preparing")
            case .requestingLoginURL: events.append("requesting-login-url")
            case .openingBrowser: events.append("opening-browser")
            case .awaitingCallback: events.append("awaiting-callback")
            case .verifying: events.append("verifying")
            default: XCTFail("Unexpected progress state: \(state)")
            }
        }

        XCTAssertEqual(events.values, [
            "preparing",
            "requesting-login-url",
            "opening-browser",
            "browser-opened",
            "awaiting-callback",
            "verifying"
        ])
    }

    func testAuthenticationCoordinatorRejectsUntrustedBrowserURL() async throws {
        let fake = FakeAppServerSession(authURL: URL(string: "https://example.invalid/login")!)
        let opened = LockedURL()
        let fakeApp = ChatGPTApplication(
            bundleURL: URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            executableURL: URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT"),
            codexExecutableURL: URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            bundleIdentifier: "com.openai.codex",
            version: "fixture",
            teamIdentifier: "fixture-team"
        )
        let coordinator = AuthenticationCoordinator(
            timeoutNanoseconds: 1_000_000,
            browserOpener: { url in
                opened.set(url)
                return true
            },
            appProvider: { fakeApp },
            sessionFactory: { _, _ in fake }
        )
        let profile = CodexProfile(
            displayName: "Fixture",
            codexHomePath: "/tmp/codex-home",
            electronDataPath: "/tmp/electron-data",
            electronCachePath: "/tmp/electron-cache",
            storageKind: .managed
        )
        do {
            _ = try await coordinator.signIn(profile: profile)
            XCTFail("Expected untrusted URL to be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("untrusted"))
        }
        XCTAssertNil(opened.value)
    }

    func testAuthenticationCoordinatorHandlesFailedBrowserCompletionAndCancelsSession() async throws {
        let fake = FakeAppServerSession(events: [.loginCompleted(loginID: "fixture-login", success: false)])
        let fakeApp = fixtureChatGPTApplication()
        let coordinator = AuthenticationCoordinator(
            timeoutNanoseconds: 1_000_000_000,
            browserOpener: { _ in true },
            appProvider: { fakeApp },
            sessionFactory: { _, _ in fake }
        )

        do {
            _ = try await coordinator.signIn(profile: fixtureProfile())
            XCTFail("Expected failed browser completion")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Browser sign-in was not completed.")
        }
        let methods = await fake.methods
        XCTAssertEqual(methods, ["account/login/start", "account/login/cancel", "stop"])
    }

    func testAuthenticationCoordinatorRejectsMismatchedCompletionAndIdentity() async throws {
        let fake = FakeAppServerSession(events: [.loginCompleted(loginID: "different-login", success: true)])
        let fakeApp = fixtureChatGPTApplication()
        let coordinator = AuthenticationCoordinator(
            timeoutNanoseconds: 1_000_000_000,
            browserOpener: { _ in true },
            appProvider: { fakeApp },
            sessionFactory: { _, _ in fake }
        )

        do {
            _ = try await coordinator.signIn(profile: fixtureProfile())
            XCTFail("Expected mismatched completion to be rejected")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Browser sign-in was not completed.")
        }
        let methods = await fake.methods
        XCTAssertEqual(methods, ["account/login/start", "account/login/cancel", "stop"])

        let identityFake = FakeAppServerSession()
        var boundProfile = fixtureProfile()
        boundProfile.expectedIdentityHash = IdentityHasher.hashEmail("different@example.com")
        let identityCoordinator = AuthenticationCoordinator(
            timeoutNanoseconds: 1_000_000_000,
            browserOpener: { _ in true },
            appProvider: { fakeApp },
            sessionFactory: { _, _ in identityFake }
        )
        do {
            _ = try await identityCoordinator.signIn(profile: boundProfile)
            XCTFail("Expected identity mismatch")
        } catch {
            guard let profileError = error as? ProfileError else {
                return XCTFail("Expected identity mismatch, got \(error)")
            }
            if case .identityMismatch = profileError {
                // Expected.
            } else {
                XCTFail("Expected identity mismatch, got \(profileError)")
            }
        }
    }

    func testAuthenticationCoordinatorTimeoutCancelsLogin() async throws {
        let fake = FakeAppServerSession(events: nil)
        let fakeApp = fixtureChatGPTApplication()
        let coordinator = AuthenticationCoordinator(
            timeoutNanoseconds: 1_000_000,
            browserOpener: { _ in true },
            appProvider: { fakeApp },
            sessionFactory: { _, _ in fake }
        )

        do {
            _ = try await coordinator.signIn(profile: fixtureProfile())
            XCTFail("Expected browser timeout")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("timed out") || error is CancellationError)
        }
        let methods = await fake.methods
        XCTAssertTrue(methods.contains("account/login/cancel"))
        XCTAssertEqual(methods.last, "stop")
    }

    func testAuthenticationCoordinatorCanReopenPendingBrowserLogin() async throws {
        let fake = FakeAppServerSession(events: nil)
        let opened = LockedCount()
        let fakeApp = fixtureChatGPTApplication()
        let coordinator = AuthenticationCoordinator(
            timeoutNanoseconds: 1_000_000_000,
            browserOpener: { _ in
                opened.increment()
                return true
            },
            appProvider: { fakeApp },
            sessionFactory: { _, _ in fake }
        )

        let task = Task {
            try? await coordinator.signIn(profile: fixtureProfile())
        }
        for _ in 0..<50 where opened.value == 0 {
            try await Task.sleep(for: .milliseconds(2))
        }
        let reopened = await coordinator.openBrowserAgain()
        XCTAssertTrue(reopened)
        task.cancel()
        _ = await task.value
        XCTAssertGreaterThanOrEqual(opened.value, 2)
    }

    func testAuthenticationCoordinatorCannotReopenBeforeAURLExists() async throws {
        let coordinator = AuthenticationCoordinator(
            browserOpener: { _ in
                XCTFail("Browser opener must not run without a pending login URL")
                return true
            }
        )
        let reopened = await coordinator.openBrowserAgain()
        XCTAssertFalse(reopened)
    }

    func testAuthenticationCoordinatorUsesAccountUpdatedAndRetriesUntilReadable() async throws {
        let fake = FakeAppServerSession(
            events: [.accountUpdated(authMode: "chatgpt")],
            readFailuresBeforeSuccess: 2
        )
        let coordinator = AuthenticationCoordinator(
            timeoutNanoseconds: 1_000_000_000,
            reconciliationTimeoutNanoseconds: 100_000_000,
            reconciliationRetryNanoseconds: 1_000_000,
            unboundPollNanoseconds: 1_000_000_000,
            browserOpener: { _ in true },
            appProvider: { fixtureChatGPTApplication() },
            sessionFactory: { _, _ in fake }
        )

        let identity = try await coordinator.signIn(profile: fixtureProfile())
        XCTAssertEqual(identity.identityHash, IdentityHasher.hashEmail("user@example.com"))
        let methods = await fake.methods
        XCTAssertEqual(methods.filter { $0 == "account/read" }.count, 3)
        XCTAssertEqual(methods.last, "stop")
    }

    func testAuthenticationCoordinatorFallsBackToAccountReadForFreshProfile() async throws {
        let fake = FakeAppServerSession(events: nil, readFailuresBeforeSuccess: 1)
        let coordinator = AuthenticationCoordinator(
            timeoutNanoseconds: 1_000_000_000,
            reconciliationRetryNanoseconds: 1_000_000,
            unboundPollNanoseconds: 1_000_000,
            browserOpener: { _ in true },
            appProvider: { fixtureChatGPTApplication() },
            sessionFactory: { _, _ in fake }
        )

        let identity = try await coordinator.signIn(profile: fixtureProfile())
        XCTAssertEqual(identity.identityHash, IdentityHasher.hashEmail("user@example.com"))
        let methods = await fake.methods
        XCTAssertEqual(methods.filter { $0 == "account/read" }.count, 2)
    }

    func testAuthenticationCoordinatorDoesNotAcceptStaleBoundAccountWithoutEvent() async throws {
        let fake = FakeAppServerSession(events: nil)
        var profile = fixtureProfile()
        profile.expectedIdentityHash = IdentityHasher.hashEmail("user@example.com")
        let coordinator = AuthenticationCoordinator(
            timeoutNanoseconds: 2_000_000,
            reconciliationRetryNanoseconds: 1_000_000,
            unboundPollNanoseconds: 1_000_000,
            browserOpener: { _ in true },
            appProvider: { fixtureChatGPTApplication() },
            sessionFactory: { _, _ in fake }
        )

        do {
            _ = try await coordinator.signIn(profile: profile)
            XCTFail("Expected a bound profile without a post-start event to time out")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("timed out") || error is CancellationError)
        }
        let methods = await fake.methods
        XCTAssertFalse(methods.contains("account/read"))
    }

    func testAuthenticationCoordinatorIgnoresUnrelatedAccountUpdate() async throws {
        let fake = FakeAppServerSession(events: [
            .accountUpdated(authMode: "apikey"),
            .loginCompleted(loginID: "fixture-login", success: true)
        ])
        let coordinator = AuthenticationCoordinator(
            timeoutNanoseconds: 1_000_000_000,
            unboundPollNanoseconds: 1_000_000_000,
            browserOpener: { _ in true },
            appProvider: { fixtureChatGPTApplication() },
            sessionFactory: { _, _ in fake }
        )

        _ = try await coordinator.signIn(profile: fixtureProfile())
        let methods = await fake.methods
        XCTAssertEqual(methods.filter { $0 == "account/read" }.count, 1)
    }

    func testAuthenticationCoordinatorManualCheckCanRecoverPendingBoundLogin() async throws {
        let fake = FakeAppServerSession(events: nil, readFailuresBeforeSuccess: 1)
        let opened = LockedCount()
        let expectedIdentityHash = IdentityHasher.hashEmail("user@example.com")
        var profile = fixtureProfile()
        profile.expectedIdentityHash = expectedIdentityHash
        let boundProfile = profile
        let coordinator = AuthenticationCoordinator(
            timeoutNanoseconds: 1_000_000_000,
            browserOpener: { _ in
                opened.increment()
                return true
            },
            appProvider: { fixtureChatGPTApplication() },
            sessionFactory: { _, _ in fake }
        )

        let task = Task {
            try await coordinator.signIn(profile: boundProfile)
        }
        for _ in 0..<50 where opened.value == 0 {
            try await Task.sleep(for: .milliseconds(2))
        }

        let firstCheck = await coordinator.checkPendingSignIn()
        let secondCheck = await coordinator.checkPendingSignIn()
        XCTAssertFalse(firstCheck)
        XCTAssertTrue(secondCheck)
        let identity = try await task.value
        XCTAssertEqual(identity.identityHash, expectedIdentityHash)
        let methods = await fake.methods
        XCTAssertEqual(methods.filter { $0 == "account/read" }.count, 2)
        XCTAssertEqual(methods.last, "stop")
    }

    func testAuthenticationCoordinatorFailsWhenUpdatedAccountNeverBecomesReadable() async throws {
        let fake = FakeAppServerSession(
            events: [.accountUpdated(authMode: "chatgpt")],
            readFailuresBeforeSuccess: 100
        )
        var profile = fixtureProfile()
        profile.expectedIdentityHash = IdentityHasher.hashEmail("user@example.com")
        let coordinator = AuthenticationCoordinator(
            timeoutNanoseconds: 1_000_000_000,
            reconciliationTimeoutNanoseconds: 3_000_000,
            reconciliationRetryNanoseconds: 1_000_000,
            browserOpener: { _ in true },
            appProvider: { fixtureChatGPTApplication() },
            sessionFactory: { _, _ in fake }
        )

        do {
            _ = try await coordinator.signIn(profile: profile)
            XCTFail("Expected an unreadable account update to fail")
        } catch ProfileError.identityUnverified {
            // Expected.
        } catch {
            XCTFail("Expected identity-unverified failure, got \(error)")
        }
    }

    func testLinePumpDeliversShortJSONLResponseBeforePipeCloses() async throws {
        let pipe = Pipe()
        let router = AppServerMessageRouter()
        let pump = AppServerLinePump(
            handle: pipe.fileHandleForReading,
            onData: { data in
                Task { await router.receive(data) }
            },
            onEOF: {
                Task { await router.finish() }
            }
        )
        defer {
            pump.stop()
            pipe.fileHandleForWriting.closeFile()
            pipe.fileHandleForReading.closeFile()
        }

        pipe.fileHandleForWriting.write(Data("{\"id\":1,\"result\":{}}\n".utf8))
        let response = try await valueWithinOneSecond {
            try await router.waitForResponse(id: 1)
        }
        XCTAssertEqual(String(data: response, encoding: .utf8), "{\"id\":1,\"result\":{}}")
    }

    func testMessageRouterBuffersSplitLinesAndInterleavedNotifications() async throws {
        let router = AppServerMessageRouter()
        let message = "{\"method\":\"account/login/completed\",\"params\":{\"loginId\":\"fixture-login\",\"success\":true}}\n{\"method\":\"account/updated\",\"params\":{\"authMode\":\"chatgpt\"}}\n{\"id\":2,\"result\":{}}\n"
        let bytes = Array(message.utf8)
        await router.receive(Data(bytes.prefix(17)))
        await router.receive(Data(bytes.dropFirst(17)))

        let response = try await router.waitForResponse(id: 2)
        let completion = try await router.waitForNotification(method: "account/login/completed", loginID: "fixture-login")
        let accountUpdate = try await router.waitForNotification(method: "account/updated", loginID: nil)
        XCTAssertEqual(String(data: response, encoding: .utf8), "{\"id\":2,\"result\":{}}")
        XCTAssertTrue(String(data: completion, encoding: .utf8)?.contains("fixture-login") == true)
        XCTAssertTrue(String(data: accountUpdate, encoding: .utf8)?.contains("chatgpt") == true)
    }

    func testMessageRouterFailsClosedForMalformedAndOversizedData() async throws {
        let malformed = AppServerMessageRouter()
        await malformed.receive(Data("not-json\n".utf8))
        do {
            _ = try await malformed.waitForResponse(id: 1)
            XCTFail("Expected malformed JSONL to fail the router")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The authentication helper returned an invalid response.")
        }

        let oversized = AppServerMessageRouter()
        await oversized.receive(Data(repeating: 0x61, count: 1_048_577))
        do {
            _ = try await oversized.waitForResponse(id: 1)
            XCTFail("Expected oversized JSONL to fail the router")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The authentication helper returned an oversized response.")
        }

        let partial = AppServerMessageRouter()
        await partial.receive(Data("{\"id\":1".utf8))
        await partial.finish()
        do {
            _ = try await partial.waitForResponse(id: 1)
            XCTFail("Expected partial EOF to fail the router")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The authentication helper closed with an incomplete response.")
        }

        let mismatched = AppServerMessageRouter()
        await mismatched.receive(Data("{\"id\":2,\"result\":{}}\n".utf8))
        await mismatched.finish()
        do {
            _ = try await mismatched.waitForResponse(id: 1)
            XCTFail("Expected a mismatched response ID to remain unresolved")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The authentication helper closed before replying.")
        }
    }

    func testAppServerSessionSendsInitializedBeforeBrowserLogin() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let transcriptURL = root.appendingPathComponent("transcript.jsonl")
        let fixtureCommand = """
        while IFS= read -r line; do
          printf '%s\\n' "$line" >> "$APP_SERVER_FIXTURE_LOG"
          case "$line" in
            *'"method":"initialize"'*)
              printf '%s\\n' '{"id":1,"result":{}}'
              ;;
            *'"type":"chatgpt"'*)
              printf '%s\\n' '{"method":"account/login/completed","params":{"loginId":"fixture-login","success":true}}'
              printf '%s\\n' '{"id":2,"result":{"type":"chatgpt","loginId":"fixture-login","authUrl":"https://chatgpt.com/fixture"}}'
              ;;
          esac
        done
        """
        let session = try AppServerSession(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            codexHome: root.appendingPathComponent("codex-home", isDirectory: true),
            environment: ["APP_SERVER_FIXTURE_LOG": transcriptURL.path],
            arguments: ["-c", fixtureCommand]
        )

        let attempt = try await session.startChatGPTLogin()
        XCTAssertEqual(attempt.authURL.scheme, "https")
        XCTAssertEqual(attempt.authURL.host, "chatgpt.com")
        _ = try await session.waitForAuthenticationEvent(loginID: attempt.loginID)
        await session.stop()

        let transcript = try String(contentsOf: transcriptURL, encoding: .utf8)
        let initialized = transcript.range(of: "\"method\":\"initialized\"")
        let login = transcript.range(of: "\"type\":\"chatgpt\"")
        guard let initialized, let login else {
            return XCTFail("Fixture transcript did not contain the required handshake messages.")
        }
        XCTAssertLessThan(initialized.lowerBound, login.lowerBound)
        XCTAssertTrue(transcript.contains("\"useHostedLoginSuccessPage\":false"))
        XCTAssertFalse(transcript.contains("\"appBrand\""))
    }

    func testAppServerSessionParsesChatGPTAccountUpdatedEvent() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixtureCommand = """
        while IFS= read -r line; do
          case "$line" in
            *'"method":"initialize"'*)
              printf '%s\n' '{"id":1,"result":{}}'
              ;;
            *'"type":"chatgpt"'*)
              printf '%s\n' '{"id":2,"result":{"type":"chatgpt","loginId":"fixture-login","authUrl":"https://chatgpt.com/fixture"}}'
              printf '%s\n' '{"method":"account/updated","params":{"authMode":"chatgpt"}}'
              ;;
          esac
        done
        """
        let session = try AppServerSession(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            codexHome: root.appendingPathComponent("codex-home", isDirectory: true),
            environment: [:],
            arguments: ["-c", fixtureCommand]
        )

        let attempt = try await session.startChatGPTLogin()
        let event = try await session.waitForAuthenticationEvent(loginID: attempt.loginID)
        await session.stop()

        XCTAssertEqual(event, .accountUpdated(authMode: "chatgpt"))
    }

    func testNativeSnapshotExcludesDetachedCrashReportersWhenChatGPTIsRunning() throws {
        let provider = DarwinProcessSnapshotProvider()
        guard let snapshot = try provider.snapshot() else {
            throw XCTSkip("ChatGPT is not running in this environment")
        }
        XCTAssertFalse(snapshot.commandLines.contains { $0.contains("browser_crashpad_handler") })
        XCTAssertTrue(snapshot.accountBearingPIDs.contains(snapshot.mainPID))
    }

    func testDarwinProcessArgumentsSeparatesExecutableArgvAndEnvironment() throws {
        let executable = "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT"
        let userData = "--user-data-dir=/tmp/profile/electron-data"
        let cache = "--disk-cache-dir=/tmp/profile/electron-cache"
        let codexHome = "/tmp/profile/codex-home"
        let argv = [executable, userData, cache]
        var argc = Int32(argv.count)
        var bytes = withUnsafeBytes(of: &argc) { Array($0) }
        for token in [executable] + argv + ["CODEX_HOME=\(codexHome)", "PATH=/usr/bin"] {
            bytes.append(contentsOf: token.utf8)
            bytes.append(0)
        }

        let parsed = try XCTUnwrap(DarwinProcessArguments.parse(bytes))

        XCTAssertEqual(parsed.arguments, [userData, cache])
        XCTAssertEqual(parsed.codexHome, codexHome)
    }

    func testAdoptedSnapshotAcceptsOnlyVerifiedImplicitDefaultCache() {
        let adopted = CodexProfile(
            displayName: "Personal",
            codexHomePath: CodexSwitchPaths.defaultCodexHome.path,
            electronDataPath: CodexSwitchPaths.defaultElectronData.path,
            electronCachePath: CodexSwitchPaths.defaultElectronCache.path,
            storageKind: .adoptedDefault
        )
        let base = ChatGPTProcessSnapshot(
            mainPID: 42,
            accountBearingPIDs: [42],
            commandLines: [],
            userDataRoots: [adopted.electronDataURL.standardizedFileURL.path],
            cacheRoots: [],
            codexHomeRoots: [adopted.codexHomeURL.standardizedFileURL.path],
            mainArgumentsReadable: true,
            mainHasExplicitCacheOverride: false
        )

        XCTAssertEqual(base.cacheEvidence(for: adopted), .implicitAdoptedDefault)
        XCTAssertTrue(base.exposes(profile: adopted))

        let unreadable = ChatGPTProcessSnapshot(
            mainPID: base.mainPID,
            accountBearingPIDs: base.accountBearingPIDs,
            commandLines: base.commandLines,
            userDataRoots: base.userDataRoots,
            cacheRoots: base.cacheRoots,
            codexHomeRoots: base.codexHomeRoots,
            mainArgumentsReadable: false,
            mainHasExplicitCacheOverride: false
        )
        XCTAssertEqual(unreadable.cacheEvidence(for: adopted), .missing)
        XCTAssertFalse(unreadable.exposes(profile: adopted))

        var managed = adopted
        managed.storageKind = .managed
        XCTAssertEqual(base.cacheEvidence(for: managed), .missing)
        XCTAssertFalse(base.exposes(profile: managed))

        let conflicting = ChatGPTProcessSnapshot(
            mainPID: base.mainPID,
            accountBearingPIDs: base.accountBearingPIDs,
            commandLines: base.commandLines,
            userDataRoots: base.userDataRoots,
            cacheRoots: ["/tmp/conflicting-cache"],
            codexHomeRoots: base.codexHomeRoots,
            mainArgumentsReadable: true,
            mainHasExplicitCacheOverride: false
        )
        XCTAssertEqual(conflicting.cacheEvidence(for: adopted), .missing)
        XCTAssertFalse(conflicting.exposes(profile: adopted))
    }

    func testFailedTargetConfirmationRollsBackAndClearsJournal() async throws {
        let fixture = try makeSwitchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let process = FakeChatGPTProcessController(
            snapshot: fixtureProcessSnapshot(profile: fixture.source),
            failingLaunchProfileIDs: [fixture.target.id]
        )
        let transaction = SwitchTransaction(
            store: fixture.store,
            processController: process,
            verifier: FakeAccountVerifier(),
            probe: FakeCompatibilityProbe(managedRoot: fixture.root)
        )

        do {
            _ = try await transaction.switchTo(
                fixture.target.id,
                validation: fixtureValidationAuthorization(fixture)
            )
            XCTFail("Expected target confirmation to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("fixture launch confirmation failed"))
        }

        XCTAssertNil(try RecoveryJournal(url: fixture.store.journalURL).load())
        XCTAssertEqual(try fixture.store.load().lastCommittedProfileID, fixture.source.id)
        XCTAssertTrue(try XCTUnwrap(process.snapshot).exposes(profile: fixture.source))
    }

    func testProvisionalSwitchRequiresAcknowledgementBeforeMutation() async throws {
        let fixture = try makeSwitchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let app = fixtureChatGPTApplication()
        _ = try fixture.store.setCompatibility(CompatibilityRecord(
            appVersion: app.version,
            bundleIdentifier: app.bundleIdentifier,
            teamIdentifier: app.teamIdentifier
        ))
        let process = FakeChatGPTProcessController(snapshot: fixtureProcessSnapshot(profile: fixture.source))
        let transaction = SwitchTransaction(
            store: fixture.store,
            processController: process,
            verifier: FakeAccountVerifier(),
            probe: FakeCompatibilityProbe(managedRoot: fixture.root)
        )

        do {
            _ = try await transaction.switchTo(fixture.target.id)
            XCTFail("Expected provisional acknowledgement to be required")
        } catch let error as ProfileError {
            guard case .compatibilityAcknowledgementRequired = error else {
                return XCTFail("Expected compatibilityAcknowledgementRequired, got \(error)")
            }
        }

        XCTAssertEqual(process.events, ["inspect"])
        XCTAssertNil(try RecoveryJournal(url: fixture.store.journalURL).load())
        XCTAssertEqual(try fixture.store.load().lastCommittedProfileID, fixture.source.id)
    }

    func testGuidedDiagnosticsCannotBypassProvisionalAcknowledgement() async throws {
        let fixture = try makeSwitchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let app = fixtureChatGPTApplication()
        _ = try fixture.store.setCompatibility(CompatibilityRecord(
            appVersion: app.version,
            bundleIdentifier: app.bundleIdentifier,
            teamIdentifier: app.teamIdentifier
        ))
        let process = FakeChatGPTProcessController(snapshot: fixtureProcessSnapshot(profile: fixture.source))
        let transaction = SwitchTransaction(
            store: fixture.store,
            processController: process,
            verifier: FakeAccountVerifier(),
            probe: FakeCompatibilityProbe(managedRoot: fixture.root)
        )

        do {
            _ = try await transaction.switchTo(
                fixture.target.id,
                validation: fixtureValidationAuthorization(fixture)
            )
            XCTFail("Expected diagnostics not to bypass acknowledgement")
        } catch let error as ProfileError {
            guard case .compatibilityAcknowledgementRequired = error else {
                return XCTFail("Expected compatibilityAcknowledgementRequired, got \(error)")
            }
        }
        XCTAssertNil(try RecoveryJournal(url: fixture.store.journalURL).load())
    }

    func testAcknowledgedProvisionalSwitchCommitsNormally() async throws {
        let fixture = try makeSwitchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let app = fixtureChatGPTApplication()
        _ = try fixture.store.setCompatibility(CompatibilityRecord(
            appVersion: app.version,
            bundleIdentifier: app.bundleIdentifier,
            teamIdentifier: app.teamIdentifier,
            provisionalAcknowledgedAt: Date(timeIntervalSince1970: 123)
        ))
        let process = FakeChatGPTProcessController(snapshot: fixtureProcessSnapshot(profile: fixture.source))
        let transaction = SwitchTransaction(
            store: fixture.store,
            processController: process,
            verifier: FakeAccountVerifier(),
            probe: FakeCompatibilityProbe(managedRoot: fixture.root)
        )

        let outcome = try await transaction.switchTo(fixture.target.id)

        XCTAssertEqual(outcome, .committed)
        XCTAssertEqual(try fixture.store.load().lastCommittedProfileID, fixture.target.id)
        XCTAssertTrue(try XCTUnwrap(process.snapshot).exposes(profile: fixture.target))
        XCTAssertNil(try RecoveryJournal(url: fixture.store.journalURL).load())
    }

    func testBlockedCompatibilityRejectsSwitchWithoutMutation() async throws {
        let fixture = try makeSwitchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let app = fixtureChatGPTApplication()
        _ = try fixture.store.setCompatibility(CompatibilityRecord(
            appVersion: app.version,
            bundleIdentifier: app.bundleIdentifier,
            teamIdentifier: app.teamIdentifier,
            status: .blocked,
            summary: "fixture block"
        ))
        let process = FakeChatGPTProcessController(snapshot: fixtureProcessSnapshot(profile: fixture.source))
        let transaction = SwitchTransaction(
            store: fixture.store,
            processController: process,
            verifier: FakeAccountVerifier(),
            probe: FakeCompatibilityProbe(managedRoot: fixture.root)
        )

        do {
            _ = try await transaction.switchTo(fixture.target.id)
            XCTFail("Expected blocked compatibility to reject switching")
        } catch let error as ProfileError {
            guard case .compatibilityBlocked(let message) = error else {
                return XCTFail("Expected compatibilityBlocked, got \(error)")
            }
            XCTAssertEqual(message, "fixture block")
        }
        XCTAssertEqual(process.events, ["inspect"])
        XCTAssertNil(try RecoveryJournal(url: fixture.store.journalURL).load())
    }

    func testOpenLiveConversationRequiresHandoffConfirmationBeforeMutation() async throws {
        let fixture = try makeSwitchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let lockDirectory = fixture.source.codexHomeURL
            .appendingPathComponent("thread-writer-locks", isDirectory: true)
        try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
        let lockURL = lockDirectory.appendingPathComponent("private-fixture.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        guard descriptor >= 0 else { return }
        defer {
            _ = flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)

        let process = FakeChatGPTProcessController(snapshot: fixtureProcessSnapshot(profile: fixture.source))
        let transaction = SwitchTransaction(
            store: fixture.store,
            processController: process,
            verifier: FakeAccountVerifier(),
            probe: FakeCompatibilityProbe(managedRoot: fixture.root)
        )

        do {
            _ = try await transaction.switchTo(
                fixture.target.id,
                validation: fixtureValidationAuthorization(fixture)
            )
            XCTFail("Expected an open live conversation to require confirmation")
        } catch let error as ProfileError {
            guard case .liveSessionHandoffRequired = error else {
                return XCTFail("Expected liveSessionHandoffRequired, got \(error)")
            }
            XCTAssertFalse(error.localizedDescription.contains(lockURL.lastPathComponent))
        }

        XCTAssertEqual(process.events, ["inspect"])
        XCTAssertNil(try RecoveryJournal(url: fixture.store.journalURL).load())
        XCTAssertEqual(try fixture.store.load().lastCommittedProfileID, fixture.source.id)
    }

    func testConversationOpenedDuringPreflightRequiresConfirmationBeforeJournaling() async throws {
        let fixture = try makeSwitchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let lockDirectory = fixture.source.codexHomeURL
            .appendingPathComponent("thread-writer-locks", isDirectory: true)
        try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
        let lockURL = lockDirectory.appendingPathComponent("private-fixture.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        guard descriptor >= 0 else { return }
        defer {
            _ = flock(descriptor, LOCK_UN)
            close(descriptor)
        }

        let process = FakeChatGPTProcessController(snapshot: fixtureProcessSnapshot(profile: fixture.source))
        let transaction = SwitchTransaction(
            store: fixture.store,
            processController: process,
            verifier: CallbackAccountVerifier {
                _ = flock(descriptor, LOCK_EX | LOCK_NB)
            },
            probe: FakeCompatibilityProbe(managedRoot: fixture.root)
        )

        do {
            _ = try await transaction.switchTo(
                fixture.target.id,
                validation: fixtureValidationAuthorization(fixture)
            )
            XCTFail("Expected a newly opened conversation to require confirmation")
        } catch let error as ProfileError {
            guard case .liveSessionHandoffRequired = error else {
                return XCTFail("Expected liveSessionHandoffRequired, got \(error)")
            }
        }

        XCTAssertEqual(process.events, ["inspect"])
        XCTAssertNil(try RecoveryJournal(url: fixture.store.journalURL).load())
        XCTAssertEqual(try fixture.store.load().lastCommittedProfileID, fixture.source.id)
    }

    func testConfirmedLiveConversationHandoffCommitsAfterWriterReleases() async throws {
        let fixture = try makeSwitchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let lockDirectory = fixture.source.codexHomeURL
            .appendingPathComponent("thread-writer-locks", isDirectory: true)
        try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
        let lockURL = lockDirectory.appendingPathComponent("private-fixture.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        guard descriptor >= 0 else { return }
        defer {
            _ = flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)

        let process = FakeChatGPTProcessController(
            snapshot: fixtureProcessSnapshot(profile: fixture.source),
            onQuit: {
                _ = flock(descriptor, LOCK_UN)
            }
        )
        let transaction = SwitchTransaction(
            store: fixture.store,
            processController: process,
            verifier: FakeAccountVerifier(),
            probe: FakeCompatibilityProbe(managedRoot: fixture.root)
        )

        let outcome = try await transaction.switchTo(
            fixture.target.id,
            validation: fixtureValidationAuthorization(fixture),
            liveSessionHandoff: .confirmedGracefulQuit
        )

        XCTAssertEqual(outcome, .committed)
        XCTAssertEqual(process.events, ["inspect", "quit", "launch:\(fixture.target.id.uuidString)"])
        XCTAssertEqual(LiveWriterDetector().status(for: fixture.source), .absent)
        XCTAssertNil(try RecoveryJournal(url: fixture.store.journalURL).load())
        XCTAssertEqual(try fixture.store.load().lastCommittedProfileID, fixture.target.id)
    }

    func testConfirmedHandoffDoesNotLaunchTargetWhileAnotherWriterRemains() async throws {
        let fixture = try makeSwitchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let lockDirectory = fixture.source.codexHomeURL
            .appendingPathComponent("thread-writer-locks", isDirectory: true)
        try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
        let lockURL = lockDirectory.appendingPathComponent("private-fixture.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        guard descriptor >= 0 else { return }
        defer {
            _ = flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)

        let process = FakeChatGPTProcessController(snapshot: fixtureProcessSnapshot(profile: fixture.source))
        let transaction = SwitchTransaction(
            store: fixture.store,
            processController: process,
            verifier: FakeAccountVerifier(),
            probe: FakeCompatibilityProbe(managedRoot: fixture.root)
        )

        do {
            _ = try await transaction.switchTo(
                fixture.target.id,
                validation: fixtureValidationAuthorization(fixture),
                liveSessionHandoff: .confirmedGracefulQuit
            )
            XCTFail("Expected an unreleased live writer to prevent target launch")
        } catch let error as ProfileError {
            guard case .transactionFailed = error else {
                return XCTFail("Expected transactionFailed, got \(error)")
            }
        }

        XCTAssertEqual(
            process.events,
            ["inspect", "quit", "inspect", "launch:\(fixture.source.id.uuidString)"]
        )
        XCTAssertFalse(process.events.contains("launch:\(fixture.target.id.uuidString)"))
        XCTAssertNil(try RecoveryJournal(url: fixture.store.journalURL).load())
        XCTAssertEqual(try fixture.store.load().lastCommittedProfileID, fixture.source.id)
        XCTAssertTrue(try XCTUnwrap(process.snapshot).exposes(profile: fixture.source))
    }

    func testConfirmedHandoffQuitFailureKeepsCommittedSourceAndClearsJournal() async throws {
        let fixture = try makeSwitchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let lockDirectory = fixture.source.codexHomeURL
            .appendingPathComponent("thread-writer-locks", isDirectory: true)
        try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
        let lockURL = lockDirectory.appendingPathComponent("private-fixture.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        guard descriptor >= 0 else { return }
        defer {
            _ = flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)

        let process = FakeChatGPTProcessController(
            snapshot: fixtureProcessSnapshot(profile: fixture.source),
            quitError: .transactionFailed("fixture graceful quit timed out")
        )
        let transaction = SwitchTransaction(
            store: fixture.store,
            processController: process,
            verifier: FakeAccountVerifier(),
            probe: FakeCompatibilityProbe(managedRoot: fixture.root)
        )

        do {
            _ = try await transaction.switchTo(
                fixture.target.id,
                validation: fixtureValidationAuthorization(fixture),
                liveSessionHandoff: .confirmedGracefulQuit
            )
            XCTFail("Expected graceful quit failure")
        } catch let error as ProfileError {
            guard case .transactionFailed = error else {
                return XCTFail("Expected transactionFailed, got \(error)")
            }
        }

        XCTAssertEqual(process.events, ["inspect", "quit", "inspect"])
        XCTAssertFalse(process.events.contains("launch:\(fixture.target.id.uuidString)"))
        XCTAssertNil(try RecoveryJournal(url: fixture.store.journalURL).load())
        XCTAssertEqual(try fixture.store.load().lastCommittedProfileID, fixture.source.id)
        XCTAssertTrue(try XCTUnwrap(process.snapshot).exposes(profile: fixture.source))
    }

    func testRecoveryFailsClosedWhenSessionInspectionIsAmbiguous() async throws {
        let fixture = try makeSwitchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try RecoveryJournal(url: fixture.store.journalURL).save(SwitchJournal(
            sourceProfileID: fixture.source.id,
            targetProfileID: fixture.target.id,
            phase: .failed
        ))
        let process = FakeChatGPTProcessController(
            inspectionError: .transactionFailed("fixture session is ambiguous")
        )
        let transaction = SwitchTransaction(
            store: fixture.store,
            processController: process,
            verifier: FakeAccountVerifier(),
            probe: FakeCompatibilityProbe(managedRoot: fixture.root)
        )

        let result = await transaction.recoverIfNeeded()

        XCTAssertFalse(result.recovered)
        XCTAssertEqual(process.events, ["inspect"])
        XCTAssertNotNil(try RecoveryJournal(url: fixture.store.journalURL).load())
    }

    func testRecoveryAcceptsAlreadyRestoredSourceWithoutRelaunching() async throws {
        let fixture = try makeSwitchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try RecoveryJournal(url: fixture.store.journalURL).save(SwitchJournal(
            sourceProfileID: fixture.source.id,
            targetProfileID: fixture.target.id,
            phase: .failed
        ))
        let process = FakeChatGPTProcessController(snapshot: fixtureProcessSnapshot(profile: fixture.source))
        let transaction = SwitchTransaction(
            store: fixture.store,
            processController: process,
            verifier: FakeAccountVerifier(),
            probe: FakeCompatibilityProbe(managedRoot: fixture.root)
        )

        let result = await transaction.recoverIfNeeded()

        XCTAssertTrue(result.recovered)
        XCTAssertEqual(process.events, ["inspect"])
        XCTAssertNil(try RecoveryJournal(url: fixture.store.journalURL).load())
    }

    func testCancellationAfterTargetLaunchRollsBackFromUncancelledCleanup() async throws {
        let fixture = try makeSwitchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let process = FakeChatGPTProcessController(
            snapshot: fixtureProcessSnapshot(profile: fixture.source),
            cancellationLaunchProfileIDs: [fixture.target.id],
            rejectCancelledCleanup: true
        )
        let transaction = SwitchTransaction(
            store: fixture.store,
            processController: process,
            verifier: FakeAccountVerifier(),
            probe: FakeCompatibilityProbe(managedRoot: fixture.root)
        )
        let task = Task {
            try await transaction.switchTo(
                fixture.target.id,
                validation: fixtureValidationAuthorization(fixture)
            )
        }

        for _ in 0..<100 where !process.events.contains("launch:\(fixture.target.id.uuidString)") {
            try await Task.sleep(for: .milliseconds(5))
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected the switch task to report cancellation")
        } catch is CancellationError {
            // Expected after an independently completed rollback.
        }
        XCTAssertNil(try RecoveryJournal(url: fixture.store.journalURL).load())
        XCTAssertEqual(try fixture.store.load().lastCommittedProfileID, fixture.source.id)
        XCTAssertTrue(try XCTUnwrap(process.snapshot).exposes(profile: fixture.source))
    }

    func testSwitchRefusesToOverwritePendingRecoveryJournal() async throws {
        let fixture = try makeSwitchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let pending = SwitchJournal(
            sourceProfileID: fixture.target.id,
            targetProfileID: fixture.source.id,
            phase: .failed
        )
        try RecoveryJournal(url: fixture.store.journalURL).save(pending)
        let process = FakeChatGPTProcessController(snapshot: fixtureProcessSnapshot(profile: fixture.source))
        let transaction = SwitchTransaction(
            store: fixture.store,
            processController: process,
            verifier: FakeAccountVerifier(),
            probe: FakeCompatibilityProbe(managedRoot: fixture.root)
        )

        do {
            _ = try await transaction.switchTo(
                fixture.target.id,
                validation: fixtureValidationAuthorization(fixture)
            )
            XCTFail("Expected pending recovery to block switching")
        } catch let error as ProfileError {
            guard case .recoveryRequired = error else {
                return XCTFail("Expected recoveryRequired, got \(error)")
            }
        }

        let preserved = try XCTUnwrap(RecoveryJournal(url: fixture.store.journalURL).load())
        XCTAssertEqual(preserved.sourceProfileID, pending.sourceProfileID)
        XCTAssertEqual(preserved.targetProfileID, pending.targetProfileID)
        XCTAssertEqual(process.events, [])
    }

    func testSwitchRejectsValidationAuthorizationAfterInstallationChanges() async throws {
        let fixture = try makeSwitchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let process = FakeChatGPTProcessController(snapshot: fixtureProcessSnapshot(profile: fixture.source))
        let changedApp = ChatGPTApplication(
            bundleURL: fixtureChatGPTApplication().bundleURL,
            executableURL: fixtureChatGPTApplication().executableURL,
            codexExecutableURL: fixtureChatGPTApplication().codexExecutableURL,
            bundleIdentifier: fixtureChatGPTApplication().bundleIdentifier,
            version: "changed-version",
            teamIdentifier: fixtureChatGPTApplication().teamIdentifier
        )
        let transaction = SwitchTransaction(
            store: fixture.store,
            processController: process,
            verifier: FakeAccountVerifier(),
            probe: FakeCompatibilityProbe(managedRoot: fixture.root, application: changedApp)
        )

        do {
            _ = try await transaction.switchTo(
                fixture.target.id,
                validation: fixtureValidationAuthorization(fixture)
            )
            XCTFail("Expected stale validation authorization to be rejected")
        } catch let error as ProfileError {
            guard case .guidedValidationInvalidated = error else {
                return XCTFail("Expected guidedValidationInvalidated, got \(error)")
            }
        }

        XCTAssertNil(try RecoveryJournal(url: fixture.store.journalURL).load())
        XCTAssertFalse(process.events.contains(where: { $0.hasPrefix("launch:") || $0 == "quit" }))
    }

    func testSwitchToAlreadyActiveProfileReturnsUnchanged() async throws {
        let fixture = try makeSwitchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let process = FakeChatGPTProcessController(snapshot: fixtureProcessSnapshot(profile: fixture.source))
        let transaction = SwitchTransaction(
            store: fixture.store,
            processController: process,
            verifier: FakeAccountVerifier(),
            probe: FakeCompatibilityProbe(managedRoot: fixture.root)
        )

        let outcome = try await transaction.switchTo(fixture.source.id)

        XCTAssertEqual(outcome, .unchanged)
        XCTAssertEqual(process.events, ["inspect"])
        XCTAssertNil(try RecoveryJournal(url: fixture.store.journalURL).load())
    }

    func testGuidedValidationPreparationLaunchesMissingCommittedSource() async throws {
        let fixture = try makeSwitchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let process = FakeChatGPTProcessController()
        let transaction = SwitchTransaction(
            store: fixture.store,
            processController: process,
            verifier: FakeAccountVerifier(),
            probe: FakeCompatibilityProbe(managedRoot: fixture.root)
        )

        let authorization = try await transaction.prepareGuidedValidation(
            profileIDs: [fixture.source.id, fixture.target.id]
        )

        XCTAssertEqual(authorization.profileIDs, [fixture.source.id, fixture.target.id])
        XCTAssertEqual(process.events, ["inspect", "launch:\(fixture.source.id.uuidString)"])
        XCTAssertTrue(try XCTUnwrap(process.snapshot).exposes(profile: fixture.source))
        XCTAssertNil(try RecoveryJournal(url: fixture.store.journalURL).load())
    }

    func testGuidedValidationPreparationAcceptsExactCommittedSource() async throws {
        let fixture = try makeSwitchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let process = FakeChatGPTProcessController(snapshot: fixtureProcessSnapshot(profile: fixture.source))
        let transaction = SwitchTransaction(
            store: fixture.store,
            processController: process,
            verifier: FakeAccountVerifier(),
            probe: FakeCompatibilityProbe(managedRoot: fixture.root)
        )

        let authorization = try await transaction.prepareGuidedValidation(
            profileIDs: [fixture.source.id, fixture.target.id]
        )

        XCTAssertEqual(authorization.profileIDs, [fixture.source.id, fixture.target.id])
        XCTAssertEqual(process.events, ["inspect"])
        XCTAssertNil(try RecoveryJournal(url: fixture.store.journalURL).load())
    }

    func testGuidedValidationPreparationAllowsOpenLiveConversation() async throws {
        let fixture = try makeSwitchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let lockDirectory = fixture.source.codexHomeURL
            .appendingPathComponent("thread-writer-locks", isDirectory: true)
        try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
        let lockURL = lockDirectory.appendingPathComponent("private-fixture.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        guard descriptor >= 0 else { return }
        defer {
            _ = flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)

        let process = FakeChatGPTProcessController(snapshot: fixtureProcessSnapshot(profile: fixture.source))
        let transaction = SwitchTransaction(
            store: fixture.store,
            processController: process,
            verifier: FakeAccountVerifier(),
            probe: FakeCompatibilityProbe(managedRoot: fixture.root)
        )

        let authorization = try await transaction.prepareGuidedValidation(
            profileIDs: [fixture.source.id, fixture.target.id]
        )

        XCTAssertEqual(authorization.profileIDs, [fixture.source.id, fixture.target.id])
        XCTAssertEqual(process.events, ["inspect"])
        XCTAssertNil(try RecoveryJournal(url: fixture.store.journalURL).load())
    }

    func testGuidedSwitchRequiresCommittedSourceToRemainRunning() async throws {
        let fixture = try makeSwitchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let process = FakeChatGPTProcessController()
        let transaction = SwitchTransaction(
            store: fixture.store,
            processController: process,
            verifier: FakeAccountVerifier(),
            probe: FakeCompatibilityProbe(managedRoot: fixture.root)
        )

        do {
            _ = try await transaction.switchTo(
                fixture.target.id,
                validation: fixtureValidationAuthorization(fixture)
            )
            XCTFail("Expected missing guided-validation source to be rejected")
        } catch let error as ProfileError {
            guard case .guidedValidationInvalidated = error else {
                return XCTFail("Expected guidedValidationInvalidated, got \(error)")
            }
        }

        XCTAssertEqual(process.events, ["inspect"])
        XCTAssertNil(try RecoveryJournal(url: fixture.store.journalURL).load())
    }

    func testFinalGuidedValidationConfirmationRequiresLiveCommittedProfile() async throws {
        let fixture = try makeSwitchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let process = FakeChatGPTProcessController()
        let transaction = SwitchTransaction(
            store: fixture.store,
            processController: process,
            verifier: FakeAccountVerifier(),
            probe: FakeCompatibilityProbe(managedRoot: fixture.root)
        )

        do {
            try await transaction.confirmActive(validation: fixtureValidationAuthorization(fixture))
            XCTFail("Expected final confirmation to reject a missing process")
        } catch let error as ProfileError {
            guard case .guidedValidationInvalidated = error else {
                return XCTFail("Expected guidedValidationInvalidated, got \(error)")
            }
        }
        XCTAssertEqual(process.events, ["inspect"])
    }

    func testFinalGuidedValidationConfirmationAcceptsExactCommittedProfile() async throws {
        let fixture = try makeSwitchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let process = FakeChatGPTProcessController(snapshot: fixtureProcessSnapshot(profile: fixture.source))
        let transaction = SwitchTransaction(
            store: fixture.store,
            processController: process,
            verifier: FakeAccountVerifier(),
            probe: FakeCompatibilityProbe(managedRoot: fixture.root)
        )

        try await transaction.confirmActive(validation: fixtureValidationAuthorization(fixture))

        XCTAssertEqual(process.events, ["inspect"])
    }

    func testAdoptedProfilePathsCannotBeChanged() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(root: root)
        let document = try store.ensureAdoptedDefaultProfile()
        var invalid = document.profiles[0]
        invalid.codexHomePath = root.appendingPathComponent("not-codex").path
        XCTAssertThrowsError(try store.update(invalid))
    }

    func testIntermediateManagedSymlinkIsRejected() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let profiles = root.appendingPathComponent("Profiles", isDirectory: true)
        try FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true)
        let real = root.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = profiles.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let profile = CodexProfile(
            displayName: "Fixture",
            codexHomePath: link.appendingPathComponent("codex-home").path,
            electronDataPath: link.appendingPathComponent("electron-data").path,
            electronCachePath: link.appendingPathComponent("electron-cache").path,
            storageKind: .managed
        )
        XCTAssertThrowsError(try ProfileStore(root: root).validate(profile))
    }
}

private func fixtureChatGPTApplication() -> ChatGPTApplication {
    ChatGPTApplication(
        bundleURL: URL(fileURLWithPath: "/Applications/ChatGPT.app"),
        executableURL: URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT"),
        codexExecutableURL: URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
        bundleIdentifier: "com.openai.codex",
        version: "fixture",
        teamIdentifier: "fixture-team"
    )
}

private func fixtureProfile() -> CodexProfile {
    CodexProfile(
        displayName: "Fixture",
        codexHomePath: "/tmp/codex-home",
        electronDataPath: "/tmp/electron-data",
        electronCachePath: "/tmp/electron-cache",
        storageKind: .managed
    )
}

private struct SwitchFixture {
    let root: URL
    let store: ProfileStore
    let source: CodexProfile
    let target: CodexProfile
}

private func makeSwitchFixture() throws -> SwitchFixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("CodexSwitchTransactionTests-\(UUID().uuidString)", isDirectory: true)
    let store = ProfileStore(root: root)
    var source = try store.createManagedProfile(named: "Fixture A").1
    var target = try store.createManagedProfile(named: "Fixture B").1
    source.expectedIdentityHash = "fixture-a"
    target.expectedIdentityHash = "fixture-b"
    _ = try store.update(source)
    _ = try store.update(target)
    _ = try store.setActive(source.id, committed: true)
    let application = fixtureChatGPTApplication()
    _ = try store.setCompatibility(CompatibilityRecord(
        appVersion: application.version,
        bundleIdentifier: application.bundleIdentifier,
        teamIdentifier: application.teamIdentifier,
        status: .verified
    ))
    return SwitchFixture(root: root, store: store, source: source, target: target)
}

private func fixtureValidationAuthorization(_ fixture: SwitchFixture) -> GuidedValidationAuthorization {
    GuidedValidationAuthorization(
        app: fixtureChatGPTApplication(),
        profileIDs: [fixture.source.id, fixture.target.id]
    )!
}

private func fixtureProcessSnapshot(profile: CodexProfile) -> ChatGPTProcessSnapshot {
    ChatGPTProcessSnapshot(
        mainPID: 42,
        accountBearingPIDs: [42],
        commandLines: [],
        userDataRoots: [profile.electronDataURL.standardizedFileURL.path],
        cacheRoots: [profile.electronCacheURL.standardizedFileURL.path],
        codexHomeRoots: [profile.codexHomeURL.standardizedFileURL.path],
        mainArgumentsReadable: true,
        mainHasExplicitCacheOverride: true
    )
}

private struct FakeAccountVerifier: AccountVerifying {
    func verify(_ profile: CodexProfile) async throws -> AccountIdentity {
        guard let identityHash = profile.expectedIdentityHash else {
            throw ProfileError.identityUnverified
        }
        return AccountIdentity(email: "fixture@example.invalid", identityHash: identityHash)
    }
}

private struct CallbackAccountVerifier: AccountVerifying {
    let callback: @Sendable () -> Void

    func verify(_ profile: CodexProfile) async throws -> AccountIdentity {
        guard let identityHash = profile.expectedIdentityHash else {
            throw ProfileError.identityUnverified
        }
        callback()
        return AccountIdentity(email: "fixture@example.invalid", identityHash: identityHash)
    }
}

private struct FakeCompatibilityProbe: CompatibilityProbing {
    let managedRoot: URL
    let application: ChatGPTApplication

    init(
        managedRoot: URL,
        application: ChatGPTApplication = fixtureChatGPTApplication()
    ) {
        self.managedRoot = managedRoot
        self.application = application
    }

    func app() throws -> ChatGPTApplication {
        application
    }

    func check(profile: CodexProfile) throws -> CompatibilityReport {
        guard [profile.codexHomeURL, profile.electronDataURL, profile.electronCacheURL].allSatisfy({
            SecureFileSystem.isPath($0, inside: managedRoot)
        }) else {
            throw ProfileError.invalidPath(profile.codexHomePath)
        }
        return CompatibilityReport(
            passed: true,
            appVersion: "fixture",
            checkedPaths: [],
            message: "fixture"
        )
    }
}

private final class FakeChatGPTProcessController: ChatGPTProcessControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var storedSnapshot: ChatGPTProcessSnapshot?
    private let inspectionError: ProfileError?
    private let failingLaunchProfileIDs: Set<UUID>
    private let cancellationLaunchProfileIDs: Set<UUID>
    private let rejectCancelledCleanup: Bool
    private let quitError: ProfileError?
    private let onQuit: (@Sendable () -> Void)?
    private var storedEvents: [String] = []

    init(
        snapshot: ChatGPTProcessSnapshot? = nil,
        inspectionError: ProfileError? = nil,
        failingLaunchProfileIDs: Set<UUID> = [],
        cancellationLaunchProfileIDs: Set<UUID> = [],
        rejectCancelledCleanup: Bool = false,
        quitError: ProfileError? = nil,
        onQuit: (@Sendable () -> Void)? = nil
    ) {
        self.storedSnapshot = snapshot
        self.inspectionError = inspectionError
        self.failingLaunchProfileIDs = failingLaunchProfileIDs
        self.cancellationLaunchProfileIDs = cancellationLaunchProfileIDs
        self.rejectCancelledCleanup = rejectCancelledCleanup
        self.quitError = quitError
        self.onQuit = onQuit
    }

    var snapshot: ChatGPTProcessSnapshot? {
        lock.withLock { storedSnapshot }
    }

    var events: [String] {
        lock.withLock { storedEvents }
    }

    func inspectSession() throws -> ChatGPTProcessSnapshot? {
        let (snapshot, error) = lock.withLock {
            storedEvents.append("inspect")
            return (storedSnapshot, inspectionError)
        }
        if let error { throw error }
        return snapshot
    }

    func quitGracefully() async throws {
        if rejectCancelledCleanup, Task.isCancelled {
            throw CancellationError()
        }
        let quitError = lock.withLock {
            storedEvents.append("quit")
            if self.quitError == nil {
                storedSnapshot = nil
            }
            return self.quitError
        }
        if let quitError { throw quitError }
        onQuit?()
    }

    func launchAndConfirm(profile: CodexProfile) async throws {
        let (shouldFail, shouldAwaitCancellation) = lock.withLock {
            storedEvents.append("launch:\(profile.id.uuidString)")
            storedSnapshot = fixtureProcessSnapshot(profile: profile)
            return (
                failingLaunchProfileIDs.contains(profile.id),
                cancellationLaunchProfileIDs.contains(profile.id)
            )
        }
        if shouldAwaitCancellation {
            while !Task.isCancelled {
                try await Task.sleep(for: .milliseconds(5))
            }
            throw CancellationError()
        }
        if rejectCancelledCleanup, Task.isCancelled {
            throw CancellationError()
        }
        if shouldFail {
            throw ProfileError.transactionFailed("fixture launch confirmation failed")
        }
    }
}

private enum TestTimeout: Error {
    case elapsed
}

private func valueWithinOneSecond<T: Sendable>(
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            throw TestTimeout.elapsed
        }
        defer { group.cancelAll() }
        guard let value = try await group.next() else {
            throw TestTimeout.elapsed
        }
        return value
    }
}

private final class LockedURL: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var value: URL?

    func set(_ value: URL) {
        lock.lock()
        self.value = value
        lock.unlock()
    }
}

private final class LockedCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private final class LockedStrings: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

private actor FakeAppServerSession: AppServerSessionProtocol {
    private let authURL: URL
    private var events: [AuthenticationEvent]?
    private var readFailuresRemaining: Int
    private let identity: AccountIdentity
    private(set) var methods: [String] = []

    init(
        authURL: URL = URL(string: "https://chatgpt.com/fixture-login")!,
        events: [AuthenticationEvent]? = [.loginCompleted(loginID: "fixture-login", success: true)],
        readFailuresBeforeSuccess: Int = 0,
        identity: AccountIdentity = AccountIdentity(
            email: "user@example.com",
            planType: "plus",
            identityHash: IdentityHasher.hashEmail("user@example.com")
        )
    ) {
        self.authURL = authURL
        self.events = events
        self.readFailuresRemaining = readFailuresBeforeSuccess
        self.identity = identity
    }

    func initialize() async throws {}

    func startChatGPTLogin() async throws -> LoginAttempt {
        methods.append("account/login/start")
        return LoginAttempt(loginID: "fixture-login", authURL: authURL)
    }

    func waitForAuthenticationEvent(loginID: String) async throws -> AuthenticationEvent {
        if var events, !events.isEmpty {
            let event = events.removeFirst()
            self.events = events
            return event
        }
        try await Task.sleep(nanoseconds: 60_000_000_000)
        return .loginCompleted(loginID: loginID, success: true)
    }

    func cancelLogin(loginID: String) async throws {
        methods.append("account/login/cancel")
    }

    func readAccount(refreshToken: Bool) async throws -> AccountIdentity {
        methods.append("account/read")
        if readFailuresRemaining > 0 {
            readFailuresRemaining -= 1
            throw ProfileError.identityUnverified
        }
        return identity
    }

    func stop() async {
        methods.append("stop")
    }
}
