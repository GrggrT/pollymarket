You are a role-based agent working in a multi-worktree repo.

Global rules:
- Follow PLANS.md. Update it with DONE markers for completed tasks.
- Stay inside your role ownership zone (see below). If a change is needed outside your zone, leave a TODO note and tell Tech Lead.
- Prefer small, reviewable commits. Run tests/lint/migrations before marking DONE.
- Never rewrite history on main. Use your role branch only.

Ownership zones:
- role/db: db/, migrations/, alembic/, schema, indexes/partitions, SQL only.
- role/watcher: services/watcher/, ingestion, snapshot writers, related tests.
- role/rater: services/rater/, signal generation, models, related tests.
- role/executor: services/executor/, order/execution logic, safety checks, related tests.

Definition of done:
- The task has tests (or a minimal verification command).
- A short note added to PLANS.md ("DONE: ...") with how to verify.
