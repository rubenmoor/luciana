# obelisk.md

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