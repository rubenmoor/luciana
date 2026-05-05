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
