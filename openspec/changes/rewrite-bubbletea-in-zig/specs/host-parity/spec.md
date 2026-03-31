# Delta for host-parity

## ADDED Requirements

### Requirement: Terminal and Browser Parity
The rewrite SHALL preserve equivalent application behavior across terminal and browser-backed hosts wherever the semantic model is shared.

#### Scenario: Equivalent app actions produce equivalent model outcomes
- **WHEN** a user performs the same semantic action in terminal and browser hosts
- **THEN** the model transitions to the same logical state
- **AND** any host-specific differences are limited to presentation or unsupported capabilities

### Requirement: Deterministic Headless Behavior
The rewrite SHALL keep headless execution deterministic for tests and automation.

#### Scenario: Headless runs remain suitable for tests
- **WHEN** the same model receives the same sequence of messages in the headless runtime
- **THEN** it produces the same logical output and timing results
- **AND** no interactive host behavior is required to reproduce that outcome

### Requirement: Structured Browser Bridge
The browser adapter SHALL consume structured tree output instead of inferring behavior from raw terminal text alone.

#### Scenario: Browser host uses structured output
- **WHEN** the browser host renders a model
- **THEN** it uses structured snapshot metadata from the Zig runtime
- **AND** raw frame text remains optional debugging output rather than the primary interaction source
