import SwiftUI

struct FAQItem: Identifiable {
    let id: String
    let category: FAQCategory
    let question: String
    let answer: String
}

enum FAQCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case privacy = "Privacy & Security"
    case auth = "Sign-In & Auth"
    case safety = "Safety & Terms"
    case compatibility = "Compatibility"
    case architecture = "Architecture"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .all: return "sparkles"
        case .privacy: return "lock.shield"
        case .auth: return "key.fill"
        case .safety: return "checkmark.shield"
        case .compatibility: return "macbook"
        case .architecture: return "cpu"
        }
    }
}

struct FAQSheetView: View {
    @Binding var isPresented: Bool
    @State private var selectedCategory: FAQCategory = .all
    @State private var expandedItemIDs: Set<String> = ["network-access"]

    private let faqItems: [FAQItem] = [
        // Privacy & Security
        FAQItem(
            id: "network-access",
            category: .privacy,
            question: "Does CodexSwitch connect to external servers or transmit my data?",
            answer: "No. CodexSwitch is 100% offline and local-only. It has zero network access capabilities, no analytics or telemetry SDKs, and no backend servers. It never connects to the internet or transmits data. All network traffic occurs exclusively between the official ChatGPT app and OpenAI servers."
        ),
        FAQItem(
            id: "data-stealing",
            category: .privacy,
            question: "Can CodexSwitch read, steal, or share my chat history or personal files?",
            answer: "No. CodexSwitch has zero access to your prompts, code snippets, chat history, or personal files. Your conversations reside strictly in ChatGPT local database and OpenAI cloud storage, which CodexSwitch treats as completely opaque. No data is ever read, recorded, or shared."
        ),
        FAQItem(
            id: "privacy-keychain",
            category: .privacy,
            question: "Does CodexSwitch access my macOS Keychain, passwords, or API keys?",
            answer: "Zero access. CodexSwitch never accesses your macOS Keychain, saved passwords, or API keys. Passwords and credentials stay encrypted inside macOS and ChatGPT sandboxed storage. CodexSwitch never prompts for or handles your credentials."
        ),
        FAQItem(
            id: "permissions",
            category: .privacy,
            question: "Does CodexSwitch require Accessibility, Screen Recording, or Admin rights?",
            answer: "None required. CodexSwitch runs entirely within standard user-space macOS permissions. It never asks for Accessibility permissions, Screen Recording rights, AppleScript automation, or root/administrator (sudo) privileges."
        ),
        FAQItem(
            id: "open-source",
            category: .privacy,
            question: "Is CodexSwitch open source and auditable?",
            answer: "Yes. CodexSwitch is 100% open source Swift code available on GitHub. You can inspect every line of code, review the architecture, or build the application from source code yourself to verify that no telemetry, network calls, or credential inspection exist."
        ),

        // Sign-In & Auth
        FAQItem(
            id: "how-signin-works",
            category: .auth,
            question: "How does the 'Sign In' process work within CodexSwitch?",
            answer: "When you click 'Sign In', CodexSwitch asks the bundled official codex app-server helper to generate an official OpenAI login URL. CodexSwitch opens this URL directly in your default macOS browser via standard system APIs (NSWorkspace). You authenticate directly on OpenAI official website (auth.openai.com). Upon completion, the browser communicates directly with the local helper over a local loopback callback, and CodexSwitch simply confirms the profile session is bound."
        ),
        FAQItem(
            id: "signin-credentials",
            category: .auth,
            question: "Will CodexSwitch be able to see or intercept my login credentials during sign-in?",
            answer: "No. You enter your credentials (email, password, Google/Apple SSO, or 2FA) exclusively in your own web browser on official OpenAI domains. CodexSwitch cannot capture keystrokes, intercept web forms, or inspect authentication tokens. It only receives an opaque confirmation signal from the local helper."
        ),
        FAQItem(
            id: "multi-account",
            category: .auth,
            question: "Can I use different OpenAI accounts (e.g. Work and Personal) on the same Mac?",
            answer: "Yes, that is the core purpose of CodexSwitch. Each profile maintains an entirely independent login session and storage folder. You can switch between your personal, team, and enterprise accounts in seconds without constantly logging out and re-authenticating."
        ),

        // Safety & Terms
        FAQItem(
            id: "binary-mod",
            category: .safety,
            question: "Does CodexSwitch modify the ChatGPT binary or inject code?",
            answer: "No. The official ChatGPT desktop app binary, memory space, and Apple/OpenAI code signatures remain 100% untouched. There is zero dynamic library injection (DYLD_INSERT_LIBRARIES), runtime memory hooking, or process tampering."
        ),
        FAQItem(
            id: "fair-use",
            category: .safety,
            question: "Can using CodexSwitch violate OpenAI's Terms of Service or get my account banned?",
            answer: "No. CodexSwitch operates strictly at the local macOS filesystem level by pointing ChatGPT to separate local configuration folders. All network requests, authentication tokens, and model interactions flow directly between official OpenAI servers and the official ChatGPT desktop app. No rate limits are bypassed, no API keys are spoofed, and no data is scraped."
        ),
        FAQItem(
            id: "data-paths",
            category: .safety,
            question: "Where are my profile files stored, and how do I delete a profile?",
            answer: "Managed profiles reside under ~/Library/Application Support/CodexSwitch/Profiles/<id>/, while the primary profile stays in its default macOS location (~/Library/Application Support/com.openai.codex). When a managed profile is removed, its folder is safely moved to the macOS Trash (~/.Trash)."
        ),

        // Compatibility
        FAQItem(
            id: "supported-versions",
            category: .compatibility,
            question: "Which macOS and ChatGPT versions are supported?",
            answer: "CodexSwitch supports macOS 14+ on Apple Silicon and Intel Macs. It supports official signed releases of the ChatGPT desktop application (bundle identifier com.openai.codex)."
        ),
        FAQItem(
            id: "app-updates",
            category: .compatibility,
            question: "What happens when ChatGPT receives an update from OpenAI?",
            answer: "When ChatGPT updates, CodexSwitch verifies its official Apple Team ID (2DC432GLL2) and bundle layout. Profile isolation continues working seamlessly across app updates without requiring manual re-configuration."
        ),

        // Architecture
        FAQItem(
            id: "isolation-storage",
            category: .architecture,
            question: "Are chat histories, cookies, or caches shared between profiles?",
            answer: "No. Each profile has a completely isolated directory structure containing its own codex-home, electron-data, and electron-cache. SQLite databases, cookies, session states, and disk caches are completely isolated with zero cross-profile leakage."
        ),
        FAQItem(
            id: "how-it-works",
            category: .architecture,
            question: "How does Profile Switching actually work behind the scenes?",
            answer: "Through an atomic 4-step handoff: (1) sends a graceful SIGTERM signal to ChatGPT, (2) waits for all background helpers and live conversation recorders to cleanly flush and exit, (3) switches the profile context pointer to the target directory, and (4) launches ChatGPT with the target profile root. ChatGPT is never force-terminated."
        ),
        FAQItem(
            id: "live-conversation",
            category: .architecture,
            question: "What happens if I switch profiles while a chat task or response is running?",
            answer: "CodexSwitch detects active conversation writer locks. If a task or conversation is actively running or holding an open recorder, CodexSwitch prompts you with an explicit warning so you can choose whether to wait for completion or confirm a handoff before switching."
        ),
        FAQItem(
            id: "crash-recovery",
            category: .architecture,
            question: "What happens if my Mac loses power or crashes during a profile switch?",
            answer: "Automatic rollback via an atomic Recovery Journal. If an interrupted switch is detected upon launch, all mutations are halted and the last verified committed profile state is restored automatically before allowing any new switches."
        )
    ]

