# Delta for runtime-contract

## ADDED Requirements

### Requirement: Shared Runtime Lifecycle
The Zig rewrite SHALL preserve one shared program lifecycle model across interactive, headless, and browser-backed hosts.

#### Scenario: Hosts drive the same update cycle
- **WHEN** a model is executed in terminal, headless, or WASM-backed environments
- **THEN** each host routes messages through the same update and command model
- **AND** host differences stay outside the model contract

### Requirement: Explicit Host Boundaries
The runtime SHALL define host responsibilities explicitly for input, rendering, focus, resize, and timer delivery.

#### Scenario: Host behavior stays outside application models
- **WHEN** a new host capability is added
- **THEN** it is modeled as host behavior at the runtime boundary
- **AND** application models do not need host-specific branching for normal lifecycle events

### Requirement: Public Surface Discipline
The rewrite SHALL distinguish intended public runtime APIs from internal implementation details.

#### Scenario: Stable runtime APIs are documented before expansion
- **WHEN** the runtime adds or changes externally consumed APIs
- **THEN** the stable contract is captured before the API is treated as part of the framework surface
