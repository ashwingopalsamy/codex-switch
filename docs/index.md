# Documentation index

Use this page as the routing table. Read the smallest authoritative set that covers the task, then return here when the task crosses boundaries.

| Need | Read first | Then inspect |
| --- | --- | --- |
| Profile roots, process mapping, switching, recovery, live writer handoff | [architecture.md](architecture.md) | Core/Services/DarwinProcessSnapshot.swift, Core/Services/CodexProcessController.swift, Core/Services/SwitchTransaction.swift |
| Authentication, browser flow, identity binding, callback completion | [architecture.md](architecture.md) Authentication | Core/Services/AppServerClient.swift, Core/Models/Authentication.swift |
| Guided validation or compatibility claim | [validation.md](validation.md) | [status.md](status.md), Core/Models/GuidedValidation.swift, Core/Services/CompatibilityProbe.swift |
| SwiftUI lifecycle, menu bar, single window, packaging | [architecture.md](architecture.md) Application lifecycle | App/, Resources/Info.plist, script/build_and_run.sh |
| Domain terminology | [CONTEXT.md](../CONTEXT.md) | Existing model and service names |
| Agent workflow and safety | [AGENTS.md](../AGENTS.md) | [agent-context.md](agent-context.md) |
| Commands and evidence | [verification-matrix.md](verification-matrix.md) | Package.swift, script/build_and_run.sh, Probe/main.swift |
| OSS contribution or pull request | [CONTRIBUTING.md](../CONTRIBUTING.md) | .github templates and [verification-matrix.md](verification-matrix.md) |
| Why this repository uses these agent/OSS files | [oss-and-agent-research.md](oss-and-agent-research.md) | Linked primary sources |

## Source-of-truth rule

The code and existing subsystem documents are authoritative for behavior. Agent-facing documents provide navigation, invariants, and checkable workflow; they must point to the source rather than copy implementation details that can drift. When behavior changes, update the owning architecture/validation/status document in the same change and then update only the affected agent pointer.
