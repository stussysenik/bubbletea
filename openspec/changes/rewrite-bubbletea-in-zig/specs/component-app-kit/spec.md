# Delta for component-app-kit

## ADDED Requirements

### Requirement: Composable Widget Surface
The rewrite SHALL expose reusable widgets that compose through the shared UI tree and runtime model.

#### Scenario: Widgets compose without host-specific rendering code
- **WHEN** an application combines supported widgets
- **THEN** those widgets compose through shared state, update, and tree-rendering primitives
- **AND** host adapters do not need per-widget custom logic for normal composition

### Requirement: Shared Focus Routing
The rewrite SHALL provide a shared focus-routing model across interactive widgets.

#### Scenario: Focus moves predictably between interactive regions
- **WHEN** a user navigates between fields, menus, or lists
- **THEN** focus movement follows one shared routing model
- **AND** focused state is visible to both terminal and browser-backed renderers

### Requirement: Field-Level Targeting
The rewrite SHALL support direct targeting of interactive fields through structured UI metadata.

#### Scenario: Host clicks can focus a specific field
- **WHEN** a host identifies a specific interactive field target
- **THEN** the application can focus that exact field
- **AND** it does not need to replay intermediate navigation steps
