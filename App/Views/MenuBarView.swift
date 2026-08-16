import AppKit
import CodexSwitchCore
import SwiftUI

struct MenuBarView: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if model.document.profiles.isEmpty {
                Text("No profiles configured")
            } else {
                // Active Profile Header
                Text(activeProfileHeader)

                // Switch Profile Submenu
                Menu("Switch Profile") {
                    ForEach(model.document.profiles) { profile in
                        let isActive = model.activeProfileID == profile.id
                        let isReady = model.isReady(profile)

                        Button {
                            if isReady {
                                model.switchTo(profile)
                            } else {
                                showManagementWindow()
                            }
                        } label: {
                            HStack {
                                Text(profileTitle(for: profile))
                                if isActive {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .disabled(isActive || model.isWorking || model.hasPendingSwitchConfirmation)
                    }
                }

                Divider()

                // ChatGPT Action
                if model.isChatGPTRunning {
                    Button("ChatGPT (Running)") {
                        model.openChatGPT()
                    }
                } else {
                    Button("Open ChatGPT") {
                        model.openChatGPT()
                    }
                    .disabled(model.isWorking || model.hasPendingSwitchConfirmation)
                }

                Button("Manage Profiles…") {
                    showManagementWindow()
                }

                // Dynamic Status and Alert Section
                if model.isWorking {
                    Divider()
                    Label(model.statusMessage, systemImage: "arrow.triangle.2.circlepath")
                } else if let error = model.lastError {
                    Divider()
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                } else if let recovery = model.recoveryMessage {
                    Divider()
                    Label(recovery, systemImage: "shield.righthalf.filled")
                }

                Divider()

                Button("Quit CodexSwitch") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .onAppear {
            UserDefaults.standard.set(ProcessInfo.processInfo.processIdentifier, forKey: "CodexSwitchMenuBarPID")
        }
        .onChange(of: model.pendingLiveSessionHandoff?.id) { _, pendingID in
            if pendingID != nil {
                showManagementWindow()
            }
        }
        .onChange(of: model.pendingCompatibilityAcknowledgement?.id) { _, pendingID in
            if pendingID != nil {
                showManagementWindow()
            }
        }
    }

    private var activeProfileHeader: String {
        guard let active = model.document.profiles.first(where: { $0.id == model.activeProfileID }) else {
            return "No Active Profile"
        }
        if let email = model.transientIdentities[active.id] ?? model.transientIdentity {
            return "Active: \(active.displayName) (\(email))"
        }
        if active.expectedIdentityHash != nil {
            return "Active: \(active.displayName)"
        }
        return "Active: \(active.displayName) (Not Signed In)"
    }

    private func profileTitle(for profile: CodexProfile) -> String {
        if let email = model.transientIdentities[profile.id] {
            return "\(profile.displayName) (\(email))"
        }
        if model.activeProfileID == profile.id, let email = model.transientIdentity {
            return "\(profile.displayName) (\(email))"
        }
        if profile.expectedIdentityHash != nil {
            return "\(profile.displayName)"
        }
        return "\(profile.displayName) (Sign In Required)"
    }

    private func showManagementWindow() {
        openWindow(id: "management")
        NSApp.activate(ignoringOtherApps: true)
    }
}
