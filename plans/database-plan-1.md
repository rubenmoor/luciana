# database-plan-1.md

Status: partial

Implementation plan for the runtime database plumbing (pool, migrations, startup logic). Refer to [database-spec.md](database-spec.md) for infrastructure and naming specifications.

---

## Goal

On backend startup: open a connection pool, bring the schema up to date, then serve. Operator gets an audit trail in production.

---

## Plan

### 1. Wire up a connection pool

New module `Backend.Db`:

- `data DbPool = DbPool (Pool Connection)` — wrap `Data.Pool` over `postgresql-simple`'s `Connection`.
- `withDbPool :: ByteString -> (DbPool -> IO a) -> IO a` — read the URL, create a pool (size ~10), `bracket` over `destroyAllResources`.
- `runBeam :: DbPool -> Pg a -> IO a` — `withResource` + `runBeamPostgres`.

The URL comes from `Obelisk.ExecutableConfig.Lookup.getConfig "backend/db-url"`.

### 2. Migration module

New module `Backend.Schema.Migration`:

- `initialMigration :: CheckedDatabaseSettings Postgres LucianaDb -> Migration Postgres (CheckedDatabaseSettings Postgres LucianaDb)` — add constraints/indexes that `defaultMigratableDbSettings` won't infer:
  - `ON DELETE CASCADE` on FKs to `users`.
  - `CHECK` constraints (locale, mode, period date range).
  - Explicit indexes (user-period-start, session-expiry, push-user).
- `migrationSteps :: MigrationSteps Postgres () (CheckedDatabaseSettings Postgres LucianaDb)` — versioned migration chain.

### 3. Apply migrations on startup

In `Backend.hs`, replace the stub `_backend_run`:

- Load DB URL and migration mode.
- Initialize pool.
- Call `runMigrations`.
- Pass pool to application handlers.

### 4. Operator switch

Use `LUCIANA_MIGRATIONS` env var:

| Value | Behavior |
|---|---|
| `auto` (default) | Apply silently. |
| `print` | Dry run: print SQL and exit. |
| `apply` | Apply in a transaction. |

### 5. Verification

- `ob run` after `pg-up` should apply migrations successfully.
- Verify schema in `psql` (`\d+`, `\di`).
- Add smoke test for User-Session cascade delete.

---

## File touch list

New:
- `backend/src/Backend/Db.hs`
- `backend/src/Backend/Schema/Migration.hs`

Edited:
- `backend/src/Backend.hs`
- `backend/backend.cabal`
