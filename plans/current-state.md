# current-state.md

Status: reference

Session-handoff inbox.

## Tasks & Fixes

- **Auth: Remove min-length constraints.** `Common.Auth` enforces `n < 8` for passwords and `n == 0` for usernames. This causes "unresponsive" buttons because the frontend drops events on validation failure. Remove constraints or add explicit frontend error handling.
- **Beam: Final cleanup.** `Backend.Auth.Login/Register` still use `withConn` and `postgresql-simple` imports. Refactor to use `runBeamApp` consistently.
- **Toasts: Flood guard.** Cap display at 5 entries.
- **Nix: Swap to `aeson-pretty`.** Revert to pretty-printed JSON once GHCJS build issue is resolved.

## Feature Ideas (No plan yet)

- **Site-wide i18n:** Promote `Common.I18n` to a catalog. Replace all literal `text "..."` with `translatedText`. Thread `Dynamic t Locale` via reader/EventWriter.
- **User Settings:** `FrontendRoute_Settings` with locale/timezone picker. `PATCH /api/auth/me` on backend.
- **Admin Backend:** `users.is_admin` column. `requireAdmin` middleware. `GET /api/admin/users` and `DELETE /api/admin/user/:id`.

## Recently Completed

- **Servant Migration:** Backend fully migrated to Servant (`ReaderT Env Snap`).
- **Beam Adoption:** `Period`, `Notifications`, and `Push` handlers are implemented with Beam.
- **Toasts:** implemented with DaisyUI (`plans/toasts.md`).
- **Rate Limiting:** integrated as a Servant combinator; returns HTTP 429.
