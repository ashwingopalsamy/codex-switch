# Claude Code entry point

CodexSwitch keeps one canonical agent contract in [AGENTS.md](AGENTS.md). Read it first; it defines the repository map, safety invariants, branch-triggered documents, required checks, and completion criteria.

For deeper context, follow the pointers in [docs/index.md](docs/index.md). In particular:

- [docs/agent-context.md](docs/agent-context.md) explains lifecycle, isolation, authentication, and recovery.
- [docs/verification-matrix.md](docs/verification-matrix.md) explains deterministic and manual validation.
- [CONTEXT.md](CONTEXT.md) defines the project vocabulary.

Do not create a second set of rules here. Claude-specific local preferences belong in an untracked CLAUDE.local.md.
