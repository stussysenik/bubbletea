## Why

The Zig rewrite is already real enough that the remaining work should stop living only in ad hoc conversation and status docs. We need one execution plan that turns the rewrite into a stable framework with explicit capability boundaries, phase dependencies, and trackable implementation tasks.

## What Changes

- Add OpenSpec as the structured planning surface for the Zig rewrite.
- Define the rewrite as phased capabilities instead of a loose backlog.
- Capture the runtime, input, rendering, component, host-parity, and conformance boundaries as spec deltas.
- Add a lightweight `ralph` loop so the next parallelizable tasks can be surfaced from OpenSpec instead of hand-curated notes.

## Capabilities

### New Capabilities
- `rewrite-planning`: repo-local planning and execution flow for the rewrite using OpenSpec artifacts and a lightweight loop script
- `runtime-contract`: stable lifecycle and host contract for the Zig runtime across terminal, headless, and browser hosts
- `input-protocols`: normalized cross-host input semantics for keys, paste, focus, mouse, and clipboard-style flows
- `layout-rendering`: deterministic layout, cursor, and rendering behavior across text and structured hosts
- `component-app-kit`: composable widget and focus-routing surface for real CLI and browser-backed applications
- `host-parity`: parity requirements across terminal, headless, and WASM/browser adapters
- `performance-conformance`: measurable rendering, allocation, verification, and release gate expectations

### Modified Capabilities
- None.

## Impact

- Adds OpenSpec structure under `openspec/` and Codex integration under `.codex/`.
- Introduces a durable phase plan for future rewrite work.
- Adds lightweight execution tooling in `scripts/` and `package.json`.
- Does not change runtime behavior by itself; it changes how the remaining rewrite work is specified and executed.
