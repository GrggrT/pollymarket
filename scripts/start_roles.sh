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
pm_j="$base/pm_j"
if [[ -d "$base/pm_janitor" && ! -d "$pm_j" ]]; then
  pm_j="$base/pm_janitor"
fi

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

PROMPT_DB=$'Ты DB Engineer. Следуй PLANS.md (Order step 1).\nСделай Alembic миграцию 0001_init для Postgres:\n- Таблицы: markets_universe, watchlist_tokens, token_rules, snapshots (partitioned by RANGE(ts)), signals, positions, orders (tick_size_at_create), fills (side), daily_stats (минимум).\n- Индексы: snapshots(token_id, ts desc), signals(score desc, updated_ts desc), watchlist(enabled), positions(state), orders(token_id, created_ts desc), fills(token_id, ts desc).\n- snapshots: add received_at default now().\n- Добавь утилиту ensure_partitions(days_ahead=3) и janitor retention: удалять партиции snapshots_YYYYMMDD старше RETENTION_DAYS.\n- Добавь минимальные SQL helper функции/скрипты если нужно.\nDONE WHEN: `alembic upgrade head` создаёт всё и snapshots партиционирован, без ошибок.\nНе меняй файлы вне своей зоны владения без необходимости; если нужно — оставь TODO.'
PROMPT_TL=$'Ты Tech Lead/Integrator. Следуй PLANS.md (Order step 2).\nСобери каркас проекта:\n- Структура: src/pm_bot/..., точки входа сервисов universe/watcher/rater/executor/janitor.\n- config.py (pydantic settings, Decimal), logging.py (structlog JSON), db.py (asyncpg pool), math_decimal.py (tick rounding), README.md.\n- Добавь requirements.txt, .env.sample, docker-compose.yml (Postgres + optional pgadmin).\n- Добавь Makefile или justfile с командами: up, migrate, run-universe, run-watcher, run-rater, run-executor, run-janitor.\nОграничения: Decimal only, asyncio, без лишней инфраструктуры.\nDONE WHEN: репозиторий стартует, импорты не ломаются, README описывает полный локальный запуск.\nЕсли надо менять код вне зоны — оставь TODO и напиши в REPORT.\nНе меняй файлы вне своей зоны владения без необходимости; если нужно — оставь TODO.'
PROMPT_W=$'Ты Market Data Engineer (watcher). Следуй PLANS.md (Order step 3).\nСделай watcher_service:\n- Загружает enabled token_id из watchlist_tokens.\n- Подключается к CLOB WebSocket, подписывается на эти token_id.\n- Парсит сообщения orjson, поддерживает локальный state[token_id] с bid/ask/mid/spread/tick_size/depth1_usd/depth2_usd/last_trade.\n- Coalesce: держит только последнее состояние на token_id, dirty set.\n- Flush loop каждые SNAPSHOT_FLUSH_MS: batch формирует строки snapshots и пишет в Postgres через asyncpg copy_records_to_table (не INSERT по одному).\n- NOTIFY: после flush делает dedupe+throttle и шлёт LISTEN/NOTIFY (PG_NOTIFY_CHANNEL) максимум раз в NOTIFY_COOLDOWN_SEC на token_id.\n- Reconnect backoff, stale detector (если нет апдейтов > X sec — не уведомлять/не писать).\nDONE WHEN: watcher запускается локально, пишет snapshots и шлёт NOTIFY, CPU адекватный.\nПримечание: если WS schema неизвестна, сделай адаптер-парсер с ясными TODO и логом raw msg на debug, но каркас потоков и COPY обязателен.\nНе меняй файлы вне своей зоны владения без необходимости; если нужно — оставь TODO.'
PROMPT_R=$'Ты Quant/Rater Engineer. Следуй PLANS.md (Order step 4).\nСделай rater_service:\n- LISTEN на PG_NOTIFY_CHANNEL через asyncpg add_listener.\n- На token_id: достать snapshots за 15 минут, посчитать score по формуле из ТЗ (Decimal only): DepthScore, ActivityScore, MomentumScore, FreshnessScore, SpreadPenalty.\n- Reject если spread_pct > MAX_SPREAD_PCT; заноси token в token_rules.blacklist_until (TTL 30-60 мин) + reason.\n- UPSERT в signals (token_id pk) с components jsonb и updated_ts.\n- Параллельно periodic poll каждые RATER_INTERVAL_SEC: взять top-K токенов по активности (count snapshots за 5 минут) и пересчитать (страховка от пропуска NOTIFY).\nDONE WHEN: signals стабильно обновляется, даже если NOTIFY редкий/пропущен.\nНе меняй файлы вне своей зоны владения без необходимости; если нужно — оставь TODO.'
PROMPT_E=$'Ты Execution Engineer. Следуй PLANS.md (Order step 5).\nСделай executor_service:\n- Singleton через pg_try_advisory_lock (фиксированный ключ).\n- Каждые EXECUTOR_INTERVAL_SEC выбирает топ сигнал из signals (учитывая enabled watchlist, updated_ts свежий).\n- Проверяет риск: max_usd_per_position, max_usd_per_event (по positions exposure), max_positions_open, price range, spread, depth2_usd.\n- Берёт market state из последнего snapshot (bid/ask/mid/tick_size).\n- Считает entry_price = round_up_to_tick(bid + tick, tick) и гарантирует post-only (entry_price < ask).\n- size_shares = (max_usd_per_position / entry_price) (Decimal, quantize).\n- Реализуй state machine позиции и запись в positions/orders/fills.\n- Реализуй “paper mode / dry-run”: вместо реального CLOB просто логируй решения и записывай orders/fills синтетически (чтобы Done when из PLANS.md выполнялся без ключей).\n- Tick-size guard: если текущий tick_size отличается от orders.tick_size_at_create у активных exit ордеров — cancel/replace (в paper-mode тоже).\nDONE WHEN: executor читает signals, создаёт execution logs/ордера в dry-run, соблюдает лимиты, не падает.\nНе меняй файлы вне своей зоны владения без необходимости; если нужно — оставь TODO.'
PROMPT_J=$'Ты Janitor/Monitoring Engineer. Следуй PLANS.md (Order step 6).\nСделай janitor_service:\n- ensure_partitions(days_ahead=3) раз в час\n- удаление snapshots партиций старше RETENTION_DAYS\n- daily_stats: агрегировать за сутки trades/pnl/rejects/ws downtime/avg batch size (можно частично на V1)\nDONE WHEN: партиции создаются/удаляются без ошибок, есть базовый daily_stats.\nНе меняй файлы вне своей зоны владения без необходимости; если нужно — оставь TODO.'

