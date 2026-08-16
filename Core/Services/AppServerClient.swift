import Foundation

public protocol AppServerSessionProtocol: Sendable {
    func initialize() async throws
    func startChatGPTLogin() async throws -> LoginAttempt
    func waitForAuthenticationEvent(loginID: String) async throws -> AuthenticationEvent
    func cancelLogin(loginID: String) async throws
    func readAccount(refreshToken: Bool) async throws -> AccountIdentity
    func stop() async
}

private enum AppServerTransportFailure: LocalizedError, Sendable {
    case closed
    case incompleteMessage
    case malformedMessage
    case messageTooLarge

    var errorDescription: String? {
        switch self {
        case .closed:
            return "The authentication helper closed before replying."
        case .incompleteMessage:
            return "The authentication helper closed with an incomplete response."
        case .malformedMessage:
            return "The authentication helper returned an invalid response."
        case .messageTooLarge:
            return "The authentication helper returned an oversized response."
        }
    }
}

private struct AppServerNotificationKey: Hashable, Sendable {
    let method: String
    let loginID: String?
}

/// A single owner for the app-server stdout stream. Keeping parsing and waiting
/// here prevents concurrent requests from consuming one another's JSONL lines.
actor AppServerMessageRouter {
    private static let maximumBufferedBytes = 1_048_576
    private static let maximumQueuedMessages = 64

    private var buffer = Data()
    private var cachedResponses: [Int: Data] = [:]
    private var responseWaiters: [Int: CheckedContinuation<Data, Error>] = [:]
    private var cachedNotifications: [AppServerNotificationKey: [Data]] = [:]
    private var notificationWaiters: [AppServerNotificationKey: [CheckedContinuation<Data, Error>]] = [:]
    private var terminalFailure: AppServerTransportFailure?

    func receive(_ chunk: Data) {
        guard terminalFailure == nil else { return }
        buffer.append(chunk)
        guard buffer.count <= Self.maximumBufferedBytes else {
            finish(with: .messageTooLarge)
            return
        }

        while let newline = buffer.firstIndex(of: 0x0A) {
            var line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if line.last == 0x0D {
                line.removeLast()
            }
            guard !line.isEmpty else { continue }
            route(line)
            guard terminalFailure == nil else { return }
        }
    }

    func finish() {
        finish(with: buffer.isEmpty ? .closed : .incompleteMessage)
    }

    func waitForResponse(id: Int) async throws -> Data {
        if let response = cachedResponses.removeValue(forKey: id) {
            return response
        }
        if let terminalFailure {
            throw terminalFailure
        }

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                if let response = cachedResponses.removeValue(forKey: id) {
                    continuation.resume(returning: response)
                } else if let terminalFailure {
                    continuation.resume(throwing: terminalFailure)
                } else {
                    responseWaiters[id] = continuation
                }
            }
        }, onCancel: {
            Task { await self.cancelResponseWaiter(id: id) }
        })
    }

    func waitForNotification(method: String, loginID: String?) async throws -> Data {
        let key = AppServerNotificationKey(method: method, loginID: loginID)
        if var notifications = cachedNotifications[key], !notifications.isEmpty {
            let notification = notifications.removeFirst()
            if notifications.isEmpty {
                cachedNotifications.removeValue(forKey: key)
            } else {
                cachedNotifications[key] = notifications
            }
            return notification
        }
        if let terminalFailure {
            throw terminalFailure
        }

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                if var notifications = cachedNotifications[key], !notifications.isEmpty {
                    let notification = notifications.removeFirst()
                    if notifications.isEmpty {
                        cachedNotifications.removeValue(forKey: key)
                    } else {
                        cachedNotifications[key] = notifications
                    }
                    continuation.resume(returning: notification)
                } else if let terminalFailure {
                    continuation.resume(throwing: terminalFailure)
                } else {
                    notificationWaiters[key, default: []].append(continuation)
                }
            }
        }, onCancel: {
            Task { await self.cancelNotificationWaiter(for: key) }
        })
    }

    private func route(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            finish(with: .malformedMessage)
            return
        }

        if let identifier = object["id"] as? NSNumber {
            deliverResponse(line, id: identifier.intValue)
            return
        }

        guard let method = object["method"] as? String else {
            finish(with: .malformedMessage)
            return
        }
        let params = object["params"] as? [String: Any]
        let loginID = params?["loginId"] as? String
        deliverNotification(line, key: AppServerNotificationKey(method: method, loginID: loginID))
    }

    private func deliverResponse(_ response: Data, id: Int) {
        if let waiter = responseWaiters.removeValue(forKey: id) {
            waiter.resume(returning: response)
            return
        }
        guard cachedResponses.count < Self.maximumQueuedMessages else {
            finish(with: .messageTooLarge)
            return
        }
        cachedResponses[id] = response
    }

    private func deliverNotification(_ notification: Data, key: AppServerNotificationKey) {
        if var waiters = notificationWaiters[key], !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            if waiters.isEmpty {
                notificationWaiters.removeValue(forKey: key)
            } else {
                notificationWaiters[key] = waiters
            }
            waiter.resume(returning: notification)
            return
        }

        let queuedCount = cachedNotifications.values.reduce(0) { $0 + $1.count }
        guard queuedCount < Self.maximumQueuedMessages else {
            finish(with: .messageTooLarge)
            return
        }
        cachedNotifications[key, default: []].append(notification)
    }

    private func cancelResponseWaiter(id: Int) {
        responseWaiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    private func cancelNotificationWaiter(for key: AppServerNotificationKey) {
        guard var waiters = notificationWaiters[key], !waiters.isEmpty else { return }
        let waiter = waiters.removeLast()
        if waiters.isEmpty {
            notificationWaiters.removeValue(forKey: key)
        } else {
            notificationWaiters[key] = waiters
        }
        waiter.resume(throwing: CancellationError())
    }

    private func finish(with failure: AppServerTransportFailure) {
        guard terminalFailure == nil else { return }
        terminalFailure = failure
        buffer.removeAll(keepingCapacity: false)
        cachedResponses.removeAll(keepingCapacity: false)
        cachedNotifications.removeAll(keepingCapacity: false)

        let responses = responseWaiters.values
        responseWaiters.removeAll(keepingCapacity: false)
        responses.forEach { $0.resume(throwing: failure) }

        let notifications = notificationWaiters.values.flatMap { $0 }
        notificationWaiters.removeAll(keepingCapacity: false)
        notifications.forEach { $0.resume(throwing: failure) }
    }
}

/// Uses `availableData` only after the file descriptor is marked readable. A
/// blocking `read(upToCount:)` here waits for a full buffer or EOF and can hide
/// short JSONL responses until the app-server exits.
final class AppServerLinePump: @unchecked Sendable {
    private let handle: FileHandle

    init(
        handle: FileHandle,
        onData: @escaping @Sendable (Data) -> Void,
        onEOF: @escaping @Sendable () -> Void
    ) {
        self.handle = handle
        handle.readabilityHandler = { readableHandle in
            let chunk = readableHandle.availableData
            if chunk.isEmpty {
                readableHandle.readabilityHandler = nil
                onEOF()
            } else {
                onData(chunk)
            }
        }
    }

    func stop() {
        handle.readabilityHandler = nil
    }
}

private final class AppServerStderrDrain: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var didReceiveOutput = false

    init(handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [weak self] readableHandle in
            let chunk = readableHandle.availableData
            if chunk.isEmpty {
                readableHandle.readabilityHandler = nil
                return
            }
            self?.record(chunk)
        }
    }

    var hasOutput: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didReceiveOutput
    }

    func stop() {
        handle.readabilityHandler = nil
    }

    private func record(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        didReceiveOutput = true
        lock.unlock()
    }
}

public actor AppServerSession: AppServerSessionProtocol {
    private static let requestTimeoutNanoseconds: UInt64 = 15_000_000_000

    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private let router: AppServerMessageRouter
    private let stdoutPump: AppServerLinePump
    private let stderrPump: AppServerStderrDrain
    private var nextID = 1
    private var initialized = false
    private var stopped = false

    public init(
        executableURL: URL,
        codexHome: URL,
        environment: [String: String] = LaunchEnvironment.sanitized()
    ) throws {
        try self.init(
            executableURL: executableURL,
            codexHome: codexHome,
            environment: environment,
            arguments: ["app-server", "--listen", "stdio://"]
        )
    }

    init(
        executableURL: URL,
        codexHome: URL,
        environment: [String: String],
        arguments: [String]
    ) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        var processEnvironment = environment
        processEnvironment["CODEX_HOME"] = codexHome.path
        process.environment = processEnvironment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        let input = stdin.fileHandleForWriting
        let output = stdout.fileHandleForReading
        let router = AppServerMessageRouter()
        let stderrPump = AppServerStderrDrain(handle: stderr.fileHandleForReading)
        let stdoutPump = AppServerLinePump(
            handle: output,
            onData: { data in
                Task { await router.receive(data) }
            },
            onEOF: {
                Task { await router.finish() }
            }
        )

        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { process in
            SwitchLogger.authenticationHelperExited(
                status: process.terminationStatus,
                wroteToStderr: stderrPump.hasOutput
            )
            Task { await router.finish() }
        }

        self.process = process
        self.input = input
        self.output = output
        self.router = router
        self.stdoutPump = stdoutPump
        self.stderrPump = stderrPump

        do {
            try process.run()
        } catch {
            stdoutPump.stop()
            stderrPump.stop()
            input.closeFile()
            output.closeFile()
            throw error
        }
    }

    public func initialize() async throws {
        guard !initialized else { return }
        _ = try await sendRequest(method: "initialize", params: [
            "clientInfo": [
                "name": "codex-switch",
                "title": "CodexSwitch",
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
            ],
            "capabilities": ["experimentalApi": false]
        ])
        try sendNotification(method: "initialized", params: [:])
        initialized = true
    }

    public func startChatGPTLogin() async throws -> LoginAttempt {
        try await initialize()
        let response = try await sendRequest(method: "account/login/start", params: [
            "type": "chatgpt",
            "useHostedLoginSuccessPage": false
        ])
        guard let result = response["result"] as? [String: Any],
              let login = result["loginId"] as? String,
              let authString = result["authUrl"] as? String,
              let authURL = URL(string: authString) else {
            throw ProfileError.transactionFailed("The authentication helper returned an invalid browser sign-in response.")
        }
        return LoginAttempt(loginID: login, authURL: authURL)
    }

    public func waitForAuthenticationEvent(loginID: String) async throws -> AuthenticationEvent {
        try await withThrowingTaskGroup(of: AuthenticationEvent.self) { group in
            group.addTask { [router] in
                let data = try await router.waitForNotification(
                    method: "account/login/completed",
                    loginID: loginID
                )
                return try Self.parseLoginCompleted(data, expectedLoginID: loginID)
            }
            group.addTask { [router] in
                let data = try await router.waitForNotification(
                    method: "account/updated",
                    loginID: nil
                )
                return try Self.parseAccountUpdated(data)
            }
            defer { group.cancelAll() }
            guard let event = try await group.next() else {
                throw ProfileError.transactionFailed("Browser sign-in ended without a result.")
            }
            return event
        }
    }

    private static func parseLoginCompleted(
        _ data: Data,
        expectedLoginID: String
    ) throws -> AuthenticationEvent {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let params = object["params"] as? [String: Any],
              let notificationLoginID = params["loginId"] as? String,
              notificationLoginID == expectedLoginID else {
            throw ProfileError.transactionFailed("The authentication helper returned an invalid browser sign-in completion.")
        }
        let success = params["success"] as? Bool ?? false
        return .loginCompleted(loginID: notificationLoginID, success: success)
    }

    private static func parseAccountUpdated(_ data: Data) throws -> AuthenticationEvent {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let params = object["params"] as? [String: Any] else {
            throw ProfileError.transactionFailed("The authentication helper returned an invalid account update.")
        }
        return .accountUpdated(authMode: params["authMode"] as? String)
    }

    public func cancelLogin(loginID: String) async throws {
        _ = try await sendRequest(method: "account/login/cancel", params: ["loginId": loginID])
    }

    public func readAccount(refreshToken: Bool = false) async throws -> AccountIdentity {
        try await initialize()
        let response = try await sendRequest(method: "account/read", params: ["refreshToken": refreshToken])
        guard let result = response["result"] as? [String: Any],
              let account = result["account"] as? [String: Any],
              let type = account["type"] as? String,
              type == "chatgpt",
              let email = account["email"] as? String,
              !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProfileError.identityUnverified
        }

        let planType = account["planType"] as? String
        return AccountIdentity(
            email: IdentityHasher.normalizeEmail(email),
            planType: planType,
            identityHash: IdentityHasher.hashEmail(email)
        )
    }

    public func stop() async {
        guard !stopped else { return }
        stopped = true
        stdoutPump.stop()
        stderrPump.stop()
        input.closeFile()
        output.closeFile()
        await router.finish()
        if process.isRunning {
            process.terminate()
        }
    }

    private func sendRequest(method: String, params: [String: Any]) async throws -> [String: Any] {
        try Task.checkCancellation()
        let requestID = nextID
        nextID += 1
        let request: [String: Any] = ["id": requestID, "method": method, "params": params]
        let data = try JSONSerialization.data(withJSONObject: request, options: [])
        input.write(data)
        input.write(Data([0x0A]))

        let router = router
        let responseData = try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await router.waitForResponse(id: requestID)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: Self.requestTimeoutNanoseconds)
                throw ProfileError.transactionFailed("The authentication helper did not respond in time.")
            }
            defer { group.cancelAll() }
            guard let response = try await group.next() else {
                throw ProfileError.transactionFailed("The authentication helper did not return a response.")
            }
            return response
        }

        guard let response = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let responseID = response["id"] as? NSNumber,
              responseID.intValue == requestID else {
            throw ProfileError.transactionFailed("The authentication helper returned an invalid response.")
        }
        if response["error"] != nil {
            throw requestFailure(for: method)
        }
        return response
    }

    private func sendNotification(method: String, params: [String: Any]) throws {
        try Task.checkCancellation()
        let notification: [String: Any] = ["method": method, "params": params]
        let data = try JSONSerialization.data(withJSONObject: notification, options: [])
        input.write(data)
        input.write(Data([0x0A]))
    }

    private func requestFailure(for method: String) -> ProfileError {
        switch method {
        case "initialize":
            return .transactionFailed("The authentication helper could not initialize.")
        case "account/login/start":
            return .transactionFailed("The authentication helper could not start browser sign-in.")
        case "account/login/cancel":
            return .transactionFailed("The authentication helper could not cancel browser sign-in.")
        case "account/read":
            return .transactionFailed("The authentication helper could not verify the account.")
        default:
            return .transactionFailed("The authentication helper rejected a request.")
        }
    }
}

