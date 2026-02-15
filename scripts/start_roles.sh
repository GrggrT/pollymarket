#!/usr/bin/env bash
set -euo pipefail

mode="auto"
if [[ "${1:-}" == "--print" ]]; then
  mode="print"
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$root" ]]; then
  echo "Error: could not find git root from $script_dir" >&2
  exit 1
fi

base="$(dirname "$root")"

pm_db="$base/pm_db"
pm_w="$base/pm_w"
pm_r="$base/pm_r"
pm_e="$base/pm_e"
pm_tl="$base/pm_tl"

required=("$pm_db" "$pm_w" "$pm_r" "$pm_e")
missing=()
for d in "${required[@]}"; do
  if [[ ! -d "$d" ]]; then
    missing+=("$d")
  fi
done
if (( ${#missing[@]} > 0 )); then
  echo "Missing required worktrees:" >&2
  for d in "${missing[@]}"; do
    echo "  $d" >&2
  done
  exit 1
fi

PROMPT_DB="You are the DB Engineer. Follow AGENTS.md and PLANS.md. Ownership: db/, migrations/, alembic/. Task: make migrations/schema/indexes/partitions workable. Add verify commands (alembic upgrade head, smoke SQL). Mark DONE in PLANS.md."
PROMPT_W="You are the Watcher Engineer. Follow AGENTS.md and PLANS.md. Ownership: services/watcher/. Task: ingestion to snapshots in the DB, retries/backoff, healthcheck, metrics/logs. Add verify command (local run + write 1 snapshot). Mark DONE in PLANS.md."
PROMPT_R="You are the Rater Engineer. Follow AGENTS.md and PLANS.md. Ownership: services/rater/. Task: read snapshots, generate/update signals idempotently, healthcheck, logs. Add verify command (local run + signals appear/update). Mark DONE in PLANS.md."
PROMPT_E="You are the Executor Engineer. Follow AGENTS.md and PLANS.md. Ownership: services/executor/. Task: read signals, perform dry-run/real-run if available, risk limits, post-only/guards if applicable, action logging. Verify: run + execution logs. Mark DONE in PLANS.md."
PROMPT_TL="You are the Tech Lead. Follow AGENTS.md and PLANS.md. Ownership: infra/compose/config/README/service skeleton. Task: single run method (docker compose or make/just), .env.example, config loader, healthchecks, README how to run. If you must change outside ownership, leave TODO and mention in REPORT. Mark DONE in PLANS.md with verify command."

print_cmds() {
  echo "cd $pm_db && codex \"$PROMPT_DB\""
  echo "cd $pm_w && codex \"$PROMPT_W\""
  echo "cd $pm_r && codex \"$PROMPT_R\""
  echo "cd $pm_e && codex \"$PROMPT_E\""
  if [[ -d "$pm_tl" ]]; then
    echo "cd $pm_tl && codex \"$PROMPT_TL\""
  fi
}

if [[ "$mode" == "print" ]]; then
  print_cmds
  exit 0
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "Error: codex is not on PATH. Run with --print to show commands." >&2
  exit 1
fi

if command -v tmux >/dev/null 2>&1; then
  session="polymarket-roles"
  if tmux has-session -t "$session" 2>/dev/null; then
    echo "tmux session already exists: $session"
    echo "Attach with: tmux attach -t $session"
    exit 0
  fi

  mk_cmd() {
    printf 'codex %q' "$1"
  }

  cmd_db="$(mk_cmd "$PROMPT_DB")"
  cmd_w="$(mk_cmd "$PROMPT_W")"
  cmd_r="$(mk_cmd "$PROMPT_R")"
  cmd_e="$(mk_cmd "$PROMPT_E")"
  cmd_tl="$(mk_cmd "$PROMPT_TL")"

  tmux new-session -d -s "$session" -n db -c "$pm_db" "$cmd_db"
  tmux new-window -t "$session" -n watcher -c "$pm_w" "$cmd_w"
  tmux new-window -t "$session" -n rater -c "$pm_r" "$cmd_r"
  tmux new-window -t "$session" -n executor -c "$pm_e" "$cmd_e"
  if [[ -d "$pm_tl" ]]; then
    tmux new-window -t "$session" -n techlead -c "$pm_tl" "$cmd_tl"
  fi

  echo "Started tmux session: $session"
  echo "Attach with: tmux attach -t $session"
  exit 0
fi

echo "tmux not found; run these in separate terminals:"
print_cmds
