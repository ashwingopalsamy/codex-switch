# CodexSwitch

CodexSwitch selects one identity-bound profile for the official ChatGPT desktop application while preserving an explicit, auditable isolation boundary.

## Language

**Profile**:
A named set of Codex home, Electron user-data, and Electron cache roots that may be bound to one verified account identity.
_Avoid_: Account, workspace

**Adopted profile**:
The profile that uses ChatGPT’s pre-existing default roots without moving or replacing them.
_Avoid_: Primary account, original profile

**Managed profile**:
A profile whose three roots are owned below CodexSwitch application support.
_Avoid_: Secondary account, cloned profile

**Identity-bound profile**:
A profile whose current account identity has been verified against its stored opaque identity hash.
_Avoid_: Logged-in profile, authenticated folder

**Committed profile**:
The profile most recently confirmed as both identity-correct and exposed by the running ChatGPT process.
_Avoid_: Selected profile, intended profile

**Guided validation authorization**:
An ephemeral diagnostic session scoped to one installed ChatGPT identity and exactly two identity-bound profiles. It adds continuity and transition-counting constraints but never bypasses compatibility policy.
_Avoid_: Validation mode flag, compatibility bypass, switching permission

**Provisional compatibility acknowledgement**:
A persisted, one-time user acknowledgement scoped to an exact ChatGPT version, bundle identifier, and signing team. It permits protected switching for a build that has not completed guided diagnostics.
_Avoid_: Permanent trust, verified compatibility

**Prepared validation source**:
The committed profile after CodexSwitch has confirmed its live roots, or safely launched and confirmed it when no ChatGPT process was running, immediately before issuing guided validation authorization.
_Avoid_: Selected profile, assumed source

**Live conversation writer**:
The coordination lock held by an open Codex live-thread recorder. It can remain present after a response completes and is not proof that model or tool work is currently running.
_Avoid_: Active work, busy writer

**Confirmed live-session handoff**:
One switch transaction for which the user has explicitly allowed CodexSwitch to gracefully close ChatGPT, confirm that its account-bearing processes and the source live writer exited, and then launch the target profile. Confirmation is never reused for a later switch.
_Avoid_: Force switch, global consent

**Validated transition**:
A committed change between the two authorized profiles whose requested runtime roots were observed after launch.
_Avoid_: Click, launch attempt

**Compatibility record**:
A provisional, verified, or blocked conclusion for one installed ChatGPT version, bundle identifier, and signing team. Only a completed guided diagnostic may create a verified or blocked conclusion.
_Avoid_: Global trust, automated support result, validation session