public protocol AccountVerifying: Sendable {
    func verify(_ profile: CodexProfile) async throws -> AccountIdentity
}

public struct AccountVerifier: AccountVerifying, Sendable {
    private let locator: ChatGPTLocator

    public init(locator: ChatGPTLocator = ChatGPTLocator()) {
        self.locator = locator
    }

    public func verify(_ profile: CodexProfile) async throws -> AccountIdentity {
        let app = try locator.locate()
        let client = try AppServerSession(executableURL: app.codexExecutableURL, codexHome: profile.codexHomeURL)
        do {
            let identity = try await client.readAccount(refreshToken: false)
            await client.stop()
            if let expected = profile.expectedIdentityHash, expected != identity.identityHash {
                throw ProfileError.identityMismatch
            }
            return identity
        } catch {
            await client.stop()
            throw error
        }
    }
}

private enum AuthenticationMonitorResult: Sendable {
    case identity(AccountIdentity)
    case failure(ProfileError)
    case cancelled
}

actor AuthenticationCompletionMonitor {
    private var terminalResult: AuthenticationMonitorResult?
    private var waiter: CheckedContinuation<AuthenticationMonitorResult, Never>?

    func wait() async throws -> AccountIdentity {
        let result = await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                if let terminalResult {
                    continuation.resume(returning: terminalResult)
                } else {
                    waiter = continuation
                }
            }
        }, onCancel: {
            Task { await self.cancelWaiter() }
        })

        switch result {
        case .identity(let identity):
            return identity
        case .failure(let error):
            throw error
        case .cancelled:
            throw CancellationError()
        }
    }

    func resolve(_ identity: AccountIdentity) {
        finish(with: .identity(identity))
    }

    func fail(_ error: ProfileError) {
        finish(with: .failure(error))
    }

    func cancel() {
        finish(with: .cancelled)
    }

    private func cancelWaiter() {
        guard terminalResult == nil else { return }
        waiter?.resume(returning: .cancelled)
        waiter = nil
    }

    private func finish(with result: AuthenticationMonitorResult) {
        guard terminalResult == nil else { return }
        terminalResult = result
        waiter?.resume(returning: result)
        waiter = nil
    }
}

