# OpenSpec Planning

This repository uses OpenSpec as the planning and execution surface for the remaining Zig rewrite work.

## Entry Points

- Project context: [`project.md`](./project.md)
- Active rewrite change: [`changes/rewrite-bubbletea-in-zig`](./changes/rewrite-bubbletea-in-zig)
- Phase tasks: [`changes/rewrite-bubbletea-in-zig/tasks.md`](./changes/rewrite-bubbletea-in-zig/tasks.md)

## Commands

- `npm run openspec:status`
- `npm run openspec:validate`
- `npm run ralph:loop`
- `npm run ralph:watch`

## Working Model

- Public repo docs still summarize status for humans.
- OpenSpec captures the phased rewrite plan, capability boundaries, and execution tasks.
- The first task group establishes planning infrastructure and is already complete.
- Remaining task groups are the rewrite phases that future implementation chunks should work through.
