# CodexSwitch

CodexSwitch is a local macOS 14+ utility for keeping independent Codex/ChatGPT desktop profiles on one Mac. It remains a menu-bar utility, appears as a regular application in the Dock and Force Quit panel, and opens a compact management window for setup and recovery.

The utility launches the official ChatGPT application with profile-specific `CODEX_HOME`, Electron user-data, and cache roots. It does not parse OAuth material, proxy traffic, patch ChatGPT, or copy live account state.

## Build and test

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

`script/build_and_run.sh` creates a locally ad-hoc-signed bundle. Its verification mode repeats launch requests, requires one process and one management window, and holds that process through a 30-second idle-window soak. It is suitable for local development, not Developer ID distribution or notarization.

## First run

1. Launch CodexSwitch. It remains available from the menu bar and has a Dock entry for management and Force Quit.
2. Profile A adopts the existing `~/.codex`, `~/Library/Application Support/Codex`, and `~/Library/Caches/Codex` roots without replacing or deleting them.
3. Choose **Verify** or **Sign In** for Profile A so its ChatGPT identity is bound to a hash.
4. Create an isolated profile for the second account. Choose **Sign In**; CodexSwitch starts a profile-local app-server and opens the official browser flow.
5. Complete browser sign-in, then close the local success page; opening ChatGPT from the browser is neither required nor part of CodexSwitch verification. The profile verifies automatically through the profile-local app-server. While waiting, **Open Browser Again** reopens the same validated login URL, **Check Sign-in Now** safely reconciles the pending account, and **Cancel** stops only the helper. The account email may be shown transiently in the management window but is not stored or logged.
6. On the first launch or switch for a newly seen official ChatGPT build, review the provisional-compatibility notice. The acknowledgement is stored only for that exact version, bundle identifier, and signing team. A changed build asks again.
7. Switch normally. CodexSwitch continues to verify identity, roots, process mapping, graceful handoff, journaling, and rollback on every operation. **Guided isolation diagnostics** remain available under Advanced diagnostics when you want to promote the exact build to verified or record a confirmed isolation failure as blocked.

Authentication does not require closing the currently running ChatGPT desktop session. When switching detects an open Codex conversation, CodexSwitch asks for confirmation before creating recovery work or changing either process. Confirmation starts a journaled graceful handoff: ChatGPT closes, all account-bearing processes and the source writer must exit, and only then may the target launch. Cancellation preserves the source and guided-validation count. Force termination is never used.

## Troubleshooting

- During sign-in, CodexSwitch first shows **Requesting secure browser sign-in**. It changes to **Opening your default browser** only after the profile-local app-server returns a validated HTTPS OpenAI/ChatGPT URL. The affected profile row then shows waiting, verification, and completion. If opening fails, the UI reports a safe failure; if the callback is pending, **Open Browser Again** reopens the same in-memory URL.
- If the browser says sign-in succeeded but the profile still shows waiting, close the tab and choose **Check Sign-in Now**. CodexSwitch will verify through the active profile-local helper; it does not read browser storage or rely on the ordinary ChatGPT app.
- Run `swift run CodexSwitchProbe auth` to verify the installed app-server handshake without printing or opening a login URL. It uses a temporary profile root and cancels its pending login before exiting.
- If switching is disabled, inspect the compatibility card. `Provisional` asks once before protected switching, `Verified` records a completed guided diagnostic, and `Blocked` means a diagnostic found state outside the controlled roots.
- If switching says a Codex conversation is open, choose **Close ChatGPT and Switch** to allow that one graceful handoff, or cancel to leave the source and validation history unchanged. Confirmation may interrupt a response or tool that is still running.
- If the source writer remains open after ChatGPT exits, CodexSwitch does not launch the target. It restores the committed source when that can be done safely; otherwise switching remains disabled until recovery succeeds.
- If startup reports recovery is required, close ChatGPT and choose **Retry Recovery** in the management window. New launches and switches remain blocked until the last committed profile is restored and the journal is cleared.
- If CodexSwitch is missing from Force Quit, rebuild the bundle with `./script/build_and_run.sh --verify`; the verification checks regular activation and bundle identity.

## Removal

Quit CodexSwitch, remove the application bundle, and optionally move `~/Library/Application Support/CodexSwitch` to the Trash. Profile A remains usable through the normal ChatGPT startup because its adopted roots are never replaced or deleted. Managed profiles are removed through the app’s confirmation dialog or independently from the managed profile directory.

## Documentation map

- [AGENTS.md](AGENTS.md): canonical always-loaded instructions for agents and contributors.
- [CLAUDE.md](CLAUDE.md): Claude Code compatibility pointer to the canonical contract.
- [docs/index.md](docs/index.md): branch-triggered documentation routing table.
- [docs/agent-context.md](docs/agent-context.md): lifecycle, isolation, authentication, recovery, and handoff context.
- [docs/verification-matrix.md](docs/verification-matrix.md): automated evidence, manual gates, and reporting rules.
- [docs/oss-and-agent-research.md](docs/oss-and-agent-research.md): primary-source research behind the repository guidance.
- [docs/architecture.md](docs/architecture.md): profile, authentication, process, transaction, and storage invariants.
- [docs/validation.md](docs/validation.md): fixture tests, guided validation, real-app evidence, and failure interpretation.
- [docs/status.md](docs/status.md): implementation evidence, current compatibility gate, and next action.

## Contributing and security

- [CONTRIBUTING.md](CONTRIBUTING.md): setup, change workflow, checks, and pull-request expectations.
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md): community conduct expectations.
- [SECURITY.md](SECURITY.md): private vulnerability-reporting guidance.
- [SUPPORT.md](SUPPORT.md): support and sanitized troubleshooting routes.
