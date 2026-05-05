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
| [database-spec.md](plans/database-spec.md) | spec | Infrastructure, env, and naming conventions |
| [database-plan-1.md](plans/database-plan-1.md) | partial | beam/postgres setup, pool, migrations |
| [database-plan-2.md](plans/database-plan-2.md) | spec | Concise field naming implementation |
| [authentication.md](plans/authentication.md) | implemented | Session cookie, bcrypt, rate-limit |
| [backend-spec.md](plans/backend-spec.md) | spec | `Env` + `ReaderT` app monad; Snap middleware to keep handlers lean |
| [backend-plan-1.md](plans/backend-plan-1.md) | spec | Steps to migrate backend to Servant from scratch |
| [backend-plan-2.md](plans/backend-plan-2.md) | spec | Steps to finish backend migration from current WIP state |
| [toasts.md](plans/toasts.md) | implemented | Transient success/error messages (DaisyUI toasts, EventWriter) |

## Source Map

- `backend/src/Backend/`: Backend.hs, Api.hs, Db.hs, Auth.hs
- `backend/src/Backend/Auth/`: Cookie.hs, Login.hs, Logout.hs, Me.hs, RateLimit.hs, Register.hs, Session.hs
- `backend/src/Backend/Schema/`: User.hs, Session.hs, PeriodEntry.hs, PushSubscription.hs, NotificationPref.hs, Db.hs, Migration.hs
- `common/src/Common/`: Route.hs, Auth.hs, Api.hs, I18n.hs
- `frontend/src/Frontend/`: Frontend.hs, Api.hs, Auth.hs, Login.hs, Signup.hs
- `frontend/src/Frontend/Widget/`: Form.hs

## Cross-cutting Conventions

- **Haskell:** Follow the conventions in [Haskell.md](plans/Haskell.md) (relude, default extensions, cabal stanzas, explicit imports).
- **Routes:** Defined in `common/src/Common/Route.hs`. Use type-safe API calls via `Frontend.Api.apiUrl` (no raw string URLs in `frontend/`). Naming: `FrontendRoute_X`, `BackendRoute_X`, `ApiRoute_X`.
- **Schema:** One `Backend.Schema.X` module per table; `LucianaDb` in `Backend.Schema.Db`.

## Ignore Paths

- `.obelisk/impl/`
- `dep/`
- `dist-newstyle/`
- `static.out/`
- `ghcid-output.txt`

## Instructions

1.  **No code without plan:** The current state of the code must always be reflected in `plans/`. Edit or create a plan file first. **Stop and wait for user review** after updating a plan before starting implementation.
    -   **No Temporary Plans:** NEVER use `enter_plan_mode`. Always create or edit plan files directly as markdown files in the `plans/` directory to ensure they are version-controlled and visible.
    -   **Task Checkpoints:** Stop and wait for user review after completing **each** task or fix listed in `current-state.md`. Do not autonomously move to the next task in the list.
2.  **One feature, one file:** Every feature gets its own markdown file in `plans/`.
3.  **Plan-file hierarchy, no redundancy:** `GEMINI.md` is the root. Link to more specific plans rather than restating content.
4.  **Explicit scope:** If changes outside the planned scope are needed, update the plan first.
5.  **Investigation & Analysis:** Use the `codebase_investigator` subagent for architectural mapping, understanding system-wide dependencies, or root-cause analysis of complex bugs.
6.  **Token Efficiency:** 
    -   Use `grep_search` with narrow scopes and `read_file` with `start_line`/`end_line` to manage context, especially for large Haskell modules or Nix files.
    -   Utilize `subagents` for repetitive batch tasks or high-volume output commands to keep the main session lean.
7.  **Verification loop:**
    -   **Inner loop:** `ob watch` (assumed running).
    -   **Automated Checks:** Before reporting "done", you MUST autonomously run:
        -   `nix-build -A ghc.backend --no-out-link`
        -   `nix-build -A ghcjs.frontend --no-out-link`
    -   **Smoke test:** `ob run`, verify route in browser.
8.  **Adding a Haskell dependency:**
    -   Survey package version: `nix-instantiate --eval --strict -E '((import ./.obelisk/impl {}).reflex-platform.ghc.<pkg>).version or "missing"'`.
    -   Add to `build-depends` in `.cabal`.
    -   Add overrides in `default.nix` if missing or wrong version.
9.  **No Private Memory:** Do not use the private project memory folder (`.gemini/tmp/luciana/memory/`). All notes, findings, machine-specific quirks, or transient context must be stored explicitly in markdown files within the repository (e.g., in `plans/` or `GEMINI.md`).
10. **State tracking:** Use `plans/current-state.md` to keep track of the current state of the project and add any issues that pop up during coding that won't be fixed immediately.
11. **Observability & Error Reporting:**
    - **Granular Updates:** Use `update_topic` frequently (every 3-5 turns) to keep the user informed of specific sub-tasks.
    - **Command Transparency:** When running long-running or complex commands (e.g., `nix-build`, `ob watch`), always share the command being run and, upon completion or failure, provide a summary of the output.
    - **Diagnostic Tail:** If a background process is used, periodically check its progress with `read_background_output` and report any new significant log entries.
    - **Failure Post-mortems:** If a task fails or the agent becomes "stuck", perform a "Strategic Re-evaluation" by listing current assumptions and proposing an alternative path.
12. **Haskell Standards:** Always adhere to the coding standards, default extensions, and prelude settings defined in [Haskell.md](plans/Haskell.md).

## Common Commands

- **Build Backend:** `nix-build -A ghc.backend --no-out-link`
- **Build Frontend:** `nix-build -A ghcjs.frontend --no-out-link`
- **Dev Server:** `ob run`
- **Watch:** `ob watch`
- **REPL:** `ob repl`
