# Delta for input-protocols

## ADDED Requirements

### Requirement: Cross-Host Key Semantics
The rewrite SHALL normalize key input so equivalent user actions map to consistent semantic keys across terminal and browser hosts.

#### Scenario: Equivalent keys map to the same semantic value
- **WHEN** a user performs the same navigation or editing action in supported hosts
- **THEN** the runtime emits the same semantic key meaning
- **AND** host-specific protocol details remain internal to adapters

### Requirement: Paste and Clipboard Flows
The rewrite SHALL treat paste-style text insertion as a first-class input path across hosts.

#### Scenario: Text insertion is delivered as a semantic paste flow
- **WHEN** a host provides pasted or clipboard-sourced text
- **THEN** the runtime delivers that text through a semantic paste path
- **AND** widgets do not need to infer paste from raw key streams

#### Scenario: Clipboard reads and writes stay at the host boundary
- **WHEN** an application requests clipboard read or write behavior
- **THEN** the runtime models that work as host-facing clipboard effects instead of widget-specific protocol handling
- **AND** resolved clipboard text re-enters the model through the same semantic paste path

### Requirement: Pointer and Focus Normalization
The rewrite SHALL normalize pointer and focus events so interaction routing can rely on one shared event model.

#### Scenario: Focus and pointer data remain host-independent
- **WHEN** pointer or focus events are emitted by any supported host
- **THEN** the runtime exposes shared focus and pointer semantics
- **AND** higher-level widgets consume them without protocol-specific parsing

#### Scenario: Pointer routing resolves through shared layout metadata
- **WHEN** a host emits pointer coordinates against a composed model tree
- **THEN** interaction routing resolves regions and actions through shared layout metadata
- **AND** terminal and browser hosts do not maintain separate per-widget hit maps
