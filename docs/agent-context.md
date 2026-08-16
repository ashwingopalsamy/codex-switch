# Agent context

This document is the deep reference for an agent working on CodexSwitch. It explains the boundaries that are easy to miss when a task looks like a small UI, process, or authentication change. The existing subsystem documents remain authoritative; this file connects them into one execution model.

## Product boundary

CodexSwitch is a local macOS 14+ SwiftPM utility. It selects one identity-bound profile for the official ChatGPT desktop application. The utility owns profile selection, root construction, process inspection, graceful lifecycle, recovery, and management UI. ChatGPT and its bundled Codex app-server own authentication, conversations, and account behavior.

CodexSwitch does not:

- implement an OAuth client or token broker;
- proxy ChatGPT traffic;
- patch or inject into the official application;
- copy live conversation or credential state between profiles;
- swap roots through symlinks;
- force-kill ChatGPT or account-bearing helpers.

The safest change is usually a narrower seam, a typed outcome, and a deterministic test rather than a new fallback.

## Vocabulary and ownership

Use the terms in CONTEXT.md in code, docs, tests, and reports:

- A profile is a named set of Codex home, Electron user-data, and Electron cache roots.
- The adopted profile uses ChatGPT's existing default roots. Its paths are immutable.
- A managed profile owns three sibling roots below CodexSwitch application support.
- An identity-bound profile has a verified opaque identity hash.
- The committed profile is the last profile whose identity and runtime roots were confirmed.
- A live conversation writer is an open Codex live-thread recorder. It can outlive a response and is not an activity indicator.
- A confirmed live-session handoff is one explicit, per-switch permission to gracefully close ChatGPT, wait for source shutdown, and launch the target.
- A validated transition is a committed root-confirmed change between the two authorized profiles.
- A compatibility record is a human conclusion for one exact installed ChatGPT identity.

Do not rename these concepts to account, active work, busy writer, force switch, or automated support result. Those terms hide the safety boundaries.

## Repository map

| Area | Responsibility | Typical entry points |
| --- | --- | --- |
| App | SwiftUI application lifecycle, menu-bar item, management window, status and confirmation presentation | App/AppModel.swift, App/Views/SettingsView.swift |
| Core/Models | Codable domain values and typed state/outcomes | Core/Models/Profile.swift, GuidedValidation.swift, Authentication.swift |
| Core/Services | Process, authentication, configuration, transaction, compatibility, and writer-lock seams | Core/Services/ |
| Core/Stores | Durable profile and compatibility records | Core/Stores/ProfileStore.swift |
| Core/Support | Application paths, hashing, logging, and shared support | Core/Support/ |
| Probe | Sanitized fixture, app, process, continuity, status, and auth diagnostics | Probe/main.swift |
| Tests | Deterministic fake-server, process, profile, validation, handoff, and UI-model coverage | Tests/ |
| Resources | Bundle metadata and Icon Composer input | Resources/ |
| script | Local build, packaging, signing, repeated-open, and idle-soak verifier | script/build_and_run.sh |
| docs | Architecture, validation, status, domain language, and agent navigation | docs/ |

Read the owning file before changing an invariant. Do not use a probe as a substitute for reading the service it exercises.

## Profile isolation boundary

Profile A adopts exactly:

    ~/.codex
    ~/Library/Application Support/Codex
    ~/Library/Caches/Codex

Managed profiles use exact sibling roots below:

    ~/Library/Application Support/CodexSwitch/Profiles/<UUID>/
    ├── codex-home/
    ├── electron-data/
    └── electron-cache/

ProfileStore owns profile documents and schema migration. AppPaths owns safe construction and containment checks. Every path component is checked for symlinks and canonical containment before use. Managed roots cannot escape their UUID directory. Profile A is never moved, replaced, or deleted by a switch.

LaunchContext carries the selected profile. LaunchEnvironment derives a sanitized environment and strips credential variables. CodexConfigManager makes profile-local credential storage explicit and backs up an existing config before changing it. These layers must stay separate: path construction must not read credentials, and process inspection must not mutate profile state.

## Authentication boundary

Authentication uses the bundled profile-local app-server:

1. Launch the helper with the selected CODEX_HOME.
2. Send initialize.
3. Send the required initialized notification.
4. Request account/login/start with the local success-page option.
5. Open only the validated HTTPS OpenAI/ChatGPT URL through the macOS default browser.
6. Wait for a typed completion or account-update trigger.
7. Verify the identity through account/read, with bounded retries for persistence lag.
8. Bind or re-bind the opaque identity hash only after that verified read.

The browser page and events are triggers, not proof. A fresh profile may use the bounded account-read fallback described in architecture.md; an already-bound profile must not silently accept stale credentials. AuthenticationCompletionMonitor and the actor-owned JSONL router must preserve request correlation, split-line handling, bounded deadlines, and cancellation.

Diagnostics may report fixed stage names such as preparing, requestingLoginURL, openingBrowser, awaitingCallback, and verifying. They must not contain URLs, helper payloads, tokens, cookies, account identifiers, hashes, or conversation text. The email may be shown transiently in the current verification result only.

