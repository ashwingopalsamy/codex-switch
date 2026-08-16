import CodexSwitchCore
import Foundation

enum ProbeFailure: Error {
    case usage
}

func fixtureProbe() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("CodexSwitchProbe-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = ProfileStore(root: root)
    let document = try store.ensureAdoptedDefaultProfile(named: "Fixture A")
    let managedResult = try store.createManagedProfile(named: "Fixture B")
    let profileA = document.profiles[0]
    let profileB = managedResult.1
    let context = LaunchContext(profile: profileB, inheritedEnvironment: ["PATH": "/usr/bin"])

    precondition(context.environment["CODEX_HOME"] == profileB.codexHomePath)
    precondition(context.arguments.contains("--user-data-dir=\(profileB.electronDataPath)"))
    precondition(context.arguments.contains("--disk-cache-dir=\(profileB.electronCachePath)"))
    precondition(profileA.storageKind == .adoptedDefault)
    precondition(profileB.storageKind == .managed)

    let child = Process()
    child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    child.arguments = ["fixture-child"] + context.arguments
    child.environment = context.environment
    child.standardOutput = Pipe()
    child.standardError = Pipe()
    try child.run()
    Thread.sleep(forTimeInterval: 0.2)

    precondition(DarwinProcessSnapshotProvider().process(child.processIdentifier, exposes: profileB))
    precondition(FileManager.default.fileExists(atPath: profileB.codexHomeURL.appendingPathComponent("fixture-canary").path))
    precondition(FileManager.default.fileExists(atPath: profileB.electronDataURL.appendingPathComponent("fixture-canary").path))
    precondition(FileManager.default.fileExists(atPath: profileB.electronCacheURL.appendingPathComponent("fixture-canary").path))
    child.terminate()
    child.waitUntilExit()
    print("PASS fixture profile persistence and launch isolation")
}

func fixtureChild() throws {
    guard let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"] else {
        throw ProbeFailure.usage
    }
    let dataArgument = CommandLine.arguments.first(where: { $0.hasPrefix("--user-data-dir=") })
    let cacheArgument = CommandLine.arguments.first(where: { $0.hasPrefix("--disk-cache-dir=") })
    guard let dataPath = dataArgument?.dropFirst("--user-data-dir=".count),
          let cachePath = cacheArgument?.dropFirst("--disk-cache-dir=".count) else {
        throw ProbeFailure.usage
    }
    for root in [
        URL(fileURLWithPath: codexHome, isDirectory: true),
        URL(fileURLWithPath: String(dataPath), isDirectory: true),
        URL(fileURLWithPath: String(cachePath), isDirectory: true)
    ] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: root.appendingPathComponent("fixture-canary"))
    }
    RunLoop.current.run(until: Date().addingTimeInterval(30))
}

func appProbe() throws {
    let app = try ChatGPTLocator().locate()
    print("ChatGPT bundle: \(app.bundleIdentifier)")
    print("ChatGPT version: \(app.version)")
    print("ChatGPT team signature: \(app.teamIdentifier)")
    print("Structural app check: PASS")
    print("Runtime root isolation: PROVISIONAL UNTIL OPTIONAL GUIDED DIAGNOSTICS")
}

func processProbe() throws {
    let provider = DarwinProcessSnapshotProvider()
    guard let snapshot = try provider.snapshot() else {
        print("ChatGPT process: not running")
        return
    }
    print("ChatGPT process: running")
    print("Main process captured: PASS")
    print("Account-bearing helpers: \(snapshot.accountBearingPIDs.count)")
    print("Profile roots exposed: user-data=\(!snapshot.userDataRoots.isEmpty), cache-explicit=\(!snapshot.cacheRoots.isEmpty), codex-home=\(!snapshot.codexHomeRoots.isEmpty)")
    let knownProfiles = (try? ProfileStore().load().profiles) ?? []
    let matchingProfiles = knownProfiles.filter { snapshot.exposes(profile: $0) }
    print("Known profile root mapping: exact=\(matchingProfiles.count == 1)")
    if let matchingProfile = matchingProfiles.count == 1 ? matchingProfiles[0] : nil {
        print("Mapped profile storage: \(matchingProfile.storageKind.rawValue)")
        print("Mapped cache evidence: \(snapshot.cacheEvidence(for: matchingProfile).rawValue)")
    }
}

func statusProbe() throws {
    let store = ProfileStore()
    let document = try store.load()
    let activeID = document.lastCommittedProfileID ?? document.activeProfileID
    let activeProfile = activeID.flatMap { id in document.profiles.first(where: { $0.id == id }) }
    let compatibility = try store.compatibility(for: ChatGPTLocator().locate())
    let recoveryPending = try RecoveryJournal(url: store.journalURL).load() != nil
    print("Profiles configured: \(document.profiles.count)")
    print("Profiles identity-bound: \(document.profiles.filter { $0.expectedIdentityHash != nil }.count)")
    print("Active profile storage: \(activeProfile?.storageKind.rawValue ?? "none")")
    print("Compatibility status: \(compatibility.status.rawValue)")
    print("Provisional acknowledged: \(compatibility.provisionalAcknowledgedAt != nil)")
    print("Recovery pending: \(recoveryPending)")
    if let activeProfile {
        if LiveWriterDetector().status(for: activeProfile) == .present {
            print("Active profile live conversation: true")
        } else {
            print("Active profile live conversation: false")
        }
    }
}

