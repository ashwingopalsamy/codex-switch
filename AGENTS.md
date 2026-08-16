# CodexSwitch agent contract

This file is the always-loaded operating contract for work in this repository. Follow it before editing, testing, committing, or reporting a compatibility result. The project is a SwiftPM macOS 14+ utility that launches the signed ChatGPT desktop app with profile-local roots.

## Read by branch

- Profile roots, process evidence, switching, recovery, or live conversations: read [docs/architecture.md](docs/architecture.md) and [docs/agent-context.md](docs/agent-context.md).
- Guided validation, probes, real-account evidence, or compatibility claims: read [docs/validation.md](docs/validation.md) and [docs/status.md](docs/status.md).
- Authentication, browser callbacks, account binding, or identity handling: read the Authentication section of [docs/architecture.md](docs/architecture.md), inspect Core/Services/AppServerClient.swift, and run the auth probe.
- SwiftUI windows, menu-bar behavior, packaging, or launch verification: inspect the relevant App files and script/build_and_run.sh.
- Tests, CI, issue reports, or pull requests: read [CONTRIBUTING.md](CONTRIBUTING.md), [docs/verification-matrix.md](docs/verification-matrix.md), and the applicable .github template.
- Domain terminology: read [CONTEXT.md](CONTEXT.md). Preserve its preferred terms.

Use [docs/index.md](docs/index.md) when the task crosses more than one branch. Existing architecture, validation, and status documents are authoritative for their subjects; agent-facing documents explain how to navigate them and must not silently replace them.

## Non-negotiable invariants

- Profile roots are the security boundary. Preserve the adopted profile's existing paths exactly. Keep managed roots below CodexSwitch application support, reject traversal and symlink components, and pass profile context through argument arrays and sanitized environment dictionaries.
- Authentication belongs to the official profile-local app-server/browser flow. Treat tokens, cookies, authentication URLs, identity hashes, emails, helper payloads, and private conversations as opaque. Never print, decode, copy, persist, or add them to diagnostics or documentation.
- The typed completion boundary is a verified account/read; a browser success page or event alone is not proof of identity.
- A live writer means an open Codex conversation recorder, not necessarily active model work. A confirmed handoff must gracefully close ChatGPT, wait for account-bearing processes and the writer to exit, and only then launch and commit the target. Never force-terminate ChatGPT or its account-bearing helpers.
- Detached crash reporters are classified separately and are never used as a reason to force-quit.
- A pending recovery journal blocks new launches and switches. Restore the exact committed source before clearing it.
- Automated fixtures do not prove real two-account isolation. Newly seen official ChatGPT builds start as provisional and require one explicit acknowledgement; keep verified compatibility status unconfirmed until the optional guided, conversation-bearing human diagnostic passes for the exact installed app identity.
- A controlled shutdown inside a journaled confirmed handoff does not invalidate guided diagnostics. External source loss, root remapping, ambiguous process evidence, or installed-app identity changes do invalidate it.

## Work loop

1. Inspect the current worktree and preserve unrelated changes.
2. Read the branch-specific documents above before changing behavior.
3. Make the smallest change that preserves the invariants and source-of-truth boundaries.
4. Add or update deterministic tests for every changed failure mode.
5. Run the relevant checks from [docs/verification-matrix.md](docs/verification-matrix.md), then run the complete matrix before claiming completion.
6. Review git diff --check, sensitive-output risk, staged paths, and documentation links.
7. Report exact commands, results, manual gates, and any remaining uncertainty. Do not infer compatibility from a passing fixture.

## Required local checks

Run from the repository root:

~~~bash
swift build
swift test
swift run CodexSwitchProbe fixture
swift run CodexSwitchProbe app
swift run CodexSwitchProbe process
swift run CodexSwitchProbe continuity 10
swift run CodexSwitchProbe status
swift run CodexSwitchProbe auth
./script/build_and_run.sh --verify
codesign --verify --deep --strict --verbose=2 dist/CodexSwitch.app
git diff --check
~~~

script/build_and_run.sh creates a local ad-hoc signature and verifies one foreground process, one management window, repeated open requests, and a delayed idle soak. It is not a Developer ID or notarization check. CodexSwitchProbe auth uses a temporary profile root and redacts its URL; it does not establish account isolation.

`CodexSwitchProbe status` is a read-only, sanitized readiness check. It prints only configured/bound counts, active storage class, compatibility state, whether provisional use was acknowledged, recovery presence, and whether the active profile has an open live conversation. `CodexSwitchProbe process` additionally reports whether the running app maps to exactly one known profile, its storage class, and whether cache evidence is explicit or the verified implicit adopted default. `CodexSwitchProbe continuity [samples]` repeats the committed-source mapping 1–100 times and fails on process loss, restart, ambiguity, or committed-profile divergence. `CodexSwitchProbe soak [seconds]` holds that exact mapping and main PID under observation for 1–600 seconds and additionally fails on a new recovery journal. None of these commands prints identity hashes or root paths.

## Git and repository safety

- Keep application code, credentials, profile data, .build/, dist/, and .DS_Store out of documentation commits unless the task explicitly changes tracked source.
- Do not reset, force-push, rewrite history, or overwrite another repository's .git directory.
- Prefer grouped commits with imperative messages. Keep a source-preservation commit separate from documentation or policy changes.
- Never claim a remote deployment, GitHub setting, security-channel availability, or manual two-account result without verifying it.
- CLAUDE.md is a compatibility pointer to this file; do not create a second conflicting instruction system. Personal CLAUDE.local.md files remain untracked.

Completion means the requested source and documentation changes are present, all intended tests/checks have passed, sensitive material is absent, the worktree is clean, and manual-only gates are clearly reported.
