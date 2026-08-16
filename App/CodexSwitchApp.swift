import AppKit
import SwiftUI

@MainActor
enum ManagementWindowPresenter {
    static func presentExisting(remainingAttempts: Int = 40) {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.styleMask.contains(.titled) }) {
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.orderFrontRegardless()
            window.makeKey()
            window.makeFirstResponder(nil)
            if window.isVisible { return }
        }
        guard remainingAttempts > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            presentExisting(remainingAttempts: remainingAttempts - 1)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        ProcessInfo.processInfo.disableAutomaticTermination("Persistent menu bar and management window")
        UserDefaults.standard.set(ProcessInfo.processInfo.processIdentifier, forKey: "CodexSwitchMenuBarPID")
        UserDefaults.standard.set(-1, forKey: "CodexSwitchManagementWindowPID")
        ManagementWindowPresenter.presentExisting()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        ManagementWindowPresenter.presentExisting()
        return true
    }
}

@main
struct CodexSwitchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("CodexSwitch", id: "management") {
            SettingsView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 480, height: 440)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Label {
                Text("CodexSwitch")
            } icon: {
                MenuBarIcon()
            }
            .labelStyle(.iconOnly)
            .accessibilityLabel("CodexSwitch")
        }
    }
}
