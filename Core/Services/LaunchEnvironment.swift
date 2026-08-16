import Foundation

public enum LaunchEnvironment {
    private static let sensitiveKeys: Set<String> = [
        "CODEX_HOME",
        "OPENAI_API_KEY",
        "CODEX_API_KEY",
        "CHATGPT_ACCESS_TOKEN",
        "CHATGPT_REFRESH_TOKEN",
        "OAUTH_ACCESS_TOKEN",
        "OAUTH_REFRESH_TOKEN"
    ]

    public static func sanitized(_ source: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        source.filter { key, _ in
            guard !sensitiveKeys.contains(key) else { return false }
            let uppercaseKey = key.uppercased()
            return !uppercaseKey.contains("TOKEN") &&
                !uppercaseKey.contains("PASSWORD") &&
                !uppercaseKey.contains("SECRET") &&
                !uppercaseKey.contains("API_KEY") &&
                !uppercaseKey.contains("OAUTH")
        }
    }
}
