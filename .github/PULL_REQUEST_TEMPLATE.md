## Summary

- What behavior-level problem does this change address?
- Which source-of-truth document or subsystem owns the change?

## Evidence

- [ ] swift build
- [ ] swift test
- [ ] Relevant CodexSwitchProbe commands
- [ ] build_and_run.sh --verify and strict codesign, when packaging or lifecycle is affected
- [ ] git diff --check
- [ ] Manual two-account validation status is stated accurately

Commands run and results:

## Safety review

- [ ] Profile-root containment, adopted-path immutability, and symlink rules are preserved.
- [ ] Authentication material and private conversation data remain opaque.
- [ ] ChatGPT and account-bearing helpers are never force-terminated.
- [ ] Recovery journal and rollback ordering remain fail-closed.
- [ ] Diagnostics and screenshots are sanitized.

## Documentation

- [ ] Architecture, validation, status, or agent guidance was updated when behavior changed.
- [ ] New files are linked from the documentation index when appropriate.
- [ ] No unsupported compatibility or deployment claim was added.
