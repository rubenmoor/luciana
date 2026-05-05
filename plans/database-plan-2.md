# database-plan-2.md

Status: spec

Implementation plan for concise Postgres field naming (concise SQL columns, descriptive Haskell fields). Refer to [database-spec.md](database-spec.md) for the naming specification.

---

## Goal

Align the Postgres schema with concise naming (e.g., `id`, `user_id`) while keeping Haskell record fields descriptive (e.g., `userId`, `sessionUserId`).

---

## Plan

### 1. Implement Naming Helpers

In `Backend.Schema.Db`, implement the generic naming logic:

- `customSnakeCase :: String -> String`: Converts `camelCase` to `snake_case` and maps `XId` or `xId` to `id`.
- `applyGlobalNaming`: A generic `allBeamFields` modification that applies `customSnakeCase`.

### 2. Update Database Settings

Update `lucianaDb` in `Backend.Schema.Db`:

- Use `defaultDbSettings \`withDbModification\` dbModification { ... }`.
- Apply `modifyTableFields applyGlobalNaming` to all tables.

### 3. Update Migrations

Refactor `Backend.Schema.Migration.hs`:

- Update `initialSql` to use concise names:
  - Primary keys: `id`.
  - Foreign keys: `user_id` (not `session_user_id__user_id`).
  - Indices and unique constraints to match.
- Bump version to `0001_initial_v3` (or reset if in early dev).

### 4. Database Reset

Apply the new schema:

1. Stop application.
2. `dropdb luciana`
3. `pg-init`
4. `ob run` (auto-applies the new concise migrations).

---

## File touch list

- `backend/src/Backend/Schema/Db.hs`
- `backend/src/Backend/Schema/Migration.hs`
