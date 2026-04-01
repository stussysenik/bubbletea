# Delta for layout-rendering

## ADDED Requirements

### Requirement: Deterministic Layout Metrics
The rewrite SHALL measure composed UI nodes deterministically in terminal cell units.

#### Scenario: The same tree measures the same way across hosts
- **WHEN** the same composed tree is rendered for terminal, headless, or browser-backed output
- **THEN** the measured layout metadata matches the shared tree contract
- **AND** host renderers derive presentation from that shared layout data

#### Scenario: Structured snapshot schema stays stable
- **WHEN** a compose-capable model emits a structured snapshot
- **THEN** node kinds, layout fields, and structured region/action metadata stay stable
- **AND** browser hosts can consume the tree without reparsing raw frame text

### Requirement: Semantic Cursor Behavior
The rewrite SHALL represent cursor intent semantically instead of as an embedded text glyph.

#### Scenario: Cursor intent survives host translation
- **WHEN** a focused field exposes a cursor
- **THEN** the UI tree carries cursor semantics separately from text content
- **AND** each host renders that cursor using host-appropriate behavior

#### Scenario: Authoritative snapshots keep cursor width at zero
- **WHEN** a compose-capable model is rendered for headless, terminal, or structured browser output
- **THEN** semantic cursor nodes do not widen layout measurement
- **AND** any visible plain-text cursor placeholder remains an explicit debug-only mode

### Requirement: Incremental Repaint Correctness
The rewrite SHALL support partial repaint behavior without corrupting visual output.

#### Scenario: Small updates do not require full-frame rewrites
- **WHEN** a small part of the frame changes
- **THEN** the renderer may update only the affected output region
- **AND** the resulting frame remains visually correct
