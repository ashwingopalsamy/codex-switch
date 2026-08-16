import AppKit
import SwiftUI

struct MenuBarIcon: View {
    private static let imageName = "CodexSwitchMenuBar"
    private static let menuBarImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: imageName, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }

        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    var body: some View {
        icon
            .foregroundStyle(.primary)
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var icon: some View {
        if let menuBarImage = Self.menuBarImage {
            Image(nsImage: menuBarImage)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "person.2.circle")
                .imageScale(.medium)
        }
    }
}
