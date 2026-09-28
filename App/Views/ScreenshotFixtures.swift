#if DEBUG
import CodexSwitchCore
import Foundation

@MainActor
enum ScreenshotFixtures {
    static func model() -> AppModel {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("CodexSwitch-Screenshot-Fixture", isDirectory: true)
        let firstID = UUID(uuidString: "A7F0D277-C0C9-4D28-86C1-F1A0C35C5C11")!
        let secondID = UUID(uuidString: "B8316D9F-5FB0-4164-A117-4A504E6E703A")!
        let firstRoot = root.appendingPathComponent("p/demo-profile-a", isDirectory: true)
        let secondRoot = root.appendingPathComponent("p/demo-profile-b", isDirectory: true)
        let firstProfile = CodexProfile(
            id: firstID,
            displayName: "Personal",
            codexHomePath: firstRoot.appendingPathComponent("codex-home").path,
            electronDataPath: firstRoot.appendingPathComponent("electron-data").path,
            electronCachePath: firstRoot.appendingPathComponent("electron-cache").path,
            storageKind: .adoptedDefault,
            expectedIdentityHash: "synthetic-demo-only"
        )
        let secondProfile = CodexProfile(
            id: secondID,
            displayName: "Work",
            codexHomePath: secondRoot.appendingPathComponent("codex-home").path,
            electronDataPath: secondRoot.appendingPathComponent("electron-data").path,
            electronCachePath: secondRoot.appendingPathComponent("electron-cache").path,
            storageKind: .managed,
            expectedIdentityHash: "synthetic-demo-only"
        )
        let model = AppModel(store: ProfileStore(root: root))
        model.document = ProfileStoreDocument(
            profiles: [firstProfile, secondProfile],
            activeProfileID: firstID,
            lastCommittedProfileID: firstID
        )
        return model
    }
}
#endif
