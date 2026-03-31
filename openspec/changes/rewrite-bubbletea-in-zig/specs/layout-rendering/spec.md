# Delta for layout-rendering

## ADDED Requirements

### Requirement: Deterministic Layout Metrics
The rewrite SHALL measure composed UI nodes deterministically in terminal cell units.

#### Scenario: The same tree measures the same way across hosts
- **WHEN** the same composed tree is rendered for terminal, headless, or browser-backed output
- **THEN** the measured layout metadata matches the shared tree contract
- **AND** host renderers derive presentation from that shared layout data

### Requirement: Semantic Cursor Behavior
The rewrite SHALL represent cursor intent semantically instead of as an embedded text glyph.

#### Scenario: Cursor intent survives host translation
- **WHEN** a focused field exposes a cursor
- **THEN** the UI tree carries cursor semantics separately from text content
- **AND** each host renders that cursor using host-appropriate behavior

### Requirement: Incremental Repaint Correctness
The rewrite SHALL support partial repaint behavior without corrupting visual output.

#### Scenario: Small updates do not require full-frame rewrites
- **WHEN** a small part of the frame changes
- **THEN** the renderer may update only the affected output region
- **AND** the resulting frame remains visually correct
