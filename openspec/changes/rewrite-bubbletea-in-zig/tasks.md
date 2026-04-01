## 1. OpenSpec Planning Surface

- [x] 1.1 Initialize OpenSpec and Codex integration in the repository
- [x] 1.2 Add project context plus the umbrella rewrite proposal, design, and capability specs
- [x] 1.3 Add a lightweight `ralph` loop script and package scripts for status and validation

## 2. Baseline Contract Freeze

- [x] 2.1 Freeze the runtime lifecycle contract across interactive, headless, and WASM hosts
- [x] 2.2 Freeze the UI tree and renderer boundary, including semantic cursor and structured snapshot expectations
- [x] 2.3 Document the intended public component/app-kit surface versus internal-only APIs

## 3. Event and Input Completion

- [x] 3.1 Add clipboard integration to the terminal host and normalize clipboard-style flows
- [x] 3.2 Add layout-aware terminal mouse routing on top of the shared layout metadata
- [x] 3.3 Align browser, terminal, and headless event semantics for keys, focus, paste, and pointer actions

## 4. Layout and Rendering Correctness

- [ ] 4.1 Harden grapheme, wide-cell, and cursor placement behavior under renderer tests
- [ ] 4.2 Add explicit invalidation and repaint expectations for partial frame updates
- [ ] 4.3 Lock down structured layout metadata needed for host-side hit testing and richer renderers

## 5. Component System Stabilization

- [ ] 5.1 Define stable focus traversal and command routing rules across widgets
- [ ] 5.2 Extend components for richer tables, menus, forms, and field-level interactions
- [ ] 5.3 Separate stable reusable widgets from showcase-only composition code

## 6. Host Parity

- [ ] 6.1 Close the remaining browser parity gaps such as cursor placement inside clicked fields
- [ ] 6.2 Ensure headless snapshots and browser structured snapshots describe the same app state
- [ ] 6.3 Define host capability differences explicitly instead of leaking them through widget behavior

## 7. Performance and Memory Hardening

- [ ] 7.1 Benchmark hot paths for input decoding, tree composition, and cell-buffer diffing
- [ ] 7.2 Reduce avoidable allocations in renderer and browser bridge hot paths
- [ ] 7.3 Set practical performance budgets for large tables, dense dashboards, and frequent redraws

## 8. Conformance and Release Gates

- [ ] 8.1 Build a conformance matrix that maps OpenSpec requirements to repo tests and smoke checks
- [ ] 8.2 Tighten validation and release gating around the Zig rewrite artifacts
- [ ] 8.3 Prepare the rewrite capabilities for eventual archive into canonical OpenSpec specs
