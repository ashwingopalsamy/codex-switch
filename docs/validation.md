# Validation Runbook

## Automated checks

Run from the repository root:

```bash
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
```

The XCTest suite uses fake app-server sessions and temporary profile roots. It also holds a real pipe open after writing a short JSONL response, exercises split lines, interleaved notifications, malformed/oversized/partial messages, and verifies `initialize → initialized → account/login/start` with a subprocess fixture. Authentication coverage includes completion-only, account-update reconciliation, reordered unrelated updates, delayed account readability, missing-event fallback for fresh profiles, stale bound credentials, manual recovery, negative completion, cancellation, and timeout. The subprocess transcript asserts local success-page parameters and the absence of an app-brand override.

Lifecycle coverage includes native argv/environment boundary parsing, kernel-observed fixture roots, target-confirmation rollback, uncancelled cleanup after task cancellation, refusal to overwrite a pending journal, fail-closed ambiguous recovery, idempotent already-restored recovery, no-op transition outcomes, root containment, process classification, and detached crash-reporter exclusion. Compatibility coverage migrates all legacy statuses, requires one exact-build provisional acknowledgement, proves cancellation is mutation-free, prevents guided diagnostics from bypassing policy, permits acknowledged switching through the normal transaction, and blocks recorded failures. Diagnostic preparation tests both an already exact source and safe establishment of a missing committed source while a live writer is present. Handoff tests assert that an unconfirmed writer performs no quit, launch, journal, commit, or history mutation; confirmation commits only after graceful source shutdown and writer release; an unreleased writer prevents target launch; and graceful-quit rollback preserves diagnostics when the exact source remains restored. Later external source loss and installed-app changes still produce typed diagnostic invalidation. `./script/build_and_run.sh --verify` sends repeated macOS open requests, requires one foreground process and one stable visible management window, then holds that exact process for a 30-second idle-window soak. Other coverage includes schema migration, TOML tables, environment sanitization, journal round trips, and symlink rejection. No fixture accesses real credentials.

`CodexSwitchProbe auth` is an installed-app-server smoke test. It creates a temporary `CODEX_HOME`, validates only that the returned browser URL is HTTPS and has an approved OpenAI/ChatGPT host, cancels the attempt, and prints no URL, account identity, or credential data. It does not open a browser and does not establish account isolation.

`CodexSwitchProbe status` is a read-only, sanitized readiness check. It prints only configured/bound counts, active storage class, compatibility state, whether provisional use was acknowledged, recovery presence, and whether the active profile has an open live conversation. `CodexSwitchProbe process` additionally reports whether the running app maps to exactly one known profile, its storage class, and whether cache evidence is explicit or the verified implicit adopted default. `CodexSwitchProbe continuity [samples]` repeats the committed-source mapping 1–100 times and fails on process loss, restart, ambiguity, or committed-profile divergence. `CodexSwitchProbe soak [seconds]` holds that exact mapping and main PID under observation for 1–600 seconds and additionally fails on a new recovery journal. None of these commands prints identity hashes or root paths.

## Optional guided isolation diagnostics

A provisional build can switch after its one-time acknowledgement. Complete this optional sequence only when promoting the exact installed build to verified or investigating suspected isolation leakage:

1. Confirm bundle ID, team signature, executable path, version, and regular CodexSwitch activation. Do not record account identifiers.
2. Bind Profile A through `account/read` or the official browser flow without replacing its existing roots.
3. Create Profile B and confirm its three managed roots are below CodexSwitch application support.
4. Start **Guided Diagnostics** under Advanced diagnostics. Preparation confirms the signed installation, diagnostic profile pair, identity bindings, roots, and live committed source, safely launching the committed profile first if ChatGPT is absent. An open live conversation does not block preparation. Diagnostics never bypass provisional acknowledgement or blocked compatibility.
5. Create uniquely named canary threads and harmless configuration markers in both accounts.
6. Alternate `A → B` at least ten times. When an open live conversation is detected, confirm the warning for that switch; CodexSwitch must gracefully close the source and verify that its account-bearing processes and writer exited before launching the target. Cancel one confirmation and verify that the source, authorization, and transition count remain unchanged. Each successful launch must expose the requested user-data, cache, and Codex roots. After the first managed launch, `swift run CodexSwitchProbe soak 120` provides a sanitized delayed-failure check while the user inspects the canary.
7. Confirm each account sees only its own canaries and that both accounts can use the same repository path.
8. Exercise a supported account refresh and repeat the switching loop.
9. Inspect fixed preferences, cache, notification-group, keychain, crash-report, and other account-bearing boundaries for leakage. Record only pass/fail, version, and sanitized failure category.
10. Choose **Record Verified** only when every check passes. The final action re-confirms the running committed roots and profile identity before writing the record. Choose **Mark Blocked** if account-specific state escapes the controlled roots.

## Failure interpretation

- Browser remains at **Requesting secure browser sign-in**: run `CodexSwitchProbe auth`. A failure means the app-server transport or installed Codex build is unavailable; keep the profile unbound.
- Browser reports success while CodexSwitch is still waiting: close the browser tab and allow automatic reconciliation to finish. If it remains pending, choose **Check Sign-in Now**; this invokes the same profile-local `account/read` verification and never imports browser or desktop-app state.
- Browser open failure after **Opening your default browser**: inspect the sanitized status, verify a default browser is configured in macOS, then retry or cancel. Never copy the URL from logs because it is never logged.
- Identity unavailable or mismatched: keep the profile unverified and do not launch it.
- Open live conversation: confirm the warning to allow one graceful handoff, or cancel to preserve the source and validation count. Confirmation may interrupt a response or tool still running.
- Live writer remains held after graceful quit: the target must not launch. If rollback restores the exact source, validation remains active; otherwise complete recovery before another switch. No termination escalation is permitted.
- Guided diagnostics stopped after a source change: the ephemeral session and history have already been cleared. Ordinary acknowledged provisional switching remains available; restart diagnostics only if you still want the verified label.
- Detached crash reporter remains: classify it separately and verify its storage root; do not force-kill it.
- Root argument or environment mismatch: stop the switch, preserve rollback/recovery evidence, and use guided diagnostics to mark the ChatGPT version blocked if the mismatch is reproducible. Do not add a copy/swap fallback.
- Recovery required after a failed switch: close ChatGPT, then choose **Retry Recovery**. Do not start a new launch or validation sequence over the pending journal.
- Strict bundle-signature failure: fix packaging before making any Force Quit or compatibility claim.

## Evidence standard

Automated checks establish transaction and root-control behavior, not real-account isolation. A `verified` compatibility claim still requires a dated guided real-account diagnostic naming the exact ChatGPT version. Without that evidence, describe the build as provisional—even though acknowledged provisional switching is available.
