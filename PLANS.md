Goal: поднять V1.1 — watcher/rater/executor живут 24h, пишутся snapshots, signals обновляются

Order:
1) db: migrations/partitions/indexes
2) techlead: скелет сервисов, конфиг, README, make/just
3) watcher: ingestion -> snapshots
4) rater: signals на базе snapshots
5) executor: исполнение сигналов + safety
6) janitor: ретеншн, cleanup, мониторинг

Conventions
- Python 3.11+, asyncio
- Money math: Decimal only (никаких float)
- DB writes: watcher только batch COPY, никаких INSERT per tick
- No extra infra: LISTEN/NOTIFY только через Postgres
- Services entrypoints: python -m pm_bot.<service>_service

Repo structure
- src/pm_bot/* (всё тут)
- .env.sample + .env (в git только sample)
- docker-compose.yml в корне

Done when:
- alembic upgrade head проходит
- сервисы стартуют локально (docker compose / systemd / whatever принято)
- watcher пишет snapshots в БД
- rater обновляет signals
- executor читает signals и пишет execution logs (или заявки в CLOB в dry-run)