    private var filteredItems: [FAQItem] {
        faqItems.filter { item in
            selectedCategory == .all || item.category == selectedCategory
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UITheme.Spacing.lg) {
                // Header Bar
                headerView

                // Category Filter Chips
                categoryFiltersView

                // Accordion Items
                accordionListView
            }
            .padding(.horizontal, UITheme.Spacing.windowPadding)
            .padding(.top, 32)
            .padding(.bottom, 24)
        }
        .ignoresSafeArea(.all, edges: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(alignment: .center) {
            Text("Frequently Asked Questions")
                .font(UITheme.Typography.appTitle)
                .foregroundStyle(.primary)

            Spacer()

            Button {
                withAnimation(UITheme.Animations.spring) {
                    isPresented = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.tactileCircleSecondary)
            .unfocusedControl()
            .instantTooltip("Close FAQ")
        }
    }

    // MARK: - Category Filters
    private var categoryFiltersView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(FAQCategory.allCases) { category in
                    Button {
                        withAnimation(UITheme.Animations.spring) {
                            selectedCategory = category
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: category.iconName)
                                .font(.system(size: 9))
                            Text(category.rawValue)
                                .font(UITheme.Typography.chip)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .foregroundStyle(selectedCategory == category ? Color.primary : Color.secondary)
                        .background(selectedCategory == category ? Color.primary.opacity(0.12) : Color.primary.opacity(0.03))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(selectedCategory == category ? Color.primary.opacity(0.20) : Color.primary.opacity(0.06), lineWidth: 0.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .unfocusedControl()
                }
            }
        }
    }

    // MARK: - Accordion Cards
    private var accordionListView: some View {
        VStack(spacing: 8) {
            ForEach(filteredItems) { item in
                faqCard(for: item)
            }
        }
    }

    private func faqCard(for item: FAQItem) -> some View {
        let isExpanded = expandedItemIDs.contains(item.id)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(UITheme.Animations.spring) {
                    if isExpanded {
                        expandedItemIDs.remove(item.id)
                    } else {
                        expandedItemIDs.insert(item.id)
                    }
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    Text(item.question)
                        .font(UITheme.Typography.cardTitle)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(isExpanded ? Color.primary : Color.secondary.opacity(0.6))
                }
                .padding(.horizontal, UITheme.Spacing.cardPaddingHorizontal)
                .padding(.vertical, UITheme.Spacing.cardPaddingVertical)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .unfocusedControl()

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .opacity(0.4)
                        .padding(.horizontal, UITheme.Spacing.cardPaddingHorizontal)

                    Text(item.answer)
                        .font(UITheme.Typography.appSubtitle)
                        .lineSpacing(3)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, UITheme.Spacing.cardPaddingHorizontal)
                        .padding(.bottom, UITheme.Spacing.cardPaddingVertical)
                        .padding(.top, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardSurface(radius: UITheme.Radius.card)
    }
}
