# Architecture

## Boundary

CodexSwitch owns profile selection and process lifecycle. The official ChatGPT desktop application and the bundled Codex app-server own authentication, conversations, and account behavior. CodexSwitch does not implement an OAuth client, token broker, traffic proxy, application patch, symlink swap, or live-state copy.

## Profile model

Profile A adopts the existing paths exactly:

```text
~/.codex
~/Library/Application Support/Codex
~/Library/Caches/Codex
```

Managed profiles live below:

```text
~/Library/Application Support/CodexSwitch/Profiles/<UUID>/
├── codex-home/
├── electron-data/
└── electron-cache/
```

The profile document stores UUID, user label, paths, storage ownership, an identity hash, validation date, validated app version, and compatibility records. Legacy free-form validation messages are discarded during schema-v2 migration. Schema v3 maps legacy `unverified`/`supported`/`unsupported` records to `provisional`/`verified`/`blocked` and can store a provisional acknowledgement. Profile A’s paths are immutable; managed roots must be exact siblings below their UUID directory.

Every existing path component is checked for symlinks and canonical containment before access. Profile-local `config.toml` is updated to top-level `cli_auth_credentials_store = "file"`; an existing file is backed up before modification.

## Authentication

For a selected profile, CodexSwitch starts the bundled `codex app-server` with that profile’s `CODEX_HOME`, sends `initialize`, then sends the required `initialized` notification before `account/login/start`. It requests the app-server’s local success page with `useHostedLoginSuccessPage = false`; this avoids the hosted page’s unrelated **Open ChatGPT** deep link, which can launch the ordinary desktop app outside the selected profile roots. The returned HTTPS OpenAI/ChatGPT URL is opened through `NSWorkspace` using the macOS default browser.

`AuthenticationCompletionMonitor` accepts either a matching successful `account/login/completed` event or a post-start `account/updated` event whose authentication mode is ChatGPT. Both events are triggers only: the profile is bound after `account/read` returns a usable identity and its hash matches an existing binding. Account reads are retried for up to ten seconds after an event because credential persistence can lag the notification. A fresh unbound profile also performs a one-second bounded read fallback while the overall ten-minute callback deadline remains active. Bound-profile re-authentication does not poll without a post-start event, preventing old credentials from silently completing a new attempt. **Check Sign-in Now** performs the same verified read against the active profile-local helper.

Stdout has one nonblocking JSONL reader built on `availableData`; its actor-owned router buffers raw bytes through line boundaries, correlates responses by request ID, and queues notifications by method/login ID. This avoids the prior failure where a blocking 64 KiB read waited for EOF while the app-server held stdout open. A 15-second helper-response deadline applies during initialization/login URL acquisition; the browser callback deadline is ten minutes. Stderr is drained only to prevent blockage and contributes only an exit status and presence flag to diagnostics.

Authentication progress is emitted by `AuthenticationCoordinator`: `preparing`, `requestingLoginURL`, `openingBrowser`, `awaitingCallback`, then `verifying`. The management UI never claims to open a browser until a validated URL exists and `NSWorkspace` has accepted it. The affected profile row displays the same state, including the terminal verified result. While a login is pending, the same validated URL can be reopened or the account can be checked without starting another ChatGPT process. Diagnostics record fixed event/read stage names only; URL contents, helper payloads, credentials, and account identity material never enter logs or persisted documents.

## Process boundary

`DarwinProcessSnapshotProvider` resolves the signed `com.openai.codex` application and walks its native process tree. Only the main app and account-bearing descendants are considered active. Detached `browser_crashpad_handler` processes are excluded from quit decisions and audited during compatibility validation because they can outlive the main app. Native `KERN_PROCARGS2` parsing treats the executable-path prefix, the `argc` argv sequence, and the following environment as three distinct regions. This is required to retain the final cache-root argument instead of misclassifying argv boundaries.

Exact `--user-data-dir`, `--disk-cache-dir`, and profile environment roots are extracted from process metadata. An ambiguous or externally launched session blocks switching rather than guessing.

The immutable adopted Profile A has one narrow default-cache exception for an ordinary signed ChatGPT launch. An absent `--disk-cache-dir` is classified as `implicitAdoptedDefault` only when the main process arguments were read successfully, no explicit cache override is present, no conflicting cache root was observed, and the profile cache path is exactly `~/Library/Caches/Codex`. Managed profiles always require an explicit cache root. Missing process metadata never qualifies as implicit evidence.

Transaction code crosses one narrow process-lifecycle seam: inspect the current session, gracefully quit it, or launch and confirm a profile. The AppKit/Darwin adapter owns native process mechanics; deterministic tests use an in-memory adapter through the same interface.

## Transaction

Switching is serialized by an operation lock and journal:

