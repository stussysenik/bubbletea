# Progress

Generated from `automation/progress.json` on 2026-04-01.

## Contents
<!-- toc:start -->
- [Overview](#overview)
- [Status Board](#status-board)
- [Verification](#verification)
- [Next](#next)
<!-- toc:end -->

## Overview

A Zig-native Bubble Tea rewrite that starts headlessly, renders to terminal today, and now includes protocol-aware terminal input with Kitty keyboard support, a structured key model, a styled cell-buffer terminal renderer with wide-glyph handling and real cursor state, form-driven UI primitives, semantic cursor nodes, and a browser host that renders structured UI snapshots with measured layout bounds, region-aware focus targeting, item-level browser actions, and direct form-field targeting from the same WASM-backed runtime. The runtime lifecycle, UI snapshot boundary, and intended public app-kit surface are now explicitly frozen in code, docs, and OpenSpec.

- Status: `active`
- Docs: [README](./README.md), [zig/README](./zig/README.md), [PROGRESS](./PROGRESS.md), [LAYERS](./LAYERS.md), [OpenSpec](./openspec/README.md)
- Planning: [project](./openspec/project.md), [active change](./openspec/changes/rewrite-bubbletea-in-zig)
- Release Strategy: semantic-release on main creates zig-v* tags and updates docs/changelog; artifact publishing for the Zig runtime is a separate next step.
- Latest Zig Tag: `zig-v0.15.0`
- Commit Style: Use Conventional Commits and prefer zig-focused scopes such as feat(zig), feat(zig/input), feat(zig/renderer), docs(zig), or chore(zig).

## Status Board

| Area | Status | Notes |
| --- | --- | --- |
| Core runtime | Done | Single-threaded update loop, deterministic command scheduling, and terminal host live in zig/src/tea.zig, now with an explicit lifecycle contract shared with headless and WASM hosts. |
| Headless runtime | Done | A host-agnostic runtime exists in zig/src/headless.zig for automation, tests, and non-terminal adapters, with explicit init-once, initial-resize, structured-tree, and post-quit behavior. |
| Composable UI tree | Done | A view tree with rows, columns, boxes, rules, spacers, stable structured snapshot kinds, and zero-width semantic cursor behavior exists in zig/src/ui.zig. |
| Reusable components | Done | Spinner, list, badge, inspector, menu, progress bar, text input, table, and form components now live in zig/src/components, with text input now emitting a semantic cursor node instead of a literal caret glyph. |
| Terminal styling | Done | The terminal renderer now respects view-tree tones through a styled cell buffer, handles wide glyphs safely, and can drive the real terminal cursor while headless and WASM renders stay plain. |
| WASM host exports | Done | A freestanding WASM module with init, resize, key, paste, focus, mouse, tick, and render exports exists in zig/src/wasm_showcase.zig. |
| Advanced terminal input | In Progress | The decoder and terminal host now handle buffered reads, split UTF-8, CSI navigation, Kitty keyboard mode, bracketed paste, focus reporting, and SGR mouse; clipboard integration and layout-aware hit testing are still ahead. |
| Higher-level app kit | In Progress | Text input, table, form validation, inspector, menu, shared focus primitives, paste insertion, wheel navigation, and browser-targetable form fields landed; richer command routing and interaction primitives are the next framework layer. |
| Browser renderer | In Progress | A static web host now boots the WASM showcase, maps browser key/paste/focus/mouse/resize events into the shared runtime, consumes structured UI snapshots with measured grid bounds for DOM rendering, renders semantic cursor nodes, can focus interactive showcase regions from browser hit testing, and can invoke list/menu item actions plus direct form-field focus while keeping the raw text frame available for debugging; richer per-widget web rendering is still ahead. |

## Verification

- `cd zig && zig build`: Verify the native showcase builds.
- `cd zig && zig build test`: Run Zig unit tests across the runtime, UI tree, and components.
- `cd zig && zig build wasm`: Verify the freestanding WASM module is emitted successfully.
- `cd zig && zig build web`: Verify the browser host assets and colocated WASM bundle are emitted together.
- `cd zig && printf 'q' | zig build run | sed -n '1,12p'`: Smoke-test the CLI host in non-interactive mode.
- `npm run web:check`: Parse-check the static browser bridge before serving it.
- `npm run docs:check`: Verify generated docs, status blocks, release metadata, and markdown tables of contents are current.

## Next

- Finish protocol-heavy terminal features such as clipboard integration and layout-aware mouse hit testing on top of the shipped Kitty keyboard layer.
- Add tougher grapheme-cluster edge cases and terminal cursor shape/blink control on top of the new wide-glyph-safe cell-buffer renderer.
- Add first-class framework components for richer tables, command routing, and layout/styling primitives on top of the newly documented public app-kit surface.
- Push region-aware hit testing deeper so browser clicks can place cursors inside fields and target richer widget internals, not just panels and row-level actions.
- Keep landing incremental zig-scoped commits so semantic-release tags reflect real rewrite layers instead of mixed-purpose changes.
