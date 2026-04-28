# obelisk.md

Status: reference

## Build & Development

This is an **Obelisk** (Haskell) project using Nix. The `ob` CLI is the primary development tool.

```bash
ob run          # Start dev server with hot reload at http://localhost:8000
ob repl         # GHCi REPL for interactive development
ob watch        # Watch for changes and rebuild
nix-build -A exe  # Production build
```

Nix environment is managed via `direnv` (`.envrc` calls `use flake`). The flake.nix provides Node.js but the actual Haskell toolchain comes from Obelisk's Nix infrastructure (`.obelisk/impl` thunk).

There are no tests or linting configured yet.

## Thunks (`ob thunk`)

A **thunk** is a directory holding just enough metadata (`github.json`: owner, repo, branch, rev, sha256) for Nix to fetch a specific upstream git commit on demand — a stand-in for a vendored checkout. `.obelisk/impl/` is itself a thunk pinning [`obsidiansystems/obelisk`](https://github.com/obsidiansystems/obelisk) to one commit.

Three subcommands:

```bash
ob thunk update <path>   # bump the pinned rev to the latest commit on the tracked branch
ob thunk unpack <path>   # expand the thunk into an editable git checkout in place
ob thunk pack <path>     # re-shrink a checkout back into a thunk
```

When to use:

- **Upgrade Obelisk** — `ob thunk update .obelisk/impl`.
- **Patch a Haskell dep** that isn't in the reflex-platform package set: `ob thunk unpack dep/foo`, edit, test with `ob run`, push upstream, `ob thunk pack dep/foo`.
- **Pin a fork** — drop a thunk under `dep/<name>/` and reference it from `default.nix` instead of using `callHackageDirect`.

## Checking that the code compiles

Three options, in order of latency / fidelity:

**1. `ob watch` — fastest feedback loop, GHC only.** Boots GHCi over all three packages (`common/`, `backend/`, `frontend/`) and prints errors + warnings on every save. Best for iterative work.

```bash
ob watch
```

GHCi-only, so it does *not* catch GHCJS-specific build issues (e.g. a `cpp-options: -DGHCJS_BROWSER` mismatch, a missing GHCJS package override). For those, use option 3.

**2. `ob repl` — same package set, interactive.** Useful when you want to inspect types (`:t`), reload a single module (`:r`), or experiment in the REPL. Same coverage as `ob watch` (GHC, all three packages).

```bash
ob repl
```

**3. `nix-build -A <attr>` — full per-package build under the real toolchain.** Slow (~30-90 s per package, cached after) but authoritative — uses the same compiler invocation as a production build. Useful before reporting "done" and the only way to catch GHCJS errors without booting `ob run`.

```bash
nix-build -A ghc.common      --no-out-link   # common (GHC)
nix-build -A ghc.backend     --no-out-link   # backend (GHC)
nix-build -A ghcjs.frontend  --no-out-link   # frontend (GHCJS) — catches GHCJS-only build errors
nix-build -A exe             --no-out-link   # full production bundle (frontend.jsexe + backend exe)
```

`ghc.<pkg>` builds the GHC variant; `ghcjs.<pkg>` builds the GHCJS variant. `common/` is built under both because both backend and frontend depend on it — `ghc.common` is enough for routine checks.

### Recommended workflow

- **While editing**: keep `ob watch` running in a side terminal.
- **Before declaring a change done**: run `nix-build -A ghc.backend` and `nix-build -A ghcjs.frontend` to confirm both toolchains are happy. Common is exercised transitively.
- **End-to-end smoke test**: `ob run` and hit the affected route(s) in the browser.

## Architecture

Obelisk full-stack Haskell web app with three Cabal packages:

- **common/** — Shared types and route definitions compiled for both GHC (backend) and GHCJS (frontend). `Common.Route` defines `BackendRoute` and `FrontendRoute` as type-safe sum types using `obelisk-route`.
- **backend/** — Snap web server (GHC). Serves the compiled frontend JS, static assets, and API endpoints. Entry point: `Backend.hs` implements `backend` record with `backendConfig` and `staticFiles`.
- **frontend/** — Reflex-DOM FRP UI (GHCJS). Compiles to JavaScript that runs in the browser. `Frontend.hs` defines `frontend` record with `_frontend_head` and `_frontend_body` widgets.

The backend serves the frontend as a single-page app. Routing is shared: route types in `common/` are used by both backend (to dispatch requests) and frontend (to handle client-side navigation).

## Configuration

Runtime config lives in `config/` with three scopes:
- `config/common/` — available to both frontend and backend (publicly visible)
- `config/backend/` — backend-only (use for secrets, DB credentials)
- `config/frontend/` — frontend-only

Frontend reads config via `getConfig`. The base route is set in `config/common/route`.

## static files

- Static assets go in `static/` and are served at `/static/`
- `static/lib.js` provides FFI bridge functions (accessed via `window['skeleton_lib']`)