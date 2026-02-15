Goal: поднять V1.1 — watcher/rater/executor живут 24h, пишутся snapshots, signals обновляются

Order:
1) db: migrations/partitions/indexes
2) techlead: скелет сервисов, конфиг, README, make/just
3) watcher: ingestion -> snapshots
4) rater: signals на базе snapshots
5) executor: исполнение сигналов + safety
6) janitor: ретеншн, cleanup, мониторинг

Done when:
- alembic upgrade head проходит
- сервисы стартуют локально (docker compose / systemd / whatever принято)
- watcher пишет snapshots в БД
- rater обновляет signals
- executor читает signals и пишет execution logs (или заявки в CLOB в dry-run)
