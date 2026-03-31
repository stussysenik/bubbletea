# bubbletea-zig

This directory contains a Zig-first Bubble Tea rewrite prototype instead of a line-for-line Go port.

## Contents

<!-- toc:start -->
- [Why this shape](#why-this-shape)
- [Optimization targets worth pushing further](#optimization-targets-worth-pushing-further)
- [Stack recommendation](#stack-recommendation)
- [Automation](#automation)
- [Run](#run)
- [Build WASM](#build-wasm)
- [Test](#test)
<!-- toc:end -->

What is here:

- A single-threaded event loop in [`src/tea.zig`](./src/tea.zig)
- A headless runtime in [`src/headless.zig`](./src/headless.zig)
- A shared focus utility in [`src/focus.zig`](./src/focus.zig)
- A composable cross-host view tree in [`src/ui.zig`](./src/ui.zig)
- A stateful terminal input decoder in [`src/input.zig`](./src/input.zig)
- Raw terminal setup and size polling in [`src/terminal.zig`](./src/terminal.zig)
- A line-diff ANSI renderer in [`src/renderer.zig`](./src/renderer.zig)
- Reusable components in [`src/components`](./src/components), including text input, table, and form primitives
- A shared showcase model in [`src/apps/showcase.zig`](./src/apps/showcase.zig)
- A native showcase in [`examples/showcase/main.zig`](./examples/showcase/main.zig)
- A WASM export surface in [`src/wasm_showcase.zig`](./src/wasm_showcase.zig)

## Why this shape

Bubble Tea's API is elegant, but the Go implementation pays for flexibility with runtime indirection, goroutine churn around commands, and renderer complexity that exists largely to hide terminal costs after the fact.

The Zig rewrite starts from different assumptions:

- Mutate model state in place instead of returning a copied interface value every update.
- Use a deterministic timer queue instead of spawning a goroutine per delayed command.
- Keep rendering incremental by diffing lines before writing ANSI sequences.
- Make components plain Zig structs with direct method calls and no interface boxing.
- Start from a headless state machine so the same model can target terminal, WASM, or service hosts.
- Render a composable view tree instead of concatenating strings in every app.

## Optimization targets worth pushing further

The current prototype already avoids some obvious overhead, but these are the best next steps:

1. Replace line diffing with a cell buffer so cursor movement and short edits become cheaper than whole-line clears.
2. Parse terminal input as a stream state machine so UTF-8, mouse, bracketed paste, and Kitty keyboard enhancements can stay allocation-free.
3. Move timers and I/O to platform event sources (`kqueue`, `epoll`, `io_uring` later) instead of poll-plus-scan.
4. Add a rope or segmented buffer for large views so composing components does not always flatten into one contiguous string.
5. Expand the current view tree into a richer layout/style system so the same model tree can target terminal, web, or WASM renderers cleanly.

## Stack recommendation

If the goal is a serious product and not just a terminal port:

- Use Zig for the terminal runtime and shared state/update/layout core.
- Use Elixir outside that core for supervision, clustering, presence, queues, and failure isolation.
- Use TypeScript and CSS only for a browser renderer or admin shell, not for terminal styling.
- Use WASM only if you want to reuse the Zig core in the browser; otherwise a native TS renderer is simpler.
- Use Lua only if you need end-user scripting, plugin sandboxes, or live automation hooks. Do not put Lua in the core runtime path by default.
- For vector graphics in the browser, use SVG for structured UI and Canvas/WebGL/WebGPU when animation throughput matters.

Practical recommendation:

- Terminal-first app: Zig only.
- Browser + terminal from one core: Zig core plus TS renderer, then compile selected logic to WASM.
- Networked multi-user system: Zig UI/runtime plus Elixir services over a protocol boundary.

## Automation

- `npm run docs:sync` refreshes `README.md`, `PROGRESS.md`, and markdown tables of contents.
- `npm run docs:check` verifies generated docs are current.
- `npm run release:dry-run` previews semantic-release decisions locally.
- `npm run release` is intended for CI on `main`; it creates `zig-v*` tags and updates the changelog/docs without colliding with upstream Bubble Tea release tags.
- Seed the release namespace with `zig-v0.0.0` at the pre-rewrite upstream main tip so semantic-release only analyzes Zig-native commits afterward.

## Run

```sh
cd zig
zig build run
```

## Build WASM

```sh
cd zig
zig build wasm
```

## Test

```sh
cd zig
zig build test
```
