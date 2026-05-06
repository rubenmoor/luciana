# database-plan-2.md

Status: spec

Implementation plan for the database shape defined in
[`database-spec.md`](database-spec.md): concise SQL column naming from a
generic Beam mapping, plus a single migration owner that bootstraps and tracks
schema versions.

---

## Goal

Move the schema layer from per-table handwritten field mappings and ad hoc
bootstrap SQL into the spec-driven layout:

- `Backend.Schema.Db` owns the canonical `lucianaDb` mapping.
- Column naming is derived generically from Beam field names.
- `Backend.Schema.Migration` owns schema bootstrap and version tracking.
- The initial SQL block is the source of truth for table creation.

---

## Current State

The current code already has a working database layer, but it does not match
the spec:

- `Backend.Schema.Db` still names every column explicitly with `fieldNamed`.
- `Backend.Schema.Migration` already owns startup migration flow, but the
  migration content should be reorganized to match the spec's contract for an
  explicit initial SQL bootstrap and versioned follow-up steps.
- The database layer is otherwise wired through `Backend.Db` and startup runs
  migrations before serving.

---

## Plan

### 1. Replace per-table field mappings with one generic naming helper

Update `Backend.Schema.Db` to derive SQL names from the Beam record structure
instead of spelling out each table field by hand.

The helper should:

- strip table-specific prefixes from Haskell field names
- convert camelCase to snake_case
- keep `Id`-style primary keys concise
- preserve readable foreign-key names such as `user_id`

Use that helper to build `lucianaDb` via `defaultDbSettings \`withDbModification\``
and Beam's table-modification helper (`modifyTable` or the equivalent
`modifyEntityName` + `modifyTableFields` composition).

### 2. Keep `checkedLucianaDb` as the migration view

Retain `checkedLucianaDb` in `Backend.Schema.Db` as the Beam migrator view
used by schema validation and inspection.

Make sure the runtime `lucianaDb` and the checked migration view describe the
same tables and field shapes so migration diffs stay meaningful.

### 3. Rework migration ownership around a single bootstrap SQL block

Refactor `Backend.Schema.Migration` so it is the only module responsible for:

- applying startup migrations
- tracking applied versions in `schema_migrations`
- owning the bootstrap SQL that creates the base tables

The bootstrap SQL should explicitly define:

- all tables
- primary keys
- foreign keys and cascade rules
- unique constraints and indexes
- check constraints
- defaults and timestamps

### 4. Make the initial migration the canonical schema bootstrap

Replace any implicit or partially generated table setup with one initial SQL
block that can stand on its own.

This bootstrap should create the current schema shape in one pass and remain
easy to audit. It should be the source of truth for the database layout, not a
secondary artifact derived from a different schema description.

### 5. Keep later migrations incremental and versioned

After the initial bootstrap exists, add future changes as explicit versioned
steps rather than regenerating the whole schema.

The migration runner should:

- read the applied versions from `schema_migrations`
- compute the pending ordered steps
- print pending SQL in `print` mode
- apply pending SQL in `auto`/`apply` modes

### 6. Preserve the startup flow

Keep the existing startup shape intact:

1. load the DB URL from config
2. create the pool
3. run migrations
4. build `Env`
5. start the backend

The plan is to change the database layer behind that flow, not to redesign the
application startup sequence.

---

## File Touch List

- `backend/src/Backend/Schema/Db.hs`
- `backend/src/Backend/Schema/Migration.hs`
- `backend/src/Backend/Schema/User.hs`
- `backend/src/Backend/Schema/Session.hs`
- `backend/src/Backend/Schema/PeriodEntry.hs`
- `backend/src/Backend/Schema/PushSubscription.hs`
- `backend/src/Backend/Schema/NotificationPref.hs`