public actor AuthenticationCoordinator {
    public typealias BrowserOpener = @MainActor @Sendable (URL) -> Bool
    public typealias ProgressHandler = @Sendable (AuthenticationState) async -> Void
    public typealias SessionFactory = @Sendable (URL, URL) async throws -> any AppServerSessionProtocol

    private let locator: ChatGPTLocator
    private let appProvider: @Sendable () throws -> ChatGPTApplication
    private let browserOpener: BrowserOpener
    private let sessionFactory: SessionFactory
    private let timeoutNanoseconds: UInt64
    private let reconciliationTimeoutNanoseconds: UInt64
    private let reconciliationRetryNanoseconds: UInt64
    private let unboundPollNanoseconds: UInt64
    private var activeSession: (any AppServerSessionProtocol)?
    private var activeAttempt: LoginAttempt?
    private var activeMonitor: AuthenticationCompletionMonitor?
    private var activeExpectedIdentityHash: String?
    private var activeProgress: ProgressHandler?

    public init(
        locator: ChatGPTLocator = ChatGPTLocator(),
        timeoutNanoseconds: UInt64 = 600_000_000_000,
        reconciliationTimeoutNanoseconds: UInt64 = 10_000_000_000,
        reconciliationRetryNanoseconds: UInt64 = 250_000_000,
        unboundPollNanoseconds: UInt64 = 1_000_000_000,
        browserOpener: @escaping BrowserOpener,
        appProvider: (@Sendable () throws -> ChatGPTApplication)? = nil,
        sessionFactory: @escaping SessionFactory = { executableURL, codexHome in
            try AppServerSession(executableURL: executableURL, codexHome: codexHome)
        }
    ) {
        self.locator = locator
        self.appProvider = appProvider ?? { try locator.locate() }
        self.browserOpener = browserOpener
        self.sessionFactory = sessionFactory
        self.timeoutNanoseconds = timeoutNanoseconds
        self.reconciliationTimeoutNanoseconds = reconciliationTimeoutNanoseconds
        self.reconciliationRetryNanoseconds = reconciliationRetryNanoseconds
        self.unboundPollNanoseconds = unboundPollNanoseconds
    }

    public func signIn(
        profile: CodexProfile,
        progress: @escaping ProgressHandler = { _ in }
    ) async throws -> AccountIdentity {
        guard activeSession == nil else {
            throw ProfileError.transactionFailed("A browser sign-in is already in progress.")
        }

        var session: (any AppServerSessionProtocol)?
        var loginID: String?
        let monitor = AuthenticationCompletionMonitor()
        do {
            await progress(.preparing)
            try Task.checkCancellation()
            let app = try appProvider()
            let createdSession = try await sessionFactory(app.codexExecutableURL, profile.codexHomeURL)
            session = createdSession
            activeSession = createdSession
            activeMonitor = monitor
            activeExpectedIdentityHash = profile.expectedIdentityHash
            activeProgress = progress

            await progress(.requestingLoginURL)
            let attempt = try await createdSession.startChatGPTLogin()
            guard attempt.authURL.scheme?.lowercased() == "https",
                  let host = attempt.authURL.host?.lowercased(),
                  host == "chatgpt.com" || host.hasSuffix(".chatgpt.com") || host == "openai.com" || host.hasSuffix(".openai.com") else {
                throw ProfileError.transactionFailed("The authentication helper returned an untrusted browser sign-in URL.")
            }

            loginID = attempt.loginID
            activeAttempt = attempt
            await progress(.openingBrowser)
            guard await browserOpener(attempt.authURL) else {
                throw ProfileError.transactionFailed("The default browser could not be opened for sign-in.")
            }

            await progress(.awaitingCallback)
            let timeoutNanoseconds = timeoutNanoseconds
            let reconciliationTimeoutNanoseconds = reconciliationTimeoutNanoseconds
            let reconciliationRetryNanoseconds = reconciliationRetryNanoseconds
            let unboundPollNanoseconds = unboundPollNanoseconds
            let expectedIdentityHash = profile.expectedIdentityHash
            let identity = try await withThrowingTaskGroup(of: AccountIdentity.self) { group in
                group.addTask {
                    try await monitor.wait()
                }
                group.addTask {
                    try await Self.waitForAutomaticIdentity(
                        session: createdSession,
                        loginID: attempt.loginID,
                        expectedIdentityHash: expectedIdentityHash,
                        reconciliationTimeoutNanoseconds: reconciliationTimeoutNanoseconds,
                        reconciliationRetryNanoseconds: reconciliationRetryNanoseconds,
                        unboundPollNanoseconds: unboundPollNanoseconds,
                        progress: progress
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    throw ProfileError.transactionFailed("Browser sign-in timed out.")
                }
                defer { group.cancelAll() }
                guard let identity = try await group.next() else {
                    throw ProfileError.transactionFailed("Browser sign-in ended without a result.")
                }
                return identity
            }

            await createdSession.stop()
            clearActiveSignIn()
            return identity
        } catch {
            if let session, let loginID {
                try? await session.cancelLogin(loginID: loginID)
            }
            if let session {
                await session.stop()
            }
            clearActiveSignIn()
            throw error
        }
    }

    public func checkPendingSignIn() async -> Bool {
        guard let session = activeSession,
              activeAttempt != nil,
              let monitor = activeMonitor else {
            return false
        }

        SwitchLogger.authenticationStage("manual-account-check")
        do {
            let identity = try await session.readAccount(refreshToken: false)
            let verified = try Self.validate(identity, expectedIdentityHash: activeExpectedIdentityHash)
            if let activeProgress {
                await activeProgress(.verifying)
            }
            SwitchLogger.authenticationStage("account-readable")
            await monitor.resolve(verified)
            return true
        } catch ProfileError.identityMismatch {
            await monitor.fail(.identityMismatch)
            return false
        } catch {
            return false
        }
    }

    public func openBrowserAgain() async -> Bool {
        guard let attempt = activeAttempt, activeSession != nil else { return false }
        return await browserOpener(attempt.authURL)
    }

    public func cancel() async {
        guard let session = activeSession else { return }
        await activeMonitor?.cancel()
        if let loginID = activeAttempt?.loginID {
            try? await session.cancelLogin(loginID: loginID)
        }
        await session.stop()
        clearActiveSignIn()
    }

    private func clearActiveSignIn() {
        activeAttempt = nil
        activeSession = nil
        activeMonitor = nil
        activeExpectedIdentityHash = nil
        activeProgress = nil
    }

    private static func waitForAutomaticIdentity(
        session: any AppServerSessionProtocol,
        loginID: String,
        expectedIdentityHash: String?,
        reconciliationTimeoutNanoseconds: UInt64,
        reconciliationRetryNanoseconds: UInt64,
        unboundPollNanoseconds: UInt64,
        progress: @escaping ProgressHandler
    ) async throws -> AccountIdentity {
        try await withThrowingTaskGroup(of: AccountIdentity.self) { group in
            group.addTask {
                try await waitForEventAndIdentity(
                    session: session,
                    loginID: loginID,
                    expectedIdentityHash: expectedIdentityHash,
                    reconciliationTimeoutNanoseconds: reconciliationTimeoutNanoseconds,
                    reconciliationRetryNanoseconds: reconciliationRetryNanoseconds,
                    progress: progress
                )
            }
            if expectedIdentityHash == nil {
                group.addTask {
                    try await pollForUnboundIdentity(
                        session: session,
                        pollNanoseconds: unboundPollNanoseconds,
                        progress: progress
                    )
                }
            }
            defer { group.cancelAll() }
            guard let identity = try await group.next() else {
                throw ProfileError.transactionFailed("Browser sign-in ended without a result.")
            }
            return identity
        }
    }

    private static func waitForEventAndIdentity(
        session: any AppServerSessionProtocol,
        loginID: String,
        expectedIdentityHash: String?,
        reconciliationTimeoutNanoseconds: UInt64,
        reconciliationRetryNanoseconds: UInt64,
        progress: @escaping ProgressHandler
    ) async throws -> AccountIdentity {
        while true {
            let event = try await session.waitForAuthenticationEvent(loginID: loginID)
            switch event {
            case .loginCompleted(let completedLoginID, let success):
                guard completedLoginID == loginID, success else {
                    throw ProfileError.transactionFailed("Browser sign-in was not completed.")
                }
                SwitchLogger.authenticationStage("login-completed-observed")
            case .accountUpdated(let authMode):
                guard authMode?.lowercased() == "chatgpt" else { continue }
                SwitchLogger.authenticationStage("account-updated-observed")
            }

            await progress(.verifying)
            return try await retryAccountRead(
                session: session,
                expectedIdentityHash: expectedIdentityHash,
                timeoutNanoseconds: reconciliationTimeoutNanoseconds,
                retryNanoseconds: reconciliationRetryNanoseconds
            )
        }
    }

    private static func retryAccountRead(
        session: any AppServerSessionProtocol,
        expectedIdentityHash: String?,
        timeoutNanoseconds: UInt64,
        retryNanoseconds: UInt64
    ) async throws -> AccountIdentity {
        var elapsed: UInt64 = 0
        while true {
            try Task.checkCancellation()
            do {
                let identity = try await session.readAccount(refreshToken: false)
                let verified = try validate(identity, expectedIdentityHash: expectedIdentityHash)
                SwitchLogger.authenticationStage("account-readable")
                return verified
            } catch ProfileError.identityUnverified {
                guard elapsed < timeoutNanoseconds else {
                    throw ProfileError.identityUnverified
                }
                let delay = min(retryNanoseconds, timeoutNanoseconds - elapsed)
                try await Task.sleep(nanoseconds: delay)
                elapsed += delay
            }
        }
    }

    private static func pollForUnboundIdentity(
        session: any AppServerSessionProtocol,
        pollNanoseconds: UInt64,
        progress: @escaping ProgressHandler
    ) async throws -> AccountIdentity {
        while true {
            try await Task.sleep(nanoseconds: pollNanoseconds)
            do {
                let identity = try await session.readAccount(refreshToken: false)
                let verified = try validate(identity, expectedIdentityHash: nil)
                await progress(.verifying)
                SwitchLogger.authenticationStage("account-readable")
                return verified
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A fresh profile is expected to be unreadable until the callback
                // commits credentials. The event watcher remains authoritative for
                // protocol and helper failures while this bounded poll continues.
            }
        }
    }

    private static func validate(
        _ identity: AccountIdentity,
        expectedIdentityHash: String?
    ) throws -> AccountIdentity {
        if let expectedIdentityHash, expectedIdentityHash != identity.identityHash {
            throw ProfileError.identityMismatch
        }
        return identity
    }
}
