# Layers

Generated from `automation/progress.json` and local git state on 2026-03-31.

## Contents
<!-- toc:start -->
- [Release Line](#release-line)
- [Layer Map](#layer-map)
- [Commit Scopes](#commit-scopes)
- [Immediate Order](#immediate-order)
<!-- toc:end -->

## Release Line

- Latest Zig Tag: `zig-v0.11.0`
- Tag Format: `zig-v${version}`
- Commit Style: Use Conventional Commits and prefer zig-focused scopes such as feat(zig), feat(zig/input), feat(zig/renderer), docs(zig), or chore(zig).
- Live Status: Run `npm run release:status` for the current head commit and recent Zig-native commit subjects.

## Layer Map

| Layer | Status | Paths | Shipped | Next |
| --- | --- | --- | --- | --- |
| Runtime and Scheduling | Done | zig/src/cell_width.zig<br>zig/src/tea.zig<br>zig/src/headless.zig<br>zig/src/terminal.zig | Interactive and headless runtimes share one message/update model with deterministic timers and explicit terminal lifecycle management. | Fold platform event sources and richer host capabilities into the same runtime contract without borrowing Go’s goroutine-heavy shape. |
| Input Protocols | In Progress | zig/src/input.zig<br>zig/src/tea.zig<br>zig/src/renderer.zig | The decoder now understands buffered UTF-8, CSI navigation, bracketed paste, focus reporting, and SGR mouse events. | Add Kitty keyboard protocol, clipboard hooks, and layout-aware mouse routing so higher-level widgets stop guessing about host input. |
| View Tree and Layout | Done | zig/src/ui.zig<br>zig/src/cell_width.zig | The shared scene graph can render rows, columns, boxes, spacers, rules, semantic cursor nodes, and semantic tones across terminal, headless, and browser hosts, exposes measured layout bounds inside structured snapshots, tags interactive regions and item actions for browser hosts, and shares terminal-cell width logic for layout-sensitive text. | Push the same metadata deeper into field-level interactions and richer layout metadata so hit testing, scrolling regions, and cross-host renderers can share more than terminal-sized boxes. |
| Renderer | In Progress | zig/src/renderer.zig<br>zig/src/ui.zig<br>zig/src/cell_width.zig | ANSI rendering now parses the composed frame into styled cells, diffs per-glyph runs instead of whole lines, keeps wide glyphs and combining sequences aligned to real terminal columns, and can drive the real terminal cursor from semantic cursor nodes in the shared tree. | Add tougher grapheme-cluster edge cases, terminal cursor shape/blink control, and host-specific effects on top of the new cell grid. |
| Components and App Kit | In Progress | zig/src/components<br>zig/src/focus.zig<br>zig/src/apps/showcase.zig | The rewrite has a native component surface for badges, inspectors, menus, spinners, lists, progress bars, text inputs, tables, forms, validation rules, shared focus handling, and browser-targetable list/menu actions. | Add richer tables, command routing, and layout-aware interaction primitives such as field-level browser targeting so this feels like a real framework instead of a demo set. |
| WASM and Browser Host | In Progress | zig/src/wasm_showcase.zig<br>zig/src/ui.zig<br>zig/src/cell_width.zig<br>zig/build.zig<br>zig/web | The core now compiles to WASM, boots through a static browser shell, accepts browser-driven resize, key, paste, focus, mouse, and timer calls, exposes structured UI snapshots with measured grid bounds and semantic cursor nodes, can focus interactive showcase regions directly from browser hit testing, and can invoke tagged list/menu actions while keeping the raw text frame for debugging. | Push region-aware hit testing deeper into field-level interactions and richer DOM/SVG/Canvas rendering now that the browser host receives real node bounds from the Zig tree. |
| Release and Repo Automation | In Progress | scripts/update-docs.mjs<br>release.config.cjs<br>package.json<br>.github/workflows/semantic-release.yml | Semantic-release already owns zig-v* tagging, changelog updates, and docs-sync on main. | Keep layer status, latest release line, and recent Zig-native commit intent visible so every gradual push has an obvious place in the roadmap. |

## Commit Scopes

- `zig`
- `zig/input`
- `zig/runtime`
- `zig/renderer`
- `zig/ui`
- `zig/components`
- `zig/wasm`
- `zig/web`
- `zig/automation`
- `docs`

## Immediate Order

- Finish protocol-heavy terminal features such as Kitty keyboard support, clipboard integration, and layout-aware mouse hit testing.
- Add tougher grapheme-cluster edge cases and terminal cursor shape/blink control on top of the new wide-glyph-safe cell-buffer renderer.
- Add first-class framework components for richer tables, command routing, and layout/styling primitives on top of the new form/focus layer.
- Push region-aware hit testing deeper so browser clicks can target individual fields and richer widget internals, not just panels and list/menu rows.
- Keep landing incremental zig-scoped commits so semantic-release tags reflect real rewrite layers instead of mixed-purpose changes.
