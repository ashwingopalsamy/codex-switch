# Implementation Status

Updated: 2026-08-16

## Implemented

- Profile-local app-server browser authentication with verified `account/read` completion, identity binding, sanitized diagnostics, and no credential or account-material logging.
- Immutable adopted roots, managed sibling-root containment, symlink rejection, file-backed credential configuration, native process mapping, and explicit managed cache evidence.
- Serialized switching with target preflight, live-conversation confirmation, graceful source shutdown, writer release, recovery journal, exact target-root confirmation, commit, and uncancelled rollback.
- Regular Dock + menu-bar lifecycle, one management window, cached app identity, single-instance bundle metadata, strict local signing, and delayed idle-window verification.
- Schema-v3 compatibility records with `provisional`, `verified`, and `blocked` states. Legacy `unverified`, `supported`, and `unsupported` values migrate without losing their meaning.
- One-time provisional acknowledgement pinned to the exact ChatGPT version, bundle identifier, and signing team. A new app identity asks again.
- A centralized compatibility-policy module used by both `AppModel` and `SwitchTransaction`; the transaction independently rejects unacknowledged provisional or blocked builds before process mutation.
- Guided isolation moved to Advanced diagnostics. Its exact-build/two-profile session adds continuity and transition-counting checks but cannot bypass compatibility policy. Completion records verified; confirmed leakage records blocked.
- The management and menu-bar UI keep profiles selectable in provisional state, foreground one native acknowledgement when required, preserve cancellation without mutation, and retain the independent per-switch live-conversation handoff.
- The existing AppKit window presenter moves a restored management window to the active macOS Space before ordering it front, fixing a baseline case where the process and window existed but the window remained off-Space.
- The sanitized status probe reports compatibility state and acknowledgement presence without printing identity hashes, paths, or account data.

## Current evidence

The user has now confirmed that the adopted and managed profiles switch seamlessly and retain distinct profile behavior. That human result motivated removal of Guided Validation as the normal switching gate. Because the earlier diagnostic history was ephemeral and no verified compatibility record was persisted, the current exact ChatGPT build is migrated truthfully to provisional rather than silently relabeled verified.

The new regressions cover legacy status migration, compatibility-policy decisions, exact-build acknowledgement, cancellation without journal/process/profile mutation, acknowledged provisional switching through the ordinary transaction, blocked-build rejection, and the rule that guided diagnostics cannot bypass provisional acknowledgement. Existing authentication, root-isolation, handoff, rollback, recovery, and diagnostic-continuity coverage remains in place.

The complete local matrix passed for ChatGPT `26.810.52044` signed by team `2DC432GLL2`: `swift build`, `swift test` (67 tests), fixture/app/process/continuity/status/auth probes, repeated-open `./script/build_and_run.sh --verify` with its 30-second idle-window soak, strict bundle signature verification, and `git diff --check`. The live process mapped exactly to the adopted profile with explicit cache evidence; compatibility is provisional and not yet acknowledged, recovery is clear, and the active profile has an open live conversation.

## Compatibility behavior

- **Provisional, not acknowledged:** Profiles are selectable; the first launch or switch presents one exact-build explanation. Cancel leaves all state unchanged.
- **Provisional, acknowledged:** Normal protected switching is enabled. Every identity, root, process, writer, journal, and rollback invariant still applies.
- **Verified:** Optional guided diagnostics completed for the exact app identity; normal switching uses the same transaction.
- **Blocked:** Launch and switching are disabled for that exact app identity.
- **App update or signing change:** Prior acknowledgement and verification do not carry forward; the newly seen build starts provisional.

## Next action

Use the staged application and choose either profile. For the current provisional build, confirm **Allow for This Version** once, then verify that subsequent switches no longer require Guided Diagnostics. If a live conversation is open, the separate **Close ChatGPT and Switch** confirmation should still appear for that individual handoff.

## Review handoff

Read these files in order:

1. [architecture.md](architecture.md) for profile, compatibility-policy, and transaction invariants.
2. `Core/Services/CompatibilityPolicy.swift` and `Core/Models/Profile.swift` for schema-v3 compatibility state.
3. `Core/Services/SwitchTransaction.swift` and `App/AppModel.swift` for independent enforcement and acknowledgement flow.
4. [validation.md](validation.md) for automated checks and optional real-account diagnostics.
