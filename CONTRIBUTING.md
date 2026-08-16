# Contributing to CodexSwitch

Thank you for improving CodexSwitch. The project controls a security-sensitive process and profile boundary, so a small, reproducible change with explicit evidence is more useful than a broad refactor.

## Before opening work

Read these documents in order:

1. [AGENTS.md](AGENTS.md) for the operating contract and non-negotiable invariants.
2. [CONTEXT.md](CONTEXT.md) for the domain vocabulary.
3. [docs/architecture.md](docs/architecture.md) for profile, authentication, process, transaction, and UI boundaries.
4. [docs/validation.md](docs/validation.md) for compatibility evidence and failure interpretation.
5. [docs/verification-matrix.md](docs/verification-matrix.md) for command-level evidence.

Use the existing terminology. In particular, call the existing roots a profile, call the original roots adopted, call the owned roots managed, and call the recorder lock a live conversation writer. Avoid language that implies a writer lock proves active model work.

## Local setup

CodexSwitch requires macOS 14 or newer and the Swift toolchain declared by Package.swift. The official ChatGPT application is required for app, process, packaging, and real-account checks; deterministic tests use fixtures and do not require credentials.

Build the package:

~~~bash
swift build
~~~

Run the complete deterministic/local matrix:

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

The app and process probes are sanitized but inspect the locally installed ChatGPT process. The auth probe uses a temporary profile root, redacts the browser URL, and cancels its helper. The packaging script creates an ad-hoc signature for local verification; it is not a distribution or notarization workflow.

## Change workflow

1. Start from a clean worktree or clearly preserve unrelated local work.
2. Identify the owning service and read its architecture/validation section.
3. Add a typed outcome and deterministic regression test for each new failure mode.
4. Keep profile roots, authentication material, process evidence, and recovery ordering unchanged unless the task explicitly changes that boundary.
5. Update the owning architecture, validation, or status document in the same change.
6. Run the relevant checks while iterating and the complete matrix before requesting review.
7. Review staged paths, whitespace, sensitive output, and documentation links.

Do not add a copy/swap fallback, force-termination path, credential parser, browser-storage reader, or process guess based on incomplete metadata. A graceful confirmed handoff may interrupt a response only after the user has explicitly confirmed it. A failed handoff must preserve or restore the exact committed source.

## Privacy and security

Never include tokens, cookies, authentication URLs, identity hashes, account emails, helper payloads, private conversations, profile-root paths, or unsanitized logs in commits, issues, tests, screenshots, fixtures, or pull requests. Use fixed categories and temporary roots. If a test needs identity behavior, use opaque fixture values that cannot be mistaken for credentials.

Report a suspected vulnerability privately using [SECURITY.md](SECURITY.md). Do not open a public issue for an unpatched security problem.

## Pull requests

A pull request should explain:

- the behavior-level problem and the smallest affected boundary;
- the tests and exact commands run;
- whether packaging or process inspection was exercised;
- documentation updated;
- privacy/security review;
- manual two-account validation completed or still pending;
- rollback and recovery implications.

Keep commits grouped by intent with imperative subjects. Do not rewrite shared history or push with force. Reviewers must be able to separate source behavior, documentation, and repository-policy changes.

## Compatibility claims

Automated tests and probes establish implementation behavior only. They do not establish account isolation. The installed ChatGPT version remains unverified until the guided, conversation-bearing two-account validation in [docs/validation.md](docs/validation.md) passes and the exact bundle identity is recorded. Report the evidence boundary instead of upgrading the claim.