When changing authentication, read the Authentication section of architecture.md, inspect AppServerClient.swift, update tests, and run the auth probe. Never make ordinary ChatGPT launch depend on browser storage or a hosted success-page deep link.

## Process evidence boundary

DarwinProcessSnapshotProvider resolves the signed ChatGPT bundle and observes its native process tree. It distinguishes:

- the main signed application;
- account-bearing descendants that must be considered for lifecycle decisions;
- detached crash reporters, which are audited separately and never force-terminated.

KERN_PROCARGS2 contains executable-path data, the argc/argv sequence, and the following environment. Parse those regions separately. Exact user-data, cache, and CODEX_HOME roots must be extracted from the correct source. An ambiguous or externally launched session fails closed.

The adopted profile has one narrow implicit-cache exception: an omitted disk-cache argument qualifies only when main arguments are readable, no explicit or conflicting cache root is present, and the exact adopted default cache is otherwise evidenced. Managed profiles always require explicit cache evidence.

CodexProcessController is the lifecycle seam. Deterministic tests use an in-memory adapter through the same interface as the native implementation. Do not add a shell-only process shortcut that bypasses the typed evidence model.

## Switch transaction state machine

SwitchTransaction serializes work with OperationLock and protects recovery with RecoveryJournal. The normal sequence is:

    preflight
    -> resolve and confirm committed source
    -> inspect live writer
    -> return handoff-required before mutation when confirmation is absent
    -> rerun complete preflight after confirmation
    -> verify target identity and roots
    -> persist recovery journal
    -> gracefully quit source
    -> wait for account-bearing processes and source writer to exit
    -> launch target
    -> confirm target identity and roots
    -> commit

The live writer represents the recorder lifetime, so it may remain after a response completes. Confirmation is required for every affected switch and is consumed once. Before confirmation there is no quit, launch, journal, commit, or validation-history mutation. Repeated UI requests must not create duplicate transactions.

After confirmation, preflight runs again because process evidence, authorization, or installed-app identity may have changed. The target is never launched until the exact target identity and roots are verified. ChatGPT termination is graceful only. If the source cannot exit, the writer remains held, or the timeout expires, do not escalate. Restore the exact committed source when possible. A successful rollback clears the journal and preserves guided validation; an unresolved rollback leaves recovery pending and disables further switching.

An already-restored source is accepted during recovery without an unnecessary relaunch. A partial target is gracefully closed before source restoration. A pending journal must never be overwritten by a new transaction.

## Guided validation and compatibility

Guided validation is an ephemeral authorization, not a permanent bypass. It is pinned to:

- one installed ChatGPT bundle identity, version, and signing team;
- exactly two identity-bound profiles;
- the committed source and its confirmed roots.

Preparation checks the signed installation, profile pair, identity bindings, roots, and live committed source. It may safely launch the committed source when ChatGPT is absent. An open live conversation does not block preparation. A controlled shutdown inside a journaled confirmed handoff is part of the authorized transition.

External source disappearance, root remapping, ambiguous process evidence, or installed-app identity changes clear authorization and transition history. Only a committed root-confirmed transition increments the count. No-op selections, failed launches, cancellations, and recovery failures do not increment it.

Automated fixtures establish code behavior only. The compatibility record stays unverified until a human alternates two real accounts, inspects distinct canaries and conversation persistence, and records the exact installed app identity. Never describe the current status as supported based only on tests or probes.

## UI and lifecycle contracts

CodexSwitch is a regular Dock application with a menu-bar item. One uniquely identified SwiftUI management Window owns setup, authentication progress, validation, recovery, status, and live-session confirmation.

The menu-bar path must foreground that existing window when confirmation is required. It must not create a second panel. Dock reopen orders the same titled window forward. App identity and codesign discovery are refreshed explicitly and cached; view evaluation must remain side-effect free. Do not perform subprocesses or mutable model work in computed view properties, binding getters, or presentation evaluation.

The packaged bundle must preserve its stable bundle identifier, regular activation metadata, single-instance policy, icon resources, and local signature. The script verifier opens repeatedly and requires one process and one stable visible management window before the idle soak.

## Safe change procedure

Before editing:

1. Check git status and identify unrelated work.
2. Read the branch-specific architecture and validation sections.
3. Locate the current source of truth instead of copying stale text into a new document.
4. State the invariant and the smallest seam that can enforce it.

While editing:

1. Keep sensitive material opaque.
2. Add a typed outcome for a new failure state.
3. Add a deterministic regression test before or with the behavior change.
4. Preserve the distinction between controlled handoff and external invalidation.
5. Update the owning docs in the same change.

Before reporting completion:

1. Run the relevant probe and test subset.
2. Run the complete matrix in verification-matrix.md.
3. Inspect staged paths and git diff --check.
4. Search new diagnostics and docs for sensitive terms and values.
5. State what is automated, what is manually validated, and what remains unverified.
