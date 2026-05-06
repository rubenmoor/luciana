# AGENTS.md

This file provides Codex-specific operating instructions for this repository.

## Repository map

Project docs live in `plans/`. Read only the plan files relevant to the task.

| File | Status | Scope |
|---|---|---|
| [plans/current-state.md](plans/current-state.md) | reference | Session-handoff inbox: pending plans, awaiting work, ungrouped ideas |
| [plans/goal.md](plans/goal.md) | spec | What the app does, top-level features |
| [plans/architecture.md](plans/architecture.md) | spec | Layering (FE/common/BE/DB), libs, push flow |
| [plans/obelisk.md](plans/obelisk.md) | reference | `ob` CLI, thunks, build commands, config dirs |
| [plans/dev-environment.md](plans/dev-environment.md) | reference | Local Postgres, env vars, direnv |
| [plans/Haskell.md](plans/Haskell.md) | reference | Prelude (relude), default extensions, cabal stanza rules |
| [plans/route-modules.md](plans/route-modules.md) | reference | One module, one function convention for route handlers |
| [plans/ui-best-practices.md](plans/ui-best-practices.md) | reference | UI tasks only |
| [plans/visual-design.md](plans/visual-design.md) | reference | Color tokens, layout primitives |
| [plans/tailwind.md](plans/tailwind.md) | reference | Tailwind build pipeline |
| [plans/daisyui.md](plans/daisyui.md) | reference | DaisyUI usage notes |
| [plans/obelisk-init-guide.md](plans/obelisk-init-guide.md) | reference | Bootstrap notes from initial scaffold |
| [plans/routes.md](plans/routes.md) | partial | URL → handler map |
| [plans/schema.md](plans/schema.md) | partial | Postgres tables |
| [plans/database-spec.md](plans/database-spec.md) | spec | Infrastructure, env, and naming conventions |
| [plans/database-plan-1.md](plans/database-plan-1.md) | partial | beam/postgres setup, pool, migrations |
| [plans/database-plan-2.md](plans/database-plan-2.md) | implemented | Concise field naming implementation |
| [plans/authentication.md](plans/authentication.md) | partial | Session cookie, bcrypt, rate-limit; source is canonical for implemented behavior |
| [plans/backend-spec.md](plans/backend-spec.md) | spec | ReaderT app monad + Snap middleware |
| [plans/backend-plan-1.md](plans/backend-plan-1.md) | reference | Historical Servant migration plan from scratch; superseded by backend-plan-2 |
| [plans/backend-plan-2.md](plans/backend-plan-2.md) | implemented | Servant migration plan from current WIP |
| [plans/toasts.md](plans/toasts.md) | implemented | Toast flow |

## Codex workflow rules

1. Plan-first workflow: when implementing features or non-trivial refactors, update/create the corresponding file in `plans/` first, then implement.
2. Keep plan hierarchy non-redundant: link to canonical plans instead of duplicating content.
3. Keep scope explicit: if required changes expand beyond planned scope, update plans first.
4. Keep `plans/current-state.md` updated with deferred issues and notable handoff context.
5. Before marking work done, run relevant verification commands and fix build errors.

## Build and verification

- Backend build: `nix-build -A ghc.backend --no-out-link`
- Frontend build: `nix-build -A ghcjs.frontend --no-out-link`
- Dev server: `ob run`
- Watch mode: `ob watch`

## Conventions

- Haskell: `relude`, explicit import lists (except `import Relude`), defaults per `plans/Haskell.md`.
- Routes: define centrally in `common/src/Common/Route.hs`, and use typed URL generation via `Frontend.Api.apiUrl`.
- Schema: one module per table under `backend/src/Backend/Schema/`.

## Paths to avoid during exploration

- `.obelisk/impl/`
- `dep/`
- `dist-newstyle/`
- `static.out/`
- `ghcid-output.txt`
