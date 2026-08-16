import Darwin
import Foundation

public final class OperationLock: @unchecked Sendable {
    private let url: URL
    private var descriptor: Int32 = -1

    public init(url: URL) {
        self.url = url
    }

    public func acquire() throws {
        try SecureFileSystem.createDirectory(url.deletingLastPathComponent())
        descriptor = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw ProfileError.transactionFailed("Could not create the switch operation lock.")
        }
        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            close(descriptor)
            descriptor = -1
            throw ProfileError.transactionFailed("Another profile switch is already in progress.")
        }
    }

    public func release() {
        guard descriptor >= 0 else { return }
        _ = flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit {
        release()
    }
}
