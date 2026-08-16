import AppKit
import Foundation

public protocol ChatGPTProcessControlling: Sendable {
    func inspectSession() throws -> ChatGPTProcessSnapshot?
    func quitGracefully() async throws
    func launchAndConfirm(profile: CodexProfile) async throws
}

public final class CodexProcessController: ChatGPTProcessControlling, @unchecked Sendable {
    private let locator: ChatGPTLocator
    private let snapshots: DarwinProcessSnapshotProvider

    public init(
        locator: ChatGPTLocator = ChatGPTLocator(),
        snapshots: DarwinProcessSnapshotProvider? = nil
    ) {
        self.locator = locator
        self.snapshots = snapshots ?? DarwinProcessSnapshotProvider(locator: locator)
    }

    public func inspectSession() throws -> ChatGPTProcessSnapshot? {
        try snapshots.snapshot()
    }

    public func quitGracefully() async throws {
        try await quitGracefully(timeout: 20)
    }

    private func quitGracefully(timeout: TimeInterval) async throws {
        let app = try locator.locate()
        guard let initial = try snapshots.snapshot() else { return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier)
            .filter { $0.processIdentifier == initial.mainPID }
        guard let application = running.first else { return }
        guard application.terminate() else {
            throw ProfileError.transactionFailed("ChatGPT did not accept a graceful quit request.")
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let mainAlive = snapshots.processExists(initial.mainPID, matchingBundleURL: app.bundleURL)
            let helpersAlive = initial.accountBearingPIDs.contains {
                $0 != initial.mainPID && snapshots.processExists($0, matchingBundleURL: app.bundleURL)
            }
            if !mainAlive && !helpersAlive { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ProfileError.transactionFailed("ChatGPT did not exit gracefully within \(Int(timeout)) seconds.")
    }

    public func launchAndConfirm(profile: CodexProfile) async throws {
        try await launch(profile: profile)
        try await waitUntilRunning(profile: profile)
    }

    private func launch(profile: CodexProfile) async throws {
        let app = try locator.locate()
        let context = LaunchContext(profile: profile)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = context.arguments
        configuration.environment = context.environment

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: app.bundleURL, configuration: configuration) { application, error in
                if let error {
                    continuation.resume(throwing: ProfileError.transactionFailed(error.localizedDescription))
                } else if application == nil {
                    continuation.resume(throwing: ProfileError.transactionFailed("ChatGPT did not return a running application."))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func waitUntilRunning(profile: CodexProfile, timeout: TimeInterval = 20) async throws {
        let app = try locator.locate()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let snapshot = try snapshots.snapshot(), snapshot.exposes(profile: profile) {
                let expectedExecutable = app.executableURL.standardizedFileURL.path
                if let running = NSRunningApplication(processIdentifier: snapshot.mainPID),
                   running.executableURL?.standardizedFileURL.path == expectedExecutable {
                    return
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ProfileError.transactionFailed("ChatGPT started without exposing the requested profile roots.")
    }
}
