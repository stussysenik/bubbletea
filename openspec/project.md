# bubbletea-zig OpenSpec Context

## Purpose

This repository is turning the Bubble Tea runtime model into a Zig-native framework that can run:

- headlessly for tests and automation
- interactively in a terminal host
- in a browser host through a shared WASM core

The rewrite is no longer a blank-slate port. It already has real runtime, UI tree, renderer, component, and browser-host foundations. OpenSpec exists here to make the remaining work explicit, phased, and executable.

## Current State

- `zig/src/tea.zig`: interactive runtime and terminal program loop
- `zig/src/headless.zig`: deterministic host-agnostic runtime
- `zig/src/ui.zig`: composable scene graph, layout, JSON snapshots, semantic cursor nodes
- `zig/src/renderer.zig`: styled cell-buffer renderer with cursor control
- `zig/src/input.zig`: buffered decoder with Kitty keyboard, paste, focus, and SGR mouse
- `zig/src/components`: current widget/app-kit surface
- `zig/src/wasm_showcase.zig` and `zig/web`: browser host bridge and DOM renderer

## Constraints

- Keep the Zig runtime explicitly managed and deterministic.
- Prefer one shared semantic model across terminal, headless, and browser hosts.
- Preserve the existing docs automation in `README.md`, `PROGRESS.md`, and `LAYERS.md`.
- Keep changes incremental and pushable. Large rewrites should still land as focused chunks.
- Avoid reverting unrelated user changes.

## Verification Commands

- `cd zig && zig build`
- `cd zig && zig build test`
- `cd zig && zig build wasm`
- `cd zig && zig build web`
- `cd zig && printf 'q' | zig build run | sed -n '1,24p'`
- `npm run web:check`
- `npm run docs:check`
- `npm run openspec:validate`

## Execution Model

The umbrella OpenSpec change for this rewrite is `rewrite-bubbletea-in-zig`.

Use it this way:

1. Check current phase/task status with `npm run openspec:status`.
2. Use `npm run ralph:loop` to surface the next unchecked task from each phase.
3. Split work only across disjoint write scopes.
4. Land focused commits that map cleanly back to one or two OpenSpec tasks.

## Parallel Agent Lanes

- Lane A: runtime and input protocols
- Lane B: layout and renderer correctness
- Lane C: components, focus routing, and browser host UX
- Lane D: docs, verification, packaging, and release gates

These lanes are guidance, not hard isolation. If two chunks touch the same files, do them sequentially.
