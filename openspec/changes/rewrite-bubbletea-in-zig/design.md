## Context

The repository already has a functioning Zig runtime, a structured UI tree, a styled cell-buffer renderer, reusable components, and a browser host. The current roadmap is spread across `README.md`, `PROGRESS.md`, `LAYERS.md`, and commit history. That is useful for humans reading status, but weak as an execution system.

The rewrite now needs two things:

1. A durable contract for what “done” means in each major subsystem.
2. A task surface that can drive incremental local work and parallel agent execution without losing dependency order.

## Goals / Non-Goals

**Goals:**
- Make the remaining rewrite phases explicit and durable in-repo.
- Turn the major rewrite layers into OpenSpec capabilities with concrete requirements.
- Keep one umbrella change that reflects the long-running rewrite rather than exploding the work into dozens of disconnected changes.
- Add a lightweight bash loop that surfaces pending work by phase so future chunks can be delegated cleanly.

**Non-Goals:**
- Replace the existing README/PROGRESS/LAYERS docs.
- Archive or freeze the rewrite immediately.
- Build a full task runner or CI orchestrator around OpenSpec.
- Split every future commit into a separate OpenSpec change.

## Decisions

### 1. Use one umbrella OpenSpec change for the rewrite

The rewrite is already underway and spans runtime, renderer, components, and hosts. Modeling this as one long-running umbrella change keeps the plan coherent and avoids false boundaries between tightly coupled layers.

Alternative considered:
- Many small changes.
Why not:
- Better for isolated feature work, worse for one cross-cutting rewrite that still shares foundational contracts.

### 2. Model phases as capabilities plus tasks

Capabilities capture stable system contracts. Tasks capture execution order. We need both:

- capability specs define what the framework must guarantee
- tasks define the order in which we actually land the work

Alternative considered:
- Tasks only.
Why not:
- That tracks activity, not the long-term contract.

### 3. Keep status docs and OpenSpec side by side

`README.md`, `PROGRESS.md`, and `LAYERS.md` remain the public/project-facing summary. OpenSpec becomes the execution source of truth for the rewrite phases.

Alternative considered:
- Replace status docs with OpenSpec output.
Why not:
- The current docs already serve a different audience and are part of release/status automation.

### 4. Use a lightweight `ralph` bash loop

The loop should expose the next unchecked task per phase and validate the active change. It should not own builds, branching, or agent orchestration. The user and agents remain in control.

Alternative considered:
- A larger automation tool or daemon.
Why not:
- Too much machinery for a repo that already has good local command discipline.

### 5. Explicit parallel lanes

Parallel work is useful only when write scopes stay disjoint. The plan therefore defines lanes by subsystem:

- runtime/input
- layout/renderer
- components/browser UX
- docs/verification/release

This gives future agent delegation a default structure without hard-coding it into the repo.

## Risks / Trade-offs

- [Umbrella change grows too large] -> Keep tasks sharply scoped and land small commits against the umbrella plan.
- [Specs drift from implementation] -> Require `openspec validate` and regular task updates when landing chunks.
- [Loop script becomes stale ceremony] -> Keep it dumb, text-first, and sourced directly from `tasks.md`.
- [Parallel agents collide in the same files] -> Use phase/lane guidance and keep disjoint write scopes as a hard rule.
- [Public docs and OpenSpec disagree] -> Refresh status docs whenever the umbrella plan materially changes.

## Migration Plan

1. Initialize OpenSpec in the repo.
2. Add project context plus the umbrella rewrite change.
3. Define the rewrite capabilities and phased task list.
4. Add the lightweight loop script and npm commands.
5. Use the OpenSpec artifacts as the planning surface for future rewrite chunks.

## Open Questions

- When the rewrite stabilizes, should the umbrella change be archived into canonical specs all at once or split into final narrower changes first?
- How much of the public API should be considered stable before the rewrite reaches full terminal/browser parity?
- Should future benchmark artifacts live in OpenSpec, normal repo docs, or both?
