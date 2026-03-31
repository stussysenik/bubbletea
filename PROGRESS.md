# Progress

Generated from `automation/progress.json` on 2026-03-31.

## Contents
<!-- toc:start -->
- [Overview](#overview)
- [Status Board](#status-board)
- [Verification](#verification)
- [Next](#next)
<!-- toc:end -->

## Overview

A Zig-native Bubble Tea rewrite that starts headlessly, renders to terminal today, and now includes protocol-aware terminal input plus editable, tabular, and form-driven UI primitives on top of a shared composable tree.

- Status: `active`
- Docs: [README](./README.md), [zig/README](./zig/README.md), [PROGRESS](./PROGRESS.md), [LAYERS](./LAYERS.md)
- Release Strategy: semantic-release on main creates zig-v* tags and updates docs/changelog; artifact publishing for the Zig runtime is a separate next step.
- Latest Zig Tag: `zig-v0.5.0`
- Commit Style: Use Conventional Commits and prefer zig-focused scopes such as feat(zig), feat(zig/input), feat(zig/renderer), docs(zig), or chore(zig).

## Status Board

| Area | Status | Notes |
| --- | --- | --- |
| Core runtime | Done | Single-threaded update loop, deterministic command scheduling, and terminal host live in zig/src/tea.zig. |
| Headless runtime | Done | A host-agnostic runtime exists in zig/src/headless.zig for automation, tests, and non-terminal adapters. |
| Composable UI tree | Done | A view tree with rows, columns, boxes, rules, and spacers exists in zig/src/ui.zig. |
| Reusable components | Done | Spinner, list, badge, inspector, menu, progress bar, text input, table, and form components now live in zig/src/components. |
| Terminal styling | Done | The terminal renderer now respects view-tree tones while headless and WASM renders stay plain. |
| WASM host exports | Done | A freestanding WASM module with init, resize, key, paste, focus, mouse, tick, and render exports exists in zig/src/wasm_showcase.zig. |
| Advanced terminal input | In Progress | The decoder and terminal host now handle buffered reads, split UTF-8, CSI navigation, bracketed paste, focus reporting, and SGR mouse; Kitty keyboard, clipboard, and layout-aware hit testing are still ahead. |
| Higher-level app kit | In Progress | Text input, table, form validation, inspector, menu, shared focus primitives, paste insertion, and wheel navigation landed; richer command routing and interaction primitives are the next framework layer. |
| Browser renderer | Planned | The core is WASM-ready, but a DOM/SVG/Canvas renderer has not been built yet. |

## Verification

- `cd zig && zig build`: Verify the native showcase builds.
- `cd zig && zig build test`: Run Zig unit tests across the runtime, UI tree, and components.
- `cd zig && zig build wasm`: Verify the freestanding WASM module is emitted successfully.
- `cd zig && printf 'q' | zig build run | sed -n '1,12p'`: Smoke-test the CLI host in non-interactive mode.
- `npm run docs:check`: Verify generated docs, status blocks, release metadata, and markdown tables of contents are current.

## Next

- Finish protocol-heavy terminal features such as Kitty keyboard support, clipboard integration, and layout-aware mouse hit testing.
- Move from line-diff rendering to a cell buffer so short updates and cursor motion are cheaper.
- Add first-class framework components for richer tables, command routing, and layout/styling primitives on top of the new form/focus layer.
- Add a browser host that renders the same view tree from WASM-backed state.
- Keep landing incremental zig-scoped commits so semantic-release tags reflect real rewrite layers instead of mixed-purpose changes.
