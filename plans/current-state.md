# current-state.md

Status: reference

Session-handoff inbox.

## Tasks & Fixes

(None pending)

## Feature Ideas (No plan yet)

- **Site-wide i18n:** Promote `Common.I18n` to a catalog. Replace all literal `text "..."` with `translatedText`. Thread `Dynamic t Locale` via reader/EventWriter.
- **User Settings:** `FrontendRoute_Settings` with locale/timezone picker. `PATCH /api/auth/me` on backend.
- **Admin Backend:** `users.is_admin` column. `requireAdmin` middleware. `GET /api/admin/users` and `DELETE /api/admin/user/:id`.

## Recently Completed

- **Toasts: Flood guard.** Capped display at 5 entries. Automatically removes oldest when overflowing.
- **Beam: Register cleanup.** Refactored `Backend.Auth.Register` to use idiomatic `insertOnConflict` with `onConflictDoNothing`, removing manual `SqlError` handling.
- **Backend: Beam 0.10 compatibility.** Updated `Backend.Schema.Db` to match the 4-argument `DatabaseTable` constructor in newer Beam versions and fixed related warnings.
- **Nix: GHCJS build fix.** Resolved `quickcheck-instances` failure by explicitly adding `text-short` dependency in `default.nix`.
- **Haskell Standards:** Enforced explicit imports across all modules (except Relude) and achieved zero warnings in the backend build.
- **Backend Fixes:** Resolved critical Beam issues (returning syntax, `runPgInsertReturningList`, multiple assignments) and fixed BCrypt hashing with secure salts.
- **Auth Constraints:** Removed min-length constraints (8 chars for password) in `Common.Auth` to prevent UI events from being dropped.
- **Servant Migration:** Backend fully migrated to Servant (`ReaderT Env Snap`).
- **Beam Adoption:** `Period`, `Notifications`, and `Push` handlers are implemented with Beam.
- **Toasts:** implemented with DaisyUI (`plans/toasts.md`).
- **Rate Limiting:** integrated as a Servant combinator; returns HTTP 429.
