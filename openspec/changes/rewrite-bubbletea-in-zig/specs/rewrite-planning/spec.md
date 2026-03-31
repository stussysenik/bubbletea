# Delta for rewrite-planning

## ADDED Requirements

### Requirement: OpenSpec Rewrite Plan
The repository SHALL maintain the Bubble Tea Zig rewrite as an OpenSpec change with proposal, design, spec, and task artifacts.

#### Scenario: Rewrite planning surface exists in-repo
- **WHEN** a contributor inspects the rewrite planning artifacts
- **THEN** the repository contains an OpenSpec change for the rewrite
- **AND** that change includes proposal, design, capability specs, and tasks

### Requirement: Task-Driven Phase Execution
The rewrite planning surface SHALL expose phase-ordered tasks that can be worked incrementally.

#### Scenario: Phase tasks are visible and ordered
- **WHEN** a contributor reads the rewrite task list
- **THEN** the tasks are grouped by numbered phases
- **AND** each phase can be advanced independently once its dependencies are satisfied

### Requirement: Lightweight Loop Support
The repository SHALL provide a lightweight loop command that surfaces the next pending rewrite tasks from OpenSpec artifacts.

#### Scenario: Loop prints next pending tasks
- **WHEN** a contributor runs the repo loop helper for the rewrite change
- **THEN** the command shows the current OpenSpec status
- **AND** it prints pending tasks grouped by phase
