# Delta for runtime-contract

## ADDED Requirements

### Requirement: Shared Runtime Lifecycle
The Zig rewrite SHALL preserve one shared program lifecycle model across interactive, headless, and browser-backed hosts.

#### Scenario: Hosts drive the same update cycle
- **WHEN** a model is executed in terminal, headless, or WASM-backed environments
- **THEN** each host routes messages through the same update and command model
- **AND** host differences stay outside the model contract

#### Scenario: First resize and init order is explicit
- **WHEN** a host boots a model for the first time
- **THEN** it injects one initial resize before the first render
- **AND** model `init` runs at most once for the lifetime of that host instance

### Requirement: Explicit Host Boundaries
The runtime SHALL define host responsibilities explicitly for input, rendering, focus, resize, and timer delivery.

#### Scenario: Host behavior stays outside application models
- **WHEN** a new host capability is added
- **THEN** it is modeled as host behavior at the runtime boundary
- **AND** application models do not need host-specific branching for normal lifecycle events

#### Scenario: WASM lifecycle stays explicit
- **WHEN** the browser-backed host is used
- **THEN** it requires explicit initialization before other exports succeed
- **AND** frame/tree buffer ownership is defined by the host boundary rather than inferred by application code

### Requirement: Public Surface Discipline
The rewrite SHALL distinguish intended public runtime APIs from internal implementation details.

#### Scenario: Stable runtime APIs are documented before expansion
- **WHEN** the runtime adds or changes externally consumed APIs
- **THEN** the stable contract is captured before the API is treated as part of the framework surface