print_cmds() {
  printf 'cd %s && codex %q\n' "$pm_db" "$PROMPT_DB"
  printf 'cd %s && codex %q\n' "$pm_w" "$PROMPT_W"
  printf 'cd %s && codex %q\n' "$pm_r" "$PROMPT_R"
  printf 'cd %s && codex %q\n' "$pm_e" "$PROMPT_E"
  if [[ -d "$pm_tl" ]]; then
    printf 'cd %s && codex %q\n' "$pm_tl" "$PROMPT_TL"
  fi
  if [[ -d "$pm_j" ]]; then
    printf 'cd %s && codex %q\n' "$pm_j" "$PROMPT_J"
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
  cmd_j="$(mk_cmd "$PROMPT_J")"

  tmux new-session -d -s "$session" -n db -c "$pm_db" "$cmd_db"
  tmux new-window -t "$session" -n watcher -c "$pm_w" "$cmd_w"
  tmux new-window -t "$session" -n rater -c "$pm_r" "$cmd_r"
  tmux new-window -t "$session" -n executor -c "$pm_e" "$cmd_e"
  if [[ -d "$pm_tl" ]]; then
    tmux new-window -t "$session" -n techlead -c "$pm_tl" "$cmd_tl"
  fi
  if [[ -d "$pm_j" ]]; then
    tmux new-window -t "$session" -n janitor -c "$pm_j" "$cmd_j"
  fi

  echo "Started tmux session: $session"
  echo "Attach with: tmux attach -t $session"
  exit 0
fi

echo "tmux not found; run these in separate terminals:"
print_cmds
