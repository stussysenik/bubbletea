# bubbletea-zig

This directory contains a Zig-first Bubble Tea rewrite prototype instead of a line-for-line Go port.

## Contents

<!-- toc:start -->
- [Why this shape](#why-this-shape)
- [Runtime Lifecycle Contract](#runtime-lifecycle-contract)
- [Structured Snapshot Contract](#structured-snapshot-contract)
- [Public API](#public-api)
- [Optimization targets worth pushing further](#optimization-targets-worth-pushing-further)
- [Stack recommendation](#stack-recommendation)
- [Automation](#automation)
- [Layer Roadmap](#layer-roadmap)
- [Run](#run)
- [Build WASM](#build-wasm)
- [Build Web Host](#build-web-host)
- [Serve Web Host](#serve-web-host)
- [Test](#test)
- [Build Docs](#build-docs)
<!-- toc:end -->

What is here:

- A single-threaded event loop in [`src/tea.zig`](./src/tea.zig)
- A headless runtime in [`src/headless.zig`](./src/headless.zig)
- Shared lifecycle and host capability contracts in [`src/contract.zig`](./src/contract.zig)
- A shared focus utility in [`src/focus.zig`](./src/focus.zig)
- A composable cross-host view tree in [`src/ui.zig`](./src/ui.zig)
- A stateful terminal input decoder in [`src/input.zig`](./src/input.zig) that handles keys, OSC52 clipboard replies, paste, focus, and SGR mouse events
- Raw terminal setup and size polling in [`src/terminal.zig`](./src/terminal.zig), including clipboard read/write hooks
- A styled cell-buffer ANSI renderer in [`src/renderer.zig`](./src/renderer.zig) that also enables terminal protocols such as bracketed paste and focus reporting
- Reusable components in [`src/components`](./src/components), including inspector, menu, text input, table, and form primitives
- A shared showcase model in [`src/apps/showcase.zig`](./src/apps/showcase.zig)
- A native showcase in [`examples/showcase/main.zig`](./examples/showcase/main.zig)
- A WASM export surface in [`src/wasm_showcase.zig`](./src/wasm_showcase.zig) with explicit init, resize, key, paste, focus, mouse, clipboard, tick, and snapshot entrypoints
- A static browser host in [`web`](./web) that drives the WASM build through a thin JavaScript bridge, consumes structured UI snapshots with measured layout bounds, uses shared hit testing for pointer routing, drains clipboard effects, and keeps the raw text frame available for debugging

## Why this shape

Bubble Tea's API is elegant, but the Go implementation pays for flexibility with runtime indirection, goroutine churn around commands, and renderer complexity that exists largely to hide terminal costs after the fact.

The Zig rewrite starts from different assumptions:

- Mutate model state in place instead of returning a copied interface value every update.
- Use a deterministic timer queue instead of spawning a goroutine per delayed command.
- Keep rendering incremental by diffing lines before writing ANSI sequences.
- Make components plain Zig structs with direct method calls and no interface boxing.
- Start from a headless state machine so the same model can target terminal, WASM, or service hosts.
- Render a composable view tree instead of concatenating strings in every app.

## Runtime Lifecycle Contract

The shared lifecycle is now explicit:

- Terminal hosts run `Program.run()`: host setup, initial resize, `init` once, first render, event loop, quit, teardown, return final model.
- Headless hosts run `HeadlessProgram`: one initial resize is injected before `init`, `boot()` is idempotent, and quit freezes later mutation until `deinit()`.
- WASM hosts must call `bt_init()` first. Other exports do not lazy-init anymore.
- `bt_render_*` is debug text output. `bt_tree_*` is the authoritative browser-facing snapshot contract.
- Snapshot pointers returned by the WASM bridge stay valid until the next successful mutating export.

## Structured Snapshot Contract

The shared UI tree in [`src/ui.zig`](./src/ui.zig) is the authoritative cross-host boundary.

- Stable node kinds: `text`, `cursor`, `row`, `column`, `box`, `spacer`, `rule`
- `layout` coordinates are measured in terminal cells
- Semantic cursor nodes stay zero-width in authoritative snapshots
- `region` and `action` metadata stay attached to the same nodes that hosts can target directly
- Plain-text cursor placeholders are debug-only and must be opted into explicitly

## Public API

Import the package as:

```zig
const tea = @import("bubbletea_zig");
```

Recommended app-kit surface:

- `tea.Program`, `tea.HeadlessProgram`
- `tea.Message`, `tea.Cmd`, `tea.Update`, `tea.emit`, `tea.tickAfter`
- `tea.copyToClipboard`, `tea.readClipboard`
- `tea.FocusRing`, `tea.ui`, `tea.components`
- `tea.contract`

Advanced host/runtime surface:

- `tea.input`, `tea.InputDecoder`, `tea.InputEvent`
- `tea.renderer`, `tea.terminal`

Example-only surface:

- `tea.apps.showcase`

Minimal app-kit usage:

```zig
const std = @import("std");
const tea = @import("bubbletea_zig");

const Msg = tea.Message(void);
const Input = tea.components.TextInput(64);

const Model = struct {
    input: Input = Input.init(.{
        .prompt = "demo> ",
        .placeholder = "type here",
    }),

    pub fn update(self: *@This(), msg: Msg) !tea.Update(Msg) {
        return switch (msg) {
            .key => |key| if (self.input.update(key)) .{} else tea.Update(Msg).noop(),
            else => tea.Update(Msg).noop(),
        };
    }

    pub fn compose(self: *const @This(), tree: *tea.ui.Tree) !tea.ui.NodeId {
        return self.input.compose(tree);
    }
};
```

## Optimization targets worth pushing further

The current prototype already avoids some obvious overhead, but these are the best next steps:

1. Replace line diffing with a cell buffer so cursor movement and short edits become cheaper than whole-line clears.
2. Keep extending the stream decoder so richer keyboard protocols and terminal-side host effects stay centralized and allocation-light.
3. Move timers and I/O to platform event sources (`kqueue`, `epoll`, `io_uring` later) instead of poll-plus-scan.
4. Add a rope or segmented buffer for large views so composing components does not always flatten into one contiguous string.
5. Expand the current view tree into a richer layout/style system so the same model tree can target terminal, web, or WASM renderers cleanly.

## Stack recommendation

If the goal is a serious product and not just a terminal port:

- Use Zig for the terminal runtime and shared state/update/layout core.
- Use Elixir outside that core for supervision, clustering, presence, queues, and failure isolation.
- Use TypeScript and CSS only for a browser renderer or admin shell, not for terminal styling.
- For the current host, plain JavaScript is enough; add TypeScript once the browser adapter grows past a small static bridge and needs stronger editor feedback.
- Use WASM only if you want to reuse the Zig core in the browser; otherwise a native TS renderer is simpler.
- Use Lua only if you need end-user scripting, plugin sandboxes, or live automation hooks. Do not put Lua in the core runtime path by default.
- For vector graphics in the browser, use SVG for structured UI and Canvas/WebGL/WebGPU when animation throughput matters.

Practical recommendation:

- Terminal-first app: Zig only.
- Browser + terminal from one core: Zig core plus TS renderer, then compile selected logic to WASM.
- Networked multi-user system: Zig UI/runtime plus Elixir services over a protocol boundary.

## Automation

- `npm run docs:sync` refreshes `README.md`, `PROGRESS.md`, `LAYERS.md`, and markdown tables of contents.
- `npm run docs:check` verifies generated docs are current.
- `npm run release:status` prints the latest `zig-v*` tag, current Zig head commit, and recent Zig-native commit subjects.
- `npm run release:dry-run` previews semantic-release decisions locally.
- `npm run release` is intended for CI on `main`; it creates `zig-v*` tags and updates the changelog/docs without colliding with upstream Bubble Tea release tags.
- Seed the release namespace with `zig-v0.0.0` at the pre-rewrite upstream main tip so semantic-release only analyzes Zig-native commits afterward.

## Layer Roadmap

- [LAYERS.md](../LAYERS.md) tracks the rewrite by architecture layer instead of by random file churn.
- Prefer gradual, scoped commits such as `feat(zig/input): ...`, `feat(zig/renderer): ...`, or `docs(zig): ...` so release tags map cleanly to rewrite milestones.

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

## Build Web Host

```sh
cd zig
zig build web
```

The static host lands in `zig/zig-out/web/showcase` with:

- `index.html`
- `styles.css`
- `app.js`
- `bubbletea-zig-showcase.wasm`

## Serve Web Host

```sh
python3 -m http.server --directory zig/zig-out/web/showcase 4173
```

Then open `http://127.0.0.1:4173`.

## Test

```sh
cd zig
zig build test
```

## Build Docs

```sh
cd zig
zig build docs
```
