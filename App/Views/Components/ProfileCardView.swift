import AppKit
import CodexSwitchCore
import SwiftUI

struct ProfileCardView: View {
    let profile: CodexProfile
    let model: AppModel
    let onRemove: (CodexProfile) -> Void
    @State private var isHovered = false
    @State private var isConfirmingDelete = false
    @State private var isEditingName = false
    @State private var editedName = ""
    @FocusState private var isNameFieldFocused: Bool

    init(
        profile: CodexProfile,
        model: AppModel,
        onRemove: @escaping (CodexProfile) -> Void
    ) {
        self.profile = profile
        self.model = model
        self.onRemove = onRemove
    }

    private var isActive: Bool {
        model.activeProfileID == profile.id
    }

    private var isAuthenticating: Bool {
        model.authenticationProfileID == profile.id && model.isWorking
    }

    private var isVerified: Bool {
        profile.expectedIdentityHash != nil
    }

    private var canSwitch: Bool {
        !isActive && model.isReady(profile) && !model.isWorking && !model.hasPendingSwitchConfirmation
    }

    private var fullEmail: String {
        if isAuthenticating {
            return "Signing in via browser…"
        }
        if let email = model.transientIdentities[profile.id] {
            return email
        }
        if isActive, let identity = model.transientIdentity {
            return identity
        }
        if isVerified {
            return "Signed in"
        }
        return "Not signed in"
    }

    private var displayEmail: String {
        let email = fullEmail
        if email.count > 25 {
            return String(email.prefix(24)) + "…"
        }
        return email
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UITheme.Spacing.sm) {
            HStack(spacing: UITheme.Spacing.md) {
                avatarView

                VStack(alignment: .leading, spacing: 3) {
                    Group {
                        if isEditingName {
                            TextField("Profile name", text: $editedName)
                                .font(UITheme.Typography.cardTitle)
                                .textFieldStyle(.plain)
                                .focused($isNameFieldFocused)
                                .onSubmit {
                                    commitRename()
                                }
                                .onExitCommand {
                                    cancelRename()
                                }
                                .padding(.horizontal, 6)
                                .frame(height: 24)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1)
                                }
                                .frame(maxWidth: 180, alignment: .leading)
                        } else {
                            Text(profile.displayName)
                                .font(UITheme.Typography.cardTitle)
                                .lineLimit(1)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    editedName = profile.displayName
                                    isEditingName = true
                                    isNameFieldFocused = true
                                }
                                .instantTooltip("Double-click to rename")
                        }
                    }
                    .frame(height: 24, alignment: .leading)

                    Text(displayEmail)
                        .font(UITheme.Typography.cardSubtitle)
                        .foregroundStyle(isAuthenticating ? Color.accentColor : (isVerified ? .secondary : UITheme.Colors.amber))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .layoutPriority(0)

                Spacer()

                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Button {
                            model.openProfile(profile)
                        } label: {
                            Image(systemName: profile.storageKind == .managed ? "folder.badge.person.crop" : "folder")
                        }
                        .buttonStyle(.tactileCircleSecondary)
                        .unfocusedControl()
                        .instantTooltip("Reveal in Finder")

                        if isVerified {
                            Button {
                                model.signIn(profile)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.tactileCircleSecondary)
                            .unfocusedControl()
                            .instantTooltip("Re-authenticate in browser")
                        } else {
                            Button {
                                model.signIn(profile)
                            } label: {
                                Image(systemName: "arrow.up.forward.app")
                            }
                            .buttonStyle(.tactileCirclePrimary)
                            .unfocusedControl()
                            .instantTooltip("Sign in with browser")
                        }