func continuityProbe(samples: Int) throws {
    guard samples >= 1, samples <= 100 else { throw ProbeFailure.usage }
    let store = ProfileStore()
    let provider = DarwinProcessSnapshotProvider()
    let document = try store.load()
    guard let committedID = document.lastCommittedProfileID ?? document.activeProfileID,
          let committed = document.profiles.first(where: { $0.id == committedID }) else {
        throw ProfileError.missingProfile
    }

    var initialPID: Int32?
    var cacheEvidence: CacheRootEvidence = .missing
    for _ in 0..<samples {
        guard let snapshot = try provider.snapshot() else {
            throw ProfileError.guidedValidationInvalidated("The committed ChatGPT source disappeared during continuity sampling.")
        }
        let matchingProfiles = document.profiles.filter { snapshot.exposes(profile: $0) }
        guard matchingProfiles.count == 1, matchingProfiles[0].id == committed.id else {
            throw ProfileError.guidedValidationInvalidated("The live ChatGPT source diverged from the committed profile during continuity sampling.")
        }
        if let initialPID, snapshot.mainPID != initialPID {
            throw ProfileError.guidedValidationInvalidated("ChatGPT restarted during continuity sampling.")
        }
        initialPID = snapshot.mainPID
        cacheEvidence = snapshot.cacheEvidence(for: committed)
    }

    print("PASS committed-source continuity across \(samples) samples")
    print("Continuity profile storage: \(committed.storageKind.rawValue)")
    print("Continuity cache evidence: \(cacheEvidence.rawValue)")
}

func soakProbe(duration: TimeInterval) throws {
    guard duration >= 1, duration <= 600 else { throw ProbeFailure.usage }
    let store = ProfileStore()
    let provider = DarwinProcessSnapshotProvider()
    let document = try store.load()
    guard let initial = try provider.snapshot() else {
        throw ProfileError.transactionFailed("ChatGPT is not running.")
    }
    let matchingProfiles = document.profiles.filter { initial.exposes(profile: $0) }
    guard matchingProfiles.count == 1 else {
        throw ProfileError.transactionFailed("The running ChatGPT session does not map to exactly one profile.")
    }
    let profile = matchingProfiles[0]
    let deadline = Date().addingTimeInterval(duration)
    while Date() < deadline {
        Thread.sleep(forTimeInterval: 1)
        guard try RecoveryJournal(url: store.journalURL).load() == nil else {
            throw ProfileError.recoveryRequired("A recovery journal appeared during the stability soak.")
        }
        guard let snapshot = try provider.snapshot(),
              snapshot.mainPID == initial.mainPID,
              snapshot.exposes(profile: profile) else {
            throw ProfileError.transactionFailed(
                "ChatGPT exited, restarted, or stopped exposing the committed profile during the stability soak."
            )
        }
    }
    print("PASS stable mapped ChatGPT process for \(Int(duration)) seconds")
    print("Soaked profile storage: \(profile.storageKind.rawValue)")
}

func authenticationProbe() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("CodexSwitchAuthProbe-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let codexHome = root.appendingPathComponent("codex-home", isDirectory: true)
    try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)

    let app = try ChatGPTLocator().locate()
    let session = try AppServerSession(executableURL: app.codexExecutableURL, codexHome: codexHome)
    do {
        let attempt = try await session.startChatGPTLogin()
        guard attempt.authURL.scheme?.lowercased() == "https",
              let host = attempt.authURL.host?.lowercased(),
              host == "chatgpt.com" || host.hasSuffix(".chatgpt.com") || host == "openai.com" || host.hasSuffix(".openai.com") else {
            throw ProfileError.transactionFailed("The app-server returned an invalid browser sign-in URL.")
        }
        try? await session.cancelLogin(loginID: attempt.loginID)
        await session.stop()
        print("PASS app-server browser handshake (URL redacted)")
    } catch {
        await session.stop()
        throw error
    }
}

private final class AuthenticationProbeResult: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Void, Error>?

    func store(_ result: Result<Void, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func get() throws {
        lock.lock()
        let result = result
        lock.unlock()
        guard let result else {
            throw ProbeFailure.usage
        }
        try result.get()
    }
}

func runAuthenticationProbe() throws {
    let semaphore = DispatchSemaphore(value: 0)
    let result = AuthenticationProbeResult()
    Task {
        do {
            try await authenticationProbe()
            result.store(.success(()))
        } catch {
            result.store(.failure(error))
        }
        semaphore.signal()
    }
    semaphore.wait()
    try result.get()
}

do {
    let command = CommandLine.arguments.dropFirst().first ?? "fixture"
    switch command {
    case "fixture":
        try fixtureProbe()
    case "fixture-child":
        try fixtureChild()
    case "app":
        try appProbe()
    case "process":
        try processProbe()
    case "status":
        try statusProbe()
    case "continuity":
        let samples = CommandLine.arguments.dropFirst(2).first.flatMap(Int.init) ?? 10
        try continuityProbe(samples: samples)
    case "soak":
        let duration = CommandLine.arguments.dropFirst(2).first.flatMap(TimeInterval.init) ?? 120
        try soakProbe(duration: duration)
    case "auth":
        try runAuthenticationProbe()
    default:
        throw ProbeFailure.usage
    }
} catch {
    fputs("CodexSwitchProbe failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
