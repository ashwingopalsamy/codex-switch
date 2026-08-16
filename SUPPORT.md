# Support

Start with [README.md](README.md), [docs/validation.md](docs/validation.md), and [docs/verification-matrix.md](docs/verification-matrix.md). The troubleshooting section explains authentication progress, live-conversation handoff, recovery journals, process evidence, and packaging failures.

## Questions and reproducible problems

Open a GitHub issue using the matching form:

- Use the bug form for a reproducible failure or regression.
- Use the feature form for a behavior proposal with scope and acceptance criteria.

For a question that contains no private data, use the repository's public discussion channel if it is enabled. Otherwise, use a clearly scoped issue and close it when the answer is recorded in the documentation.

## What to include

Include macOS version, ChatGPT version, CodexSwitch commit or build, exact sanitized command output, reproduction steps, expected behavior, actual behavior, and whether the failure happened during a live-conversation handoff or recovery.

Remove tokens, cookies, authentication URLs, identity hashes, account emails, private conversations, profile-root paths, screenshots with personal data, and unsanitized logs. If a report may contain sensitive information, use [SECURITY.md](SECURITY.md) instead of a public issue.
