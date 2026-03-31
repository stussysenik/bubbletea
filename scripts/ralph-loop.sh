#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANGE_NAME="${1:-rewrite-bubbletea-in-zig}"
WATCH_MODE="${WATCH_MODE:-0}"
TASKS_FILE="$ROOT_DIR/openspec/changes/$CHANGE_NAME/tasks.md"
OPENSPEC_BIN=(npx -y @fission-ai/openspec@latest)

print_phase_tasks() {
  awk '
    BEGIN {
      current = ""
    }
    /^## / {
      current = $0
      next
    }
    /^- \[ \]/ {
      if (!(current in seen)) {
        print current
        seen[current] = 1
      }
      print $0
    }
  ' "$TASKS_FILE"
}

run_once() {
  if [[ ! -f "$TASKS_FILE" ]]; then
    echo "missing tasks file: $TASKS_FILE" >&2
    exit 1
  fi

  cd "$ROOT_DIR"
  echo "== OpenSpec Status: $CHANGE_NAME =="
  "${OPENSPEC_BIN[@]}" status --change "$CHANGE_NAME"
  echo
  echo "== OpenSpec Validation =="
  "${OPENSPEC_BIN[@]}" validate "$CHANGE_NAME" --type change --strict --no-interactive
  echo
  echo "== Next Pending Tasks By Phase =="
  print_phase_tasks
}

if [[ "${2:-}" == "--watch" ]]; then
  WATCH_MODE=1
fi

if [[ "$WATCH_MODE" == "1" ]]; then
  while true; do
    clear
    run_once
    sleep "${WATCH_SECONDS:-30}"
  done
else
  run_once
fi
