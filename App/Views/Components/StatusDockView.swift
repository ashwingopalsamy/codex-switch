import AppKit
import CodexSwitchCore
import SwiftUI

struct StatusDockView: View {
    let model: AppModel
    @Binding var isFAQPresented: Bool

    init(model: AppModel, isFAQPresented: Binding<Bool>) {
        self.model = model
        self._isFAQPresented = isFAQPresented
    }

    var body: some View {
        VStack(spacing: 0) {
            // Error Alert Banner if present
            if let error = model.lastError {
                HStack(alignment: .top, spacing: UITheme.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(UITheme.Colors.coral)
                        .font(.caption)
                        .padding(.top, 1)

                    Text(error)
                        .font(.caption)
                        .foregroundStyle(UITheme.Colors.coral)
                        .textSelection(.enabled)
                        .lineLimit(2)

                    Spacer()
                }
                .padding(.horizontal, UITheme.Spacing.windowPadding)
                .padding(.vertical, 8)
                .background(UITheme.Colors.coralBg)
            }

            // Recovery Warning Banner if present
            if let recovery = model.recoveryMessage {
                HStack(alignment: .center, spacing: UITheme.Spacing.xs) {
                    Image(systemName: "shield.righthalf.filled")
                        .foregroundStyle(UITheme.Colors.amber)
                        .font(.caption)

                    Text(recovery)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .textSelection(.enabled)

                    Spacer()

                    Button {
                        model.retryRecovery()
                    } label: {
                        Label("Retry Recovery", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.tactileSecondary)
                    .unfocusedControl()
                    .disabled(model.isWorking)
                }
                .padding(.horizontal, UITheme.Spacing.windowPadding)
                .padding(.vertical, 8)
                .background(UITheme.Colors.amberBg)
            }

            // Main Status Dock Bar
            HStack(spacing: UITheme.Spacing.sm) {
                if model.isWorking {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)

                        Text(model.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .layoutPriority(0)
                } else {
                    Button {
                        withAnimation(UITheme.Animations.spring) {
                            isFAQPresented.toggle()
                        }
                    } label: {
                        Label("FAQ", systemImage: "questionmark.bubble")
                    }
                    .buttonStyle(.tactileSecondary)
                    .controlSize(.small)
                    .unfocusedControl()
                    .instantTooltip("Frequently Asked Questions & Architecture")
                }

                Spacer(minLength: 8)

                // Contextual Actions & Secondary Badges
                HStack(spacing: 6) {
                    if model.canOpenBrowserAgain {
                        Button {
                            model.openBrowserAgain()
                        } label: {
                            Label("Open Browser", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.tactileSecondary)
                        .controlSize(.small)
                        .unfocusedControl()
                        .instantTooltip("Re-open OpenAI authentication page in browser")
                    }

                    if model.canCheckPendingSignIn {
                        Button {
                            model.checkPendingSignIn()
                        } label: {
                            if model.isCheckingPendingSignIn {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .controlSize(.mini)
                                    Text("Checking…")
                                }
                            } else {
                                Label("Check Sign-in", systemImage: "checkmark.circle")
                            }
                        }
                        .buttonStyle(.tactilePrimary)
                        .controlSize(.small)
                        .unfocusedControl()
                        .disabled(model.isCheckingPendingSignIn)
                        .instantTooltip("Verify completed browser sign-in")
                    }

                    if model.canCancelCurrentOperation {
                        Button {
                            model.cancelCurrentOperation()
                        } label: {
                            Text("Cancel")
                        }
                        .buttonStyle(.tactileSubtle)
                        .controlSize(.small)
                        .unfocusedControl()
                        .instantTooltip("Cancel current operation")
                    }

                    if !model.isWorking && !model.canOpenBrowserAgain && !model.canCheckPendingSignIn && !model.canCancelCurrentOperation {
                        if model.isChatGPTRunning {
                            Button {
                            } label: {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(UITheme.Colors.emerald)
                                        .frame(width: 6, height: 6)
                                    Text("ChatGPT Running")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(UITheme.Colors.emerald)
                                }
                            }
                            .buttonStyle(.tactileSubtle)
                            .controlSize(.small)
                            .unfocusedControl()
                            .disabled(true)
                            .opacity(0.85)
                        } else {
                            Button {
                                model.openChatGPT()
                            } label: {
                                Label("Open ChatGPT", systemImage: "arrow.up.forward.app")
                            }
                            .buttonStyle(.tactileSecondary)
                            .controlSize(.small)
                            .unfocusedControl()
                            .instantTooltip("Launch ChatGPT desktop app")
                        }
                    }
                }
                .layoutPriority(1)
            }
            .padding(.horizontal, UITheme.Spacing.windowPadding)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(0.02),
                            Color.primary.opacity(0.09),
                            Color.primary.opacity(0.02)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.5)
        }
    }
}
