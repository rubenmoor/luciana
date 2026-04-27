# Initializing a New Obelisk (Obsidian Systems) Web App

> Audience: Haskell developers familiar with Nix.

---

## Prerequisites

| Tool | Notes |
|------|-------|
| **Nix** (multi-user install) | `sh <(curl -L https://nixos.org/nix/install) --daemon` |
| **Obelisk** | Installed via the Obelisk Nix cache / channel |

Enable the Obsidian Systems binary cache so you don't build the world from source:

```bash
# /etc/nix/nix.conf  (or per-user ~/.config/nix/nix.conf)
substituters = https://cache.nixos.org https://nixcache.reflex-frp.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= ryantrinkle.com-1:JJiAKaRv9mWgpVAz8dwewnZe0AzzEAzPkagE9SP5NWI=
```

Install the `ob` command:

```bash
# Option A — from the official Obelisk repo (recommended)
nix-env -f https://github.com/obsidiansystems/obelisk/archive/master.tar.gz -iA command

# Option B — using a pinned release (check https://github.com/obsidiansystems/obelisk/releases)
nix-env -f https://github.com/obsidiansystems/obelisk/archive/v1.4.1.tar.gz -iA command
```

Verify:

```bash
ob --version
```

---

## 1. Create the project

```bash
mkdir my-app && cd my-app
ob init
```

This scaffolds the canonical Obelisk directory layout:

```
my-app/
├── backend/
│   └── src/
│       └── Backend.hs          -- Snap-based backend; serves the frontend & API
├── common/
│   └── src/
│       └── Common/
│           └── Route.hs        -- Shared route types (used by both FE & BE)
├── frontend/
│   └── src/
│       └── Frontend.hs         -- Reflex-DOM widgets
├── config/
│   └── common/
│       └── route               -- Base URL path (usually "/")
├── static/                     -- Static assets served at /static/
├── default.nix                 -- Top-level Nix expression
├── cabal.project               -- Multi-package Cabal project file
└── .obelisk/                   -- Obelisk framework plumbing (pinned thunk)
```

### Key modules after `ob init`

| Module | Package | Role |
|--------|---------|------|
| `Backend.backend` | `backend` | `IO ()` entry point; configures Snap, serves the frontend, exposes API endpoints |
| `Frontend.frontend` | `frontend` | `Frontend (R FrontendRoute)` value; the Reflex-DOM widget tree |
| `Common.Route` | `common` | `ObeliskRoute` definition shared across FE/BE; type-safe routing via `obelisk-route` |

---

## 2. Run the dev server

```bash
ob run
```

This:

1. Builds the backend with GHC.
2. Builds the frontend with GHCJS (or GHC + jsaddle-warp in dev mode).
3. Starts a local server on **http://localhost:8000**.
4. Watches for file changes and reloads automatically (GHCi-based).

> First run pulls a lot from the Nix cache. Subsequent runs are fast.

---

## 3. Project configuration

### `config/`

Obelisk reads runtime config from the `config/` directory tree. Files are served to the frontend at `config/common/*` and kept backend-only at `config/backend/*`.

```bash
echo "/" > config/common/route    # base route
```

### `default.nix`

The top-level Nix expression. Override dependencies, add system packages, or pin Obelisk here:

```nix
# default.nix
(import ./.obelisk/impl {}).project ./. ({ pkgs, ... }: {
  overrides = self: super: {
    # your Haskell package overrides
  };
  # Android / iOS mobile builds (optional)
  # android.applicationId = "com.example.myapp";
  # ios.bundleIdentifier = "com.example.myapp";
})
```

---

## 4. Adding a new route

Edit [`common/src/Common/Route.hs`](common/src/Common/Route.hs):

```haskell
data FrontendRoute :: * -> * where
  FrontendRoute_Home :: FrontendRoute ()
  FrontendRoute_About :: FrontendRoute ()   -- new
```

Update the encoder/decoder, then handle it in [`frontend/src/Frontend.hs`](frontend/src/Frontend.hs):

```haskell
frontend :: Frontend (R FrontendRoute)
frontend = Frontend
  { _frontend_head = do
      elAttr "meta" ("charset" =: "utf-8") blank
      el "title" $ text "My App"
  , _frontend_body = subRoute_ $ \case
      FrontendRoute_Home  -> homeWidget
      FrontendRoute_About -> aboutWidget
  }
```

---

## 5. Building for production

```bash
# Full production build (GHCJS frontend + GHC backend)
nix-build -A exe

# The result is a single executable + static assets
ls result/
```

Deploy the contents of `result/` behind a reverse proxy (Nginx, Caddy, etc.).

---

## 6. Common `ob` commands

| Command | Description |
|---------|-------------|
| `ob init` | Scaffold a new project |
| `ob run` | Dev server with hot reload |
| `ob repl` | GHCi REPL for the project |
| `ob deploy init <env>` | Initialize a NixOps deployment |
| `ob deploy push <env>` | Push to a deployment target |
| `ob thunk pack <dir>` | Pack a source directory into an Obelisk thunk |
| `ob thunk unpack <dir>` | Unpack a thunk for local editing |
| `ob hoogle` | Start a local Hoogle server for project deps |

---

## 7. Useful references

- [Obelisk GitHub](https://github.com/obsidiansystems/obelisk) — source, issues, examples
- [Reflex-FRP docs](https://reflex-frp.org/) — the reactive framework powering the frontend
- [Reflex-DOM quickref](https://github.com/reflex-frp/reflex-dom/blob/develop/Quickref.md) — widget combinators cheat sheet
- [obelisk-route](https://hackage.haskell.org/package/obelisk-route) — type-safe routing library
- [Obsidian Systems blog](https://obsidian.systems/blog) — tutorials and deep dives
