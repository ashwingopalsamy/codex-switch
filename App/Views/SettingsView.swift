import AppKit
import CodexSwitchCore
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @State private var profilePendingRemoval: CodexProfile?
    @State private var isRemovalConfirmationPresented = false
    @State private var isLiveSessionHandoffConfirmationPresented = false
    @State private var isCompatibilityConfirmationPresented = false
    @State private var isFAQPresented = false

    init(model: AppModel) {
        self.model = model
    }

    var body: some View {
        compatibilityAlert
    }

    private var compatibilityAlert: some View {
        liveSessionAlert
            .alert(
                "Allow provisional compatibility?",
                isPresented: $isCompatibilityConfirmationPresented,
                presenting: model.pendingCompatibilityAcknowledgement
            ) { _ in
                Button("Allow for This Version") {
                    model.confirmProvisionalCompatibility()
                }
                Button("Cancel", role: .cancel) {
                    model.cancelProvisionalCompatibility()
                }
            } message: { pending in
                Text("ChatGPT \(pending.appVersion) has not completed the optional guided diagnostics. CodexSwitch will still verify account identity and exact profile roots, then roll back if the requested launch cannot be confirmed. Continue to \(pending.action.description)?")
            }
    }

    private var liveSessionAlert: some View {
        removalConfirmation
            .alert(
                "Close ChatGPT and switch?",
                isPresented: $isLiveSessionHandoffConfirmationPresented,
                presenting: model.pendingLiveSessionHandoff
            ) { _ in
                Button("Close ChatGPT and Switch", role: .destructive) {
                    model.confirmLiveSessionHandoff()
                }
                Button("Cancel", role: .cancel) {
                    model.cancelLiveSessionHandoff()
                }
            } message: { pending in
                Text("A Codex conversation is open in \(pending.sourceDisplayName). Switching to \(pending.targetDisplayName) will safely close ChatGPT and interrupt any response or tool work still running.")
            }
    }

    private var removalConfirmation: some View {
        content
            .confirmationDialog(
                "Remove profile?",
                isPresented: $isRemovalConfirmationPresented,
                presenting: profilePendingRemoval
            ) { profile in
                Button("Move \(profile.displayName) to Trash", role: .destructive) {
                    model.remove(profile)
                    profilePendingRemoval = nil
                }
                Button("Cancel", role: .cancel) {
                    profilePendingRemoval = nil
                }
            } message: { _ in
                Text("The managed profile roots will be moved to the macOS Trash. The adopted Profile A cannot be removed.")
            }
    }

    private var content: some View {
        Group {
            if isFAQPresented {
                FAQSheetView(isPresented: $isFAQPresented)
                    .transition(.opacity)
            } else {
                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: UITheme.Spacing.lg) {
                            headerView
                            profilesSection
                        }
                        .padding(.horizontal, UITheme.Spacing.windowPadding)
                        .padding(.top, 32)
                        .padding(.bottom, 60)
                    }
                    .ignoresSafeArea(.all, edges: .top)

                    StatusDockView(model: model, isFAQPresented: $isFAQPresented)
                }
                .transition(.opacity)
            }
        }
        .instantTooltipContainer()
        .frame(width: 480)
        .frame(minHeight: 380, maxHeight: 580)
        .background(VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow).ignoresSafeArea())
        .background(
            WindowAccessor { window in
                window.isOpaque = false
                window.backgroundColor = .clear
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.titlebarSeparatorStyle = .none
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = true
                window.minSize = NSSize(width: 480, height: 380)
                window.maxSize = NSSize(width: 480, height: 700)
                if abs(window.frame.width - 480) > 1.0 {
                    var frame = window.frame
                    frame.origin.x += (frame.width - 480) / 2
                    frame.size.width = 480
                    window.setFrame(frame, display: true, animate: false)
                }
            }
        )
        .onAppear {
            UserDefaults.standard.set(ProcessInfo.processInfo.processIdentifier, forKey: "CodexSwitchManagementWindowPID")
            isLiveSessionHandoffConfirmationPresented = model.pendingLiveSessionHandoff != nil
            isCompatibilityConfirmationPresented = model.pendingCompatibilityAcknowledgement != nil
        }
        .onChange(of: model.pendingLiveSessionHandoff?.id) { _, pendingID in
            isLiveSessionHandoffConfirmationPresented = pendingID != nil
        }
        .onChange(of: isLiveSessionHandoffConfirmationPresented) { _, isPresented in
            if !isPresented, model.pendingLiveSessionHandoff != nil {
                model.cancelLiveSessionHandoff()
            }
        }
        .onChange(of: model.pendingCompatibilityAcknowledgement?.id) { _, pendingID in
            isCompatibilityConfirmationPresented = pendingID != nil
        }
        .onChange(of: isCompatibilityConfirmationPresented) { _, isPresented in
            if !isPresented, model.pendingCompatibilityAcknowledgement != nil {
                model.cancelProvisionalCompatibility()
            }
        }
        .task {
            ManagementWindowPresenter.presentExisting()
            model.start()
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(alignment: .center, spacing: UITheme.Spacing.sm + 2) {
            appIconView

            VStack(alignment: .leading, spacing: 2) {
                Text("CodexSwitch")
                    .font(UITheme.Typography.appTitle)

                Text("One verified ChatGPT desktop session at a time, with profile-local Codex state.")
                    .font(UITheme.Typography.appSubtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var appIconView: some View {
        Group {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: UITheme.Spacing.avatarSize, height: UITheme.Spacing.avatarSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: Color.black.opacity(0.1), radius: 3, y: 1.5)
            } else {
                Image(systemName: "app.badge.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    // MARK: - Profiles Section
    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: UITheme.Spacing.xs) {
            HStack(spacing: 6) {
                Text("Profiles")
                    .font(UITheme.Typography.sectionHeader)
                    .foregroundStyle(.secondary)

                Text("\(model.document.profiles.count)")
                    .font(UITheme.Typography.badge)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(UITheme.Colors.buttonSecondaryBg)
                    .clipShape(Capsule())

                Spacer()
            }
            .padding(.horizontal, 2)

            VStack(spacing: 8) {
                ForEach(model.document.profiles) { profile in
                    ProfileCardView(
                        profile: profile,
                        model: model,
                        onRemove: { target in
                            model.remove(target)
                        }
                    )
                }

                AddProfileCardView(model: model)
            }
        }
        .background {
            // Invisible keyboard shortcut triggers (Cmd+1..9)
            ForEach(Array(model.document.profiles.enumerated()), id: \.element.id) { index, profile in
                if index < 9 {
                    Button("") {
                        if model.activeProfileID != profile.id && model.isReady(profile) && !model.isWorking && !model.hasPendingSwitchConfirmation {
                            model.switchTo(profile)
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .opacity(0)
                    .allowsHitTesting(false)
                }
            }
        }
    }
}