```text
preflight
→ resolve and confirm source
→ detect a live conversation writer
→ require per-switch confirmation when one is present (no journal yet)
→ rerun the complete preflight after confirmation
→ verify target identity and roots (non-mutating)
→ persist recovery journal
→ gracefully quit source
→ confirm account-bearing processes and the source writer exited
→ launch target
→ confirm target roots
→ commit
```

The target is never committed until identity, app signature/version, and runtime roots match. A pending journal blocks every new launch or switch so an interrupted transaction cannot be overwritten. Failed launches enter an explicit rollback phase, gracefully close a partial target, and restore the last committed profile from an uncancelled cleanup task. A successful rollback re-commits the source and clears the journal; a failed rollback leaves the journal for recovery.

A live writer lock means that an open Codex thread recorder owns the writer guard; it can remain held after a response completes and is not an activity signal. This follows the [official Codex writer-lock lifetime](https://github.com/openai/codex/blob/main/codex-rs/thread-store/src/local/writer_lock.rs). Before confirmation, the transaction returns a typed handoff-required result without persisting a recovery journal, quitting ChatGPT, exposing the lock filename, or changing validation history. Confirmation applies to one switch only and warns that a running response or tool may be interrupted.

After confirmation, the transaction reruns the complete preflight so stale authorization or process evidence cannot be reused. It then verifies the target, persists the journal, requests graceful source termination, and waits for both account-bearing processes and the source writer to exit. If graceful termination times out, the writer remains held, or the source cannot be closed safely, the target never launches. The existing rollback path restores the exact committed source and clears the journal when restoration succeeds; otherwise the recovery journal remains and further switching is disabled. ChatGPT and its helpers are never force-killed.

Startup recovery first inspects the live process and fails closed if inspection is ambiguous. An already-restored source is accepted without a quit/relaunch cycle. A live, uncommitted target is gracefully closed before the source is restored. The UI exposes a retry action, but never launches over unresolved recovery state.

## Compatibility

Compatibility is recorded per ChatGPT version, bundle ID, and team ID as `provisional`, `verified`, or `blocked`. A newly seen official build is provisional. Its profiles remain selectable, but the first launch or switch requires a persisted acknowledgement for that exact installed-app identity. A version, bundle, or signing-team change cannot inherit the acknowledgement. Verified builds completed the optional human guided diagnostic; blocked builds cannot launch or switch.

`CompatibilityPolicy` is the single decision seam for the model and transaction. It returns allowed, acknowledgement-required, or blocked. The UI may collect acknowledgement, but the transaction independently reads the persisted record before process mutation, so a caller cannot bypass policy. Provisional and verified operations otherwise follow the same identity verification, structural preflight, process mapping, journal, graceful handoff, target-root confirmation, and rollback path.

Guided isolation is an advanced diagnostic, not an authorization bypass. Its ephemeral session remains pinned to the current version, bundle ID, signing team, and exactly two identity-bound profiles. The committed source must remain running and expose its roots before the next diagnostic transition; a disappeared or remapped process invalidates only the session and transition history, not an existing provisional acknowledgement. Only committed transitions count toward the ten required alternations. Recording verified compatibility performs one final live root and identity confirmation; confirmed state escape records the build as blocked.

The diagnostic session is issued only after a serialized preparation step validates the two-profile set, committed profile, signed installation, identity bindings, roots, and live process mapping. An open live conversation does not block preparation. If ChatGPT is absent, preparation verifies and launches the committed profile with controlled roots. A controlled shutdown inside a journaled, confirmed handoff is part of the diagnostic transition. Fixed-category telemetry distinguishes source absence, ambiguous mapping, committed-source mismatch, changed session identity, live-writer confirmation, live-writer release failure, target preflight, and target identity without logging profile or account material.

## Application lifecycle

The app uses regular activation so it appears in the Dock and Force Quit list, while `MenuBarExtra` remains the quick-switch surface. One uniquely identified SwiftUI `Window` owns setup, browser-auth progress, diagnostics, recovery, sanitized status, and native confirmations. It is the primary scene so launch creates it deterministically. Dock reopens and menu-bar confirmation requests foreground that same scene instead of creating a panel. The narrow AppKit presenter moves an existing restored management window to the active macOS Space before ordering it front; this handles a closed/off-Space restoration record without disabling primary-window restoration. The staged bundle has stable metadata, `LSMultipleInstancesProhibited`, and a local ad-hoc signature verified after all resources are copied. The run verifier opens the bundle repeatedly and requires exactly one process and one stable visible management window.

SwiftUI rendering reads only cached application identity and compatibility values. Signed-app discovery and `codesign` subprocesses run at explicit model refresh boundaries, never from a view-dependent computed property. Startup work begins from the window task rather than the `@State` model initializer, and presentation controls use native state bindings without mutation in binding getters or presentation evaluation. The run verifier holds the single process and window through a 30-second idle soak so delayed AttributeGraph aborts fail the build check.
