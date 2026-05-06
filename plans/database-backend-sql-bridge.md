# database-backend-sql-bridge.md

Status: spec

Implementation plan for the long-term database boundary between `common`
and `backend`, based on [`database-spec.md`](database-spec.md).

---

## Summary

Keep `common` pure and beam-free, keep `beam-*` backend-only, and move all
SQL/Beam instances for shared domain types into backend-local bridge types.
This removes orphan-instance pressure without leaking database dependencies
into the frontend through `common`.

---

## Key Changes

- Strip `Common.I18n` back to pure domain concerns only: `Locale`, JSON
  instances, and text conversion helpers.
- Introduce a backend-local SQL wrapper for locale, used only at persistence
  boundaries.
- Update schema code to map between `Locale` and the backend wrapper when
  reading and writing DB rows.
- Keep the current SQL column shape unchanged so this is a dependency-boundary
  refactor, not a schema migration.
- Record the rule in `database-spec.md`: shared types live in `common`, SQL
  and Beam instances live in `backend`, and `common` must not depend on
  `beam-*`.

---

## Test Plan

- Rebuild the backend and confirm orphan-instance warnings are gone.
- Rebuild the frontend and confirm it does not inherit `beam-*` through
  `common`.
- Run `ob run` and verify registration and login still work end to end.
- No database wipe is required if the SQL schema stays unchanged.

---

## Assumptions

- The locale column stays `TEXT` with the same values.
- The backend bridge type is private to persistence code and does not leak
  into API or UI types.
- The goal is dependency hygiene, not just silence in compiler output.
