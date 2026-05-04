# GEMINI.md

Root of the project's documentation and instructions for Gemini. The `plans/` directory holds overview, reference, and feature plans.

## Plan Index

Refer to these files for context on specific areas. Each plan starts with a `Status:` line (`spec` / `partial` / `implemented` / `reference`).

| File | Status | Scope |
|---|---|---|
| [current-state.md](plans/current-state.md) | reference | Session-handoff inbox: pending plans, awaiting work, ungrouped ideas |
| [goal.md](plans/goal.md) | spec | What the app does, top-level features |
| [architecture.md](plans/architecture.md) | spec | Layering (FE/common/BE/DB), libs, push flow |
| [obelisk.md](plans/obelisk.md) | reference | `ob` CLI, thunks, build commands, config dirs |
| [dev-environment.md](plans/dev-environment.md) | reference | Local Postgres, env vars, direnv |
| [Haskell.md](plans/Haskell.md) | reference | Prelude (relude), default extensions, cabal stanza rules |
| [route-modules.md](plans/route-modules.md) | reference | One module, one function — convention for route handlers |
| [ui-best-practices.md](plans/ui-best-practices.md) | reference | UI tasks only — form labels, ids, Enter-to-submit |
| [visual-design.md](plans/visual-design.md) | reference | Color tokens, layout primitives |
| [tailwind.md](plans/tailwind.md) | reference | Tailwind build pipeline |
| [daisyui.md](plans/daisyui.md) | reference | DaisyUI usage notes |
| [obelisk-init-guide.md](plans/obelisk-init-guide.md) | reference | Bootstrap notes from initial scaffold |
| [routes.md](plans/routes.md) | partial | URL → handler map; spec for unbuilt routes |
| [schema.md](plans/schema.md) | partial | Postgres tables; some implemented |
| [database.md](plans/database.md) | partial | beam/postgres setup, pool, migrations |
| [authentication.md](plans/authentication.md) | implemented | Session cookie, bcrypt, rate-limit |
| [backend.md](plans/backend.md) | spec | `Env` + `ReaderT` app monad; Snap middleware to keep handlers lean |
| [toasts.md](plans/toasts.md) | implemented | Transient success/error messages (DaisyUI toasts, EventWriter) |

## Source Map

- `backend/src/Backend/`: Backend.hs, Api.hs, Db.hs, Auth.hs
- `backend/src/Backend/Auth/`: Cookie.hs, Login.hs, Logout.hs, Me.hs, RateLimit.hs, Register.hs, Session.hs
- `backend/src/Backend/Schema/`: User.hs, Session.hs, PeriodEntry.hs, PushSubscription.hs, NotificationPref.hs, Db.hs, Migration.hs
- `common/src/Common/`: Route.hs, Auth.hs, Api.hs, I18n.hs
- `frontend/src/Frontend/`: Frontend.hs, Api.hs, Auth.hs, Login.hs, Signup.hs
- `frontend/src/Frontend/Widget/`: Form.hs

## Cross-cutting Conventions

- **Routes:** Defined in `common/src/Common/Route.hs`. Use type-safe API calls via `Frontend.Api.apiUrl` (no raw string URLs in `frontend/`). Naming: `FrontendRoute_X`, `BackendRoute_X`, `ApiRoute_X`.
- **Schema:** One `Backend.Schema.X` module per table; `LucianaDb` in `Backend.Schema.Db`.
- **Prelude:** Use `relude` everywhere. Explicit import lists except for `import Relude`.

## Ignore Paths

- `.obelisk/impl/`
- `dep/`
- `dist-newstyle/`
- `static.out/`
- `ghcid-output.txt`

## Instructions

1. **No code without plan:** The current state of the code must always be reflected in `plans/`. Edit or create a plan file first. **Stop and wait for user review** after updating a plan before starting implementation.
2. **One feature, one file:** Every feature gets its own markdown file in `plans/`.
3. **Plan-file hierarchy, no redundancy:** `GEMINI.md` is the root. Link to more specific plans rather than restating content.
4. **Explicit scope:** If changes outside the planned scope are needed, update the plan first.
5. **Verification loop:**
   - Inner loop: `ob watch` (assumed running).
   - Before completion: `nix-build -A ghc.backend --no-out-link` AND `nix-build -A ghcjs.frontend --no-out-link`.
   - Smoke test: `ob run`, verify route in browser.
6. **Adding a Haskell dependency:**
   - Survey package version: `nix-instantiate --eval --strict -E '((import ./.obelisk/impl {}).reflex-platform.ghc.<pkg>).version or "missing"'`.
   - Add to `build-depends` in `.cabal`.
   - Add overrides in `default.nix` if missing or wrong version.

## Common Commands

- **Build Backend:** `nix-build -A ghc.backend --no-out-link`
- **Build Frontend:** `nix-build -A ghcjs.frontend --no-out-link`
- **Dev Server:** `ob run`
- **Watch:** `ob watch`
- **REPL:** `ob repl`
