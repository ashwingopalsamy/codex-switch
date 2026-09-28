#if DEBUG
import SwiftUI

#Preview("Synthetic profile manager") {
    SettingsView(model: ScreenshotFixtures.model(), startsModelLifecycle: false)
}

#Preview("Synthetic menu bar") {
    MenuBarView(model: ScreenshotFixtures.model(), recordsLifecycle: false)
        .padding()
}
#endif
