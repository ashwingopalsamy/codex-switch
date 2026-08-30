# Implementation Status

Updated: 2026-08-16

## Implemented

- Profile-local app-server browser authentication with verified `account/read` completion, identity binding, sanitized diagnostics, and no credential or account-material logging.
- Immutable adopted roots, managed sibling-root containment, symlink rejection, file-backed credential configuration, native process mapping, and explicit managed cache evidence.
- Serialized switching with target preflight, live-conversation confirmation, graceful source shutdown, writer release, recovery journal, exact target-root confirmation, commit, and uncancelled rollback.
- Regular Dock + menu-bar lifecycle, one management window, cached app identity, single-instance bundle metadata, strict local signing, and delayed idle-window verification.
- Schema-v3 compatibility records with `provisional`, `verified`, and `blocked` states. Legacy `unverified`, `supported`, and `unsupported` values migrate without losing their meaning.
- Direct provisional compatibility allowing official signed ChatGPT builds to switch out-of-the-box without extra modal confirmation.
- Live process mapping with support for implicit adopted default roots (user data, cache, and codex home) and automatic active profile state inference in `AppModel`.
- A centralized compatibility-policy module used by both `AppModel` and `SwitchTransaction`; blocked builds remain safely rejected before process mutation.
- Guided isolation moved to Advanced diagnostics. Its exact-build/two-profile session adds continuity and transition-counting checks. Completion records verified; confirmed leakage records blocked.
- The management and menu-bar UI reflect true running active profile state dynamically, while retaining the independent per-switch live-conversation handoff.
- The existing AppKit window presenter moves a restored management window to the active macOS Space before ordering it front, fixing a baseline case where the process and window existed but the window remained off-Space.
- The sanitized status probe reports compatibility state without printing identity hashes, paths, or account data.

## Current evidence

The user confirmed that profile switching across versions operates reliably and requested streamlining the one-time provisional banner as well as improving active profile state inference from running processes.

The test suite covers legacy status migration, compatibility-policy decisions, direct provisional switching, running process profile inference, native implicit adopted default roots, cancellation without journal/process/profile mutation, blocked-build rejection, and guided diagnostics. Existing authentication, root-isolation, handoff, rollback, recovery, and diagnostic-continuity coverage remains in place.

The complete local matrix passed: `swift build`, `swift test` (69 tests), fixture/app/process/continuity/status/auth probes, repeated-open `./script/build_and_run.sh --verify` with its 30-second idle-window soak, strict bundle signature verification, and `git diff --check`.

## Compatibility behavior

- **Provisional:** Normal protected switching is enabled directly. Every identity, root, process, writer, journal, and rollback invariant still applies.
- **Verified:** Optional guided diagnostics completed for the exact app identity; normal switching uses the same transaction.
- **Blocked:** Launch and switching are disabled for that exact app identity.
- **App update or signing change:** Newly seen builds start provisional and switch directly with full isolation.

## Next action

Use the staged application and choose either profile. Switching operates directly without provisional acknowledgement banners. If a live conversation is open, the separate **Close ChatGPT and Switch** confirmation appears for that individual handoff.

## Review handoff

Read these files in order:

1. [architecture.md](architecture.md) for profile, compatibility-policy, and transaction invariants.
2. `Core/Services/CompatibilityPolicy.swift` and `Core/Models/Profile.swift` for schema-v3 compatibility state.
3. `Core/Services/SwitchTransaction.swift` and `App/AppModel.swift` for independent enforcement and live-process inference.
4. [validation.md](validation.md) for automated checks and optional real-account diagnostics.
