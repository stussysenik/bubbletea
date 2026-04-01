# Layers

Generated from `automation/progress.json` and local git state on 2026-04-01.

## Contents
<!-- toc:start -->
- [Release Line](#release-line)
- [Layer Map](#layer-map)
- [Commit Scopes](#commit-scopes)
- [Immediate Order](#immediate-order)
<!-- toc:end -->

## Release Line

- Latest Zig Tag: `zig-v0.15.0`
- Tag Format: `zig-v${version}`
- Commit Style: Use Conventional Commits and prefer zig-focused scopes such as feat(zig), feat(zig/input), feat(zig/renderer), docs(zig), or chore(zig).
- Live Status: Run `npm run release:status` for the current head commit and recent Zig-native commit subjects.

## Layer Map

| Layer | Status | Paths | Shipped | Next |
| --- | --- | --- | --- | --- |
| Runtime and Scheduling | Done | zig/src/cell_width.zig<br>zig/src/tea.zig<br>zig/src/headless.zig<br>zig/src/terminal.zig | Interactive and headless runtimes share one message/update model with deterministic timers, explicit first-resize/init rules, and defined post-quit behavior, while the WASM bridge now requires explicit initialization. | Fold platform event sources and richer host capabilities into the same runtime contract without borrowing Go’s goroutine-heavy shape. |
| Input Protocols | Done | zig/src/input.zig<br>zig/src/tea.zig<br>zig/src/renderer.zig | The decoder now understands buffered UTF-8, CSI navigation, Kitty keyboard CSI-u events, bracketed paste, focus reporting, SGR mouse events, and OSC52 clipboard replies; the runtime exposes clipboard read/write effects, and hosts route pointer actions through shared layout metadata instead of widget-specific hit maps. | Extend the normalized event surface into deeper field-level targeting, richer cursor placement, and additional host effects without splintering browser and terminal semantics. |
| View Tree and Layout | Done | zig/src/ui.zig<br>zig/src/cell_width.zig | The shared scene graph can render rows, columns, boxes, spacers, rules, semantic cursor nodes, and semantic tones across terminal, headless, and browser hosts, exposes measured layout bounds inside structured snapshots, keeps semantic cursors zero-width in authoritative snapshots, tags interactive regions and item actions, supports shared region/action lookup plus hit testing, and shares terminal-cell width logic for layout-sensitive text. | Push the same metadata deeper into field-level interactions and richer layout metadata so cursor placement, scrolling regions, and cross-host renderers can share more than terminal-sized boxes. |
| Renderer | In Progress | zig/src/renderer.zig<br>zig/src/ui.zig<br>zig/src/cell_width.zig | ANSI rendering now parses the composed frame into styled cells, diffs per-glyph runs instead of whole lines, keeps wide glyphs and combining sequences aligned to real terminal columns, and can drive the real terminal cursor from semantic cursor nodes in the shared tree. | Add tougher grapheme-cluster edge cases, terminal cursor shape/blink control, and host-specific effects on top of the new cell grid. |
| Components and App Kit | In Progress | zig/src/components<br>zig/src/focus.zig<br>zig/src/apps/showcase.zig | The rewrite has a native component surface for badges, inspectors, menus, spinners, lists, progress bars, text inputs, tables, forms, validation rules, shared focus handling, semantic clipboard actions, and shared list/menu/form-field targeting across browser and terminal flows. | Add richer tables, command routing, and layout-aware interaction primitives such as cursor placement so this feels like a real framework instead of a demo set. |
| WASM and Browser Host | In Progress | zig/src/wasm_showcase.zig<br>zig/src/ui.zig<br>zig/src/cell_width.zig<br>zig/build.zig<br>zig/web | The core now compiles to WASM, boots through a static browser shell, requires explicit `bt_init`, accepts browser-driven resize, key, paste, focus, mouse, clipboard, and timer calls, exposes structured UI snapshots with measured grid bounds and semantic cursor nodes as the primary browser contract, routes pointer actions through shared Zig-side hit testing, and keeps the raw text frame as debugging output. | Push shared hit testing deeper into cursor placement and richer DOM/SVG/Canvas rendering now that the browser host receives real node bounds from the Zig tree. |
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

- Add tougher grapheme-cluster edge cases and terminal cursor shape/blink control on top of the new wide-glyph-safe cell-buffer renderer.
- Add explicit invalidation and repaint expectations so partial frame updates stay correct as the renderer grows beyond the showcase.
- Push shared hit testing deeper so browser clicks can place cursors inside fields and target richer widget internals, not just panels and row-level actions.
- Add first-class framework components for richer tables, command routing, and layout/styling primitives on top of the newly documented public app-kit surface.
- Separate stable reusable widgets from showcase-only composition code so the package boundary keeps getting tighter as features land.
- Keep landing incremental zig-scoped commits so semantic-release tags reflect real rewrite layers instead of mixed-purpose changes.
