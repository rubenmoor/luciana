# database-spec.md

Status: spec

Technical specification for the database infrastructure, environment, and naming conventions.

---

## Infrastructure

### Postgres in dev

A project-local cluster is provisioned by `flake.nix`.

- **Server**: `pkgs.postgresql_16`.
- **Cluster location**: `.pg/{data,log,sock}` under repo root.
- **Env vars**: `LUCIANA_ROOT`, `PGDATA`, `PGHOST`, `PG_LOG`, `PGDATABASE`, `PGUSER`.
- **Helper scripts**: `pg-init`, `pg-up`, `pg-down`, `psql`.
- **Connection string**: Written to `config/backend/db-url`.

### Backend Haskell side

- **Dependencies**: `beam-core`, `beam-migrate`, `beam-postgres`, `postgresql-simple`, `obelisk-executable-config-lookup`.
- **Modules**:
  - `Backend.Schema.{User,Session,PeriodEntry,PushSubscription,NotificationPref}` for table records.
  - `Backend.Schema.Db` for `LucianaDb` definition.

---

## Postgres Field Naming

To keep SQL column names concise (e.g. `id` instead of `user_id`, `user_id` instead of `session_user_id__user_id`), we use a generic mapping function in `Backend.Schema.Db`.

```haskell
-- | A generic function that strips prefixes and converts to snake_case.
-- Matches the default Beam camelCase-to-snake_case but handles nested
-- primary keys concisely for simple FKs.
applyGlobalNaming :: (Generic (tbl (FieldModification s tbl)))
                  => tbl (FieldModification s tbl)
applyGlobalNaming = allBeamFields $ \field ->
  let name = T.unpack (_fieldColumnName field)
  in stringToFieldName (customSnakeCase name)

-- Usage in LucianaDb definition
lucianaDb :: DatabaseSettings be LucianaDb
lucianaDb = defaultDbSettings `withDbModification`
  dbModification
    { _users             = modifyTableFields applyGlobalNaming
    , _sessions          = modifyTableFields applyGlobalNaming
    , _periodEntries     = modifyTableFields applyGlobalNaming
    , _pushSubscriptions = modifyTableFields applyGlobalNaming
    , _notificationPrefs = modifyTableFields applyGlobalNaming
    }
```

This ensures that:
1. Primary keys named `XId` in Haskell map to `id` in SQL (via `customSnakeCase` logic).
2. Foreign keys map to `other_table_id` instead of the verbose nested defaults.

---

## Migrations

The migration strategy is intentionally simple:

- `Backend.Schema.Migration` owns all migration logic.
- `schema_migrations` tracks applied versions by string identifier and applied timestamp.
- The backend loads pending migrations on startup and applies them in order.
- Development defaults to auto-apply so a fresh local database comes up with the current schema immediately.
- Production can switch to a print/apply mode so operators can inspect pending SQL before execution.

The key rule is that the handwritten initial SQL is the source of truth for
table and column creation. Beam's migrator is used for bookkeeping and schema
comparison, but the actual bootstrap SQL should explicitly define:

- every table and primary key
- every foreign key and cascade rule
- every unique constraint and secondary index
- every check constraint and column default

The initial migration should be idempotent at the database level in the sense
that it only creates the schema when it is absent. Subsequent migrations can
append new versions as needed, but the base table layout should remain
described by one initial SQL block so it is easy to inspect and reason about.

When validating a schema change locally, reset the database before re-running
the app so the bootstrap SQL and migration order are exercised from a clean
state. Use a database-only reset for ordinary migration testing and a full
cluster reset when you need to verify the bootstrap path from scratch.
