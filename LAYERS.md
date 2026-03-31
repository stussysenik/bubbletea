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

- Latest Zig Tag: `zig-v0.3.0`
- Tag Format: `zig-v${version}`
- Commit Style: Use Conventional Commits and prefer zig-focused scopes such as feat(zig), feat(zig/input), feat(zig/renderer), docs(zig), or chore(zig).
- Live Status: Run `npm run release:status` for the current head commit and recent Zig-native commit subjects.

## Layer Map

| Layer | Status | Paths | Shipped | Next |
| --- | --- | --- | --- | --- |
| Runtime and Scheduling | Done | zig/src/tea.zig<br>zig/src/headless.zig<br>zig/src/terminal.zig | Interactive and headless runtimes share one message/update model with deterministic timers and explicit terminal lifecycle management. | Fold platform event sources and richer host capabilities into the same runtime contract without borrowing Go’s goroutine-heavy shape. |
| Input Protocols | In Progress | zig/src/input.zig<br>zig/src/tea.zig<br>zig/src/renderer.zig | The decoder now understands buffered UTF-8, CSI navigation, bracketed paste, focus reporting, and SGR mouse events. | Add Kitty keyboard protocol, clipboard hooks, and layout-aware mouse routing so higher-level widgets stop guessing about host input. |
| View Tree and Layout | Done | zig/src/ui.zig | The shared scene graph can render rows, columns, boxes, spacers, rules, and semantic tones across terminal, headless, and future browser hosts. | Expose layout metadata and measurable boxes so hit testing, scrolling regions, and cross-host renderers can share the same tree. |
| Renderer | In Progress | zig/src/renderer.zig<br>zig/src/ui.zig | ANSI rendering is incremental at the line level and now enables the terminal modes needed for richer input. | Replace line diffing with a cell buffer so short edits, cursor motion, and host-specific effects get cheaper and more precise. |
| Components and App Kit | In Progress | zig/src/components<br>zig/src/focus.zig<br>zig/src/apps/showcase.zig | The rewrite has a native component surface for badges, inspectors, spinners, lists, progress bars, text inputs, tables, forms, and shared focus handling. | Add validation, menus, richer tables, and layout-aware interaction primitives that feel like a real framework instead of a demo set. |
| WASM and Browser Host | Planned | zig/src/wasm_showcase.zig | The core can already compile to WASM and drive a headless text renderer from browser-controlled resize, key, paste, focus, mouse, and timer calls. | Build a DOM/SVG/Canvas host that consumes the same model tree and gradually replaces text-only rendering on the web side. |
| Release and Repo Automation | In Progress | scripts/update-docs.mjs<br>release.config.cjs<br>package.json<br>.github/workflows/semantic-release.yml | Semantic-release already owns zig-v* tagging, changelog updates, and docs-sync on main. | Keep layer status, latest release line, and recent Zig-native commit intent visible so every gradual push has an obvious place in the roadmap. |

## Commit Scopes

- `zig`
- `zig/input`
- `zig/runtime`
- `zig/renderer`
- `zig/ui`
- `zig/components`
- `zig/wasm`
- `zig/automation`
- `docs`

## Immediate Order

- Finish protocol-heavy terminal features such as Kitty keyboard support, clipboard integration, and layout-aware mouse hit testing.
- Move from line-diff rendering to a cell buffer so short updates and cursor motion are cheaper.
- Add first-class framework components for validation, menus, and richer layout/styling primitives on top of the new form/focus layer.
- Add a browser host that renders the same view tree from WASM-backed state.
- Keep landing incremental zig-scoped commits so semantic-release tags reflect real rewrite layers instead of mixed-purpose changes.
