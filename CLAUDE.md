# CLAUDE.md

Root of the project's documentation. The `plans/` directory holds overview,
reference, and feature plans; `CLAUDE.md` points into them.

## Plan index

Read only the files relevant to the current task. Each plan starts with a
`Status:` line that says whether it describes intended or existing
behaviour (`spec` / `partial` / `implemented` / `reference`).

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
| [backend-spec.md](plans/backend-spec.md) | spec | `Env` + `ReaderT` app monad; Snap middleware to keep handlers lean |
| [backend-plan-1.md](plans/backend-plan-1.md) | spec | Steps to migrate backend to Servant from scratch |
| [backend-plan-2.md](plans/backend-plan-2.md) | spec | Steps to finish backend migration from current WIP state |
| [toasts.md](plans/toasts.md) | implemented | Transient success/error messages (DaisyUI toasts, EventWriter) |

## Source map

```
backend/src/Backend/          Backend.hs, Api.hs, Db.hs, Auth.hs
backend/src/Backend/Auth/     Cookie.hs, Login.hs, Logout.hs, Me.hs,
                              RateLimit.hs, Register.hs, Session.hs
backend/src/Backend/Schema/   User.hs, Session.hs, PeriodEntry.hs,
                              PushSubscription.hs, NotificationPref.hs,
                              Db.hs, Migration.hs
common/src/Common/            Route.hs, Auth.hs, Api.hs, I18n.hs
frontend/src/Frontend/        Frontend.hs, Api.hs, Auth.hs, Login.hs, Signup.hs
frontend/src/Frontend/Widget/ Form.hs
```

## Cross-cutting conventions

- Routes: defined once in [`common/src/Common/Route.hs`](common/src/Common/Route.hs);
  full URL table and the type-safe API-call convention (no string URLs in
  `frontend/` — render via `Frontend.Api.apiUrl`) live in
  [`routes.md`](plans/routes.md). Naming: `FrontendRoute_X`, `BackendRoute_X`,
  `ApiRoute_X`, then per-area `AuthRoute` / `PeriodRoute` /
  `NotificationsRoute` / `PushRoute`.
- Schema: one `Backend.Schema.X` module per table; `LucianaDb` lives in
  `Backend.Schema.Db`.
- Prelude: `relude` everywhere; explicit import lists except `import Relude`.

## Skip these paths in searches and reads

- `.obelisk/impl/` — Obelisk thunk, large
- `dep/` — vendored thunks
- `dist-newstyle/` — cabal build output
- `static.out/` — generated assets bundle
- `ghcid-output.txt` — transient compiler output

## Instructions

1. **No code without plan:** the current state of the code must always be
   reflected in some markdown file in `plans/`. My prompts usually mean
   "edit a plan file" until I explicitly ask you to *implement a plan*.
   Whenever you write to `plans/`, stop and let me review before
   proceeding with implementation.
2. **One feature, one file:** every feature gets its own markdown file in
   `plans/`.
3. **Plan-file hierarchy, no redundancy:** plan files form a tree —
   `CLAUDE.md` is the root, overview/reference plans sit in the middle,
   feature plans are leaves. When writing or editing a plan, do not
   restate content that lives in a file further down the tree; link to it
   instead. If two files at the same level overlap, pick one as the home
   and have the other link to it.
4. **Explicit scope:** the plan file specifies files and functions; if
   changes outside that scope become necessary, update the plan first and
   nothing else.
5. **Verification loop:** after changes to code, check that it compiles
   and fix any errors before reporting done.
   - Inner loop: `ob watch` (assume it's running in a side terminal).
   - Before "done": `nix-build -A ghc.backend --no-out-link` *and*
     `nix-build -A ghcjs.frontend --no-out-link` — the GHCJS build is the
     only way to catch frontend-only errors short of `ob run`.
   - End-to-end smoke: `ob run`, hit the affected route in the browser.
6. **Verbosity:** don't explain things to me unless I ask.
7. **Subagents:** use for parallel research; don't spawn for simple
   single-file refactors.
8. **State tracking:** Use `plans/current-state.md` to keep track of the current
   state of the project and add any issues that pop up during coding that won't
   be fixed immediately.

## Common commands

- Survey a Haskell package version in the pinned set (replace `<pkg>`):
  ```bash
  nix-instantiate --eval --strict -E \
    '((import ./.obelisk/impl {}).reflex-platform.ghc.<pkg>).version or "missing"'
  ```
  Use `.ghcjs.<pkg>` for frontend-only packages.
- Build one package: `nix-build -A ghc.<pkg> --no-out-link` (or `ghcjs.<pkg>`)
- Dev server:        `ob run`
- Watch-compile:     `ob watch`
- REPL:              `ob repl`

## Adding a Haskell dependency

Available packages come from the Obelisk thunk's pinned package set (plus
`default.nix` overrides). **Do not search `/nix/store`** — it only shows
locally-built derivations and tells you nothing about the package set.

1. **Survey** each candidate package using the version-check command above.
   Run for every candidate up front so you know what's missing before
   editing cabal files.
2. **Add to `build-depends`** in the relevant `.cabal` file.
3. **For "missing" or wrong-version packages**, add an override in
   `default.nix`'s `overrides` block (`callHackageDirect`, `callCabal2nix`,
   or a thunk).
4. **Verify** with `ob run` / `ghcid`. Address build errors before reporting
   done.
