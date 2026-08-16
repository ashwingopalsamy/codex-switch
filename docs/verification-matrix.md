# Verification matrix

Use this matrix to choose evidence and to report it accurately. A passing command proves only the boundary it exercises. No automated command proves two-account isolation.

## Deterministic local checks

Run from the repository root.

| Command | Proves | Side effects and privacy |
| --- | --- | --- |
| swift build | All SwiftPM targets compile for the installed toolchain | Writes ignored .build artifacts; no credentials |
| swift test | XCTest regressions, including authentication, process parsing, recovery, guided validation, and live handoff | Writes temporary fixtures and ignored test artifacts |
| swift run CodexSwitchProbe fixture | Profile persistence and launch-environment fixture isolation | Uses temporary roots; prints no identity material |
| swift run CodexSwitchProbe app | Installed signed ChatGPT bundle structure and version/team metadata | Read-only; runtime root isolation remains manual |
| swift run CodexSwitchProbe process | Native process-tree classification and exact root evidence | Read-only sanitized process inspection; never prints identity hashes or root paths |
| swift run CodexSwitchProbe continuity 10 | Repeated committed-source mapping without process loss or divergence | Observes the running app; use only when the source session may remain active |
| swift run CodexSwitchProbe status | Sanitized configured/bound counts, active storage class, compatibility, recovery, and live-writer state | Read-only; no credentials or account identifiers |
| swift run CodexSwitchProbe auth | Profile-local app-server handshake and redacted approved browser URL | Uses a temporary profile and cancels; does not open a browser or bind an account |
| ./script/build_and_run.sh --verify | Packaging, regular activation, one process, one management window, repeated opens, and delayed idle survival | Rebuilds ignored dist output, signs ad hoc, and launches/terminates only CodexSwitch |
| codesign --verify --deep --strict --verbose=2 dist/CodexSwitch.app | Bundle signature and designated requirement validity | Read-only verification |
| git diff --check | Whitespace cleanliness | Read-only |
| git fsck --full | Git object integrity | Read-only |

The complete local matrix is:

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
git fsck --full
~~~

The shell startup warning about a missing optional cargo environment is unrelated to this SwiftPM project; report it only if it changes a command's exit status.

## Test interpretation

The XCTest suite uses fake app-server sessions, temporary profile roots, process fixtures, and an in-memory lifecycle adapter. Important behavior covered includes:

- initialize, initialized, login-start ordering and nonblocking JSONL framing;
- verified account-read completion, delayed readability, stale-bound protection, cancellation, timeout, and safe browser progress;
- root containment, adopted-path immutability, sibling managed roots, symlink rejection, environment sanitization, and TOML updates;
- native argv/environment boundaries, cache evidence, account-bearing process classification, and detached crash reporters;
- pending journal exclusion, already-restored recovery, target failure rollback, cancellation-safe cleanup, and fail-closed ambiguity;
- guided-validation authorization, committed-source requirements, external invalidation, open-live-writer preparation, and transition history;
- unconfirmed handoff no-op behavior, one-time confirmation, graceful quit, writer release, timeout rollback, and target launch gating;
- regular activation, single-instance window behavior, and cached side-effect-free UI model state.

When a test passes, report the behavior it proves. Do not turn a fixture result into a real-account compatibility claim.

## Human acceptance gate

The following evidence cannot be automated safely:

1. Bind two real accounts through the official browser flow.
2. Start guided validation for the exact installed ChatGPT bundle identity.
3. Create distinct harmless canary threads and settings in both accounts.
4. Alternate at least ten times, confirming every live-conversation handoff and allowing the source writer to release.
5. Cancel one confirmation and verify the source and transition count remain unchanged.
6. Start or complete a response in each account and repeat the handoff in both directions.
7. Inspect conversation persistence, account-specific canaries, settings, notification groups, cache behavior, keychain boundaries, crash reports, and shared repository access.
8. Run the 120-second sanitized soak while the managed profile is active.
9. Record support only after every check passes. Otherwise mark the installed version unsupported or leave it unverified.

External Force Quit, source disappearance, root remapping, ambiguous process evidence, and installed-app changes are invalidation events. A controlled shutdown in a journaled confirmed switch is not.

## CI boundary

CI may run deterministic Swift build/test checks, static documentation checks, YAML parsing, and whitespace validation on a macOS runner. CI must not require account credentials, browser sessions, private profile roots, or a real two-account claim. Packaging checks that depend on local macOS resources may remain a local release gate unless the runner is explicitly provisioned and the result is documented.

## Reporting format

Every implementation report should include:

- commit or working-tree scope;
- exact commands and pass/fail results;
- tests added or exercised;
- manual-only evidence completed or still pending;
- privacy/security review performed;
- generated or ignored artifacts intentionally excluded;
- remaining uncertainty and the next safe action.
