import CryptoKit
import Foundation

public enum IdentityHasher {
    public static func normalizeEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func hashEmail(_ value: String) -> String {
        let normalized = normalizeEmail(value)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
