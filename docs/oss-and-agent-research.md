# AI-ready OSS repository research

Research date: 2026-08-16

This note records the primary-source conventions used for the repository guidance. It is reference material, not an additional always-loaded instruction file.

## Findings

### Agent instructions

- OpenAI's Codex documentation describes AGENTS.md as the place for repository navigation, coding conventions, build commands, test commands, and safe operating guidance. The repository therefore keeps one concise root AGENTS.md as the canonical contract.
- Claude Code automatically loads project CLAUDE.md files and can discover nested guidance when needed. The repository therefore uses CLAUDE.md as a compatibility pointer rather than maintaining a second rule set.
- Agent guidance is most reliable when it uses progressive disclosure: a short root contract points to branch-specific reference documents, and each step has a checkable completion condition.

Sources:

- [OpenAI Codex AGENTS documentation](https://github.com/openai/codex/blob/main/docs/agents_md.md)
- [Claude Code memory and CLAUDE.md loading](https://code.claude.com/docs/en/memory)
- [AGENTS.md scope and precedence discussion](https://github.com/agentsmd/agents.md/issues/135)

### GitHub OSS health

- GitHub recognizes README, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, SUPPORT, GOVERNANCE, issue templates, pull-request templates, and related community files. Repository-local files take precedence over organization or user defaults.
- GitHub issue forms support structured YAML fields, required inputs, uploads, and checkboxes. CodexSwitch issue forms must ask for reproducible, sanitized diagnostics without soliciting account or credential material.
- SECURITY.md should state supported versions and a private reporting route. This repository prefers GitHub Security Advisories and does not invent a maintainer email.
- CODEOWNERS and branch protection are repository policy choices that require verified ownership and GitHub settings; local documentation must not claim those settings exist.

Sources:

- [GitHub community health files](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file)
- [GitHub community profile checklist](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/about-community-profiles-for-public-repositories)
- [GitHub issue templates and forms](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/configuring-issue-templates-for-your-repository)
- [GitHub security policy guidance](https://docs.github.com/en/code-security/getting-started/adding-a-security-policy-to-your-repository)
- [GitHub CODEOWNERS](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners)
- [GitHub protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches)

## Decisions applied here

- Keep AGENTS.md short enough to load on every task; disclose lifecycle and evidence detail in docs/agent-context.md and docs/verification-matrix.md.
- Keep CLAUDE.md as a non-conflicting shim.
- Add standard OSS files and structured issue/PR templates, but avoid speculative CODEOWNERS, Dependabot, governance, funding, or remote branch-protection claims.
- Make MIT the repository license.
- Use GitHub Security Advisories as the preferred private security route, with truthful fallback wording if the feature is not enabled.
- Preserve the distinction between automated behavior evidence and real two-account compatibility evidence.

## Maintenance rule

When an upstream convention changes, update this note with the new primary source and then adjust the canonical instruction or community file. Do not copy vendor documentation wholesale into this repository.