                        if profile.storageKind == .managed && !isActive {
                            Button(role: .destructive) {
                                withAnimation(UITheme.Animations.spring) {
                                    isConfirmingDelete.toggle()
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(isConfirmingDelete ? .tactileCircleDestructive : .tactileCircleSecondary)
                            .unfocusedControl()
                            .instantTooltip("Delete this profile")
                        }
                    }
                    .opacity(isHovered || isConfirmingDelete ? 1.0 : 0.0)
                    .scaleEffect(isHovered || isConfirmingDelete ? 1.0 : 0.92)
                    .animation(UITheme.Animations.hover, value: isHovered)
                    .disabled(model.isWorking || model.hasPendingSwitchConfirmation)

                    if isActive {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(UITheme.Colors.emerald)
                                .frame(width: 6, height: 6)
                            Text("Active")
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(UITheme.Colors.emerald)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .frame(minWidth: 78, minHeight: 28)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    } else if canSwitch {
                        Button {
                            model.switchTo(profile)
                        } label: {
                            Label("Switch", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.tactilePrimary)
                        .controlSize(.small)
                        .frame(minWidth: 78, minHeight: 28)
                        .unfocusedControl()
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .layoutPriority(1)
                .disabled(model.isWorking || model.hasPendingSwitchConfirmation)
            }

            if isConfirmingDelete {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(UITheme.Colors.coral)
                        .font(.caption)

                    Text("Move \"\(profile.displayName)\" isolated roots to the macOS Trash?")
                        .font(.caption)
                        .foregroundStyle(UITheme.Colors.coral)

                    Spacer()

                    Button {
                        withAnimation(UITheme.Animations.spring) {
                            isConfirmingDelete = false
                        }
                    } label: {
                        Text("Cancel")
                    }
                    .buttonStyle(.tactileSubtle)
                    .controlSize(.small)
                    .unfocusedControl()

                    Button(role: .destructive) {
                        withAnimation(UITheme.Animations.spring) {
                            isConfirmingDelete = false
                            onRemove(profile)
                        }
                    } label: {
                        Label("Move to Trash", systemImage: "trash.fill")
                    }
                    .buttonStyle(.tactileDestructive)
                    .controlSize(.small)
                    .unfocusedControl()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.04))
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isAuthenticating {
                inlineAuthenticationStatus
            }
        }
        .padding(.horizontal, UITheme.Spacing.cardPaddingHorizontal)
        .padding(.vertical, UITheme.Spacing.cardPaddingVertical)
        .cardSurface(radius: UITheme.Radius.card)
        .overlay {
            if canSwitch && isHovered {
                RoundedRectangle(cornerRadius: UITheme.Radius.card, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
            }
        }
        .contextMenu {
            if !isActive && canSwitch {
                Button {
                    model.switchTo(profile)
                } label: {
                    Label("Switch to \(profile.displayName)", systemImage: "arrow.triangle.2.circlepath")
                }
            }

            Button {
                model.openProfile(profile)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }

            Button {
                model.signIn(profile)
            } label: {
                Label(isVerified ? "Re-authenticate in Browser…" : "Sign In with Browser…", systemImage: "arrow.up.forward.app")
            }

            Button {
                editedName = profile.displayName
                isEditingName = true
                isNameFieldFocused = true
            } label: {
                Label("Rename Profile", systemImage: "pencil")
            }

            if profile.storageKind == .managed && !isActive {
                Divider()
                Button(role: .destructive) {
                    withAnimation(UITheme.Animations.spring) {
                        isConfirmingDelete = true
                    }
                } label: {
                    Label("Delete Profile…", systemImage: "trash")
                }
            }
        }
        .onHover { hovering in
            withAnimation(UITheme.Animations.hover) {
                isHovered = hovering
            }
        }
        .onChange(of: isNameFieldFocused) { _, isFocused in
            if !isFocused && isEditingName {
                commitRename()
            }
        }
    }

    // MARK: - State-aware SF Symbol Avatar
    private var avatarView: some View {
        let (badgeSymbol, badgeColor, tooltipText) = avatarBadgeAttributes

        return ZStack {
            Circle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: UITheme.Spacing.avatarSize, height: UITheme.Spacing.avatarSize)
                .overlay {
                    Circle()
                        .strokeBorder(UITheme.Colors.cardBorder, lineWidth: 0.5)
                }
                .overlay {
                    if isAuthenticating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "person.crop.circle")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 23, weight: .regular))
                            .foregroundStyle(isActive ? .primary : .secondary)
                    }
                }

            if !isAuthenticating, let badgeSymbol, let badgeColor {
                Image(systemName: badgeSymbol)
                    .symbolRenderingMode(.palette)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white, badgeColor)
                    .frame(width: UITheme.Spacing.avatarSize, height: UITheme.Spacing.avatarSize, alignment: .bottomTrailing)
                    .offset(x: -1, y: -1)
            }
        }
        .instantTooltip(tooltipText)
    }

    private var avatarBadgeAttributes: (badgeSymbol: String?, badgeColor: Color?, tooltip: String) {
        if isAuthenticating {
            return (
                nil,
                nil,
                "Authenticating…"
            )
        } else if !isVerified {
            return (
                "exclamationmark.circle.fill",
                UITheme.Colors.amber,
                isActive ? "Active profile (Not signed in)" : "Not signed in"
            )
        } else {
            return (
                nil,
                nil,
                isActive ? "Active profile" : "Signed in"
            )
        }
    }

    // MARK: - Inline Auth Status
    @ViewBuilder
    private var inlineAuthenticationStatus: some View {
        HStack(spacing: 8) {
            switch model.authenticationState {
            case .preparing, .requestingLoginURL, .openingBrowser:
                ProgressView()
                    .controlSize(.small)
                Text("Opening default browser for authentication…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .awaitingCallback:
                ProgressView()
                    .controlSize(.small)
                Text(model.isCheckingPendingSignIn ? "Checking identity…" : "Finish sign-in in browser, then close tab…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .verifying:
                ProgressView()
                    .controlSize(.small)
                Text("Verifying account identity…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(UITheme.Colors.emerald)
                Text("Sign-in verified")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(UITheme.Colors.emerald)
            case .cancelled:
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Sign-in cancelled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(UITheme.Colors.coral)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(UITheme.Colors.coral)
                    .lineLimit(1)
            case .idle:
                EmptyView()
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
    }

    private func commitRename() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != profile.displayName {
            model.rename(profile, to: trimmed)
        }
        isEditingName = false
    }

    private func cancelRename() {
        editedName = profile.displayName
        isEditingName = false
    }
}
