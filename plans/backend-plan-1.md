# backend-plan-1.md

Status: reference — historical plan superseded by [backend-plan-2.md](backend-plan-2.md).

Historical implementation plan to migrate the backend to the architecture
defined in [backend-spec.md](backend-spec.md). Do not use this as current
implementation guidance; the migration was completed through
[backend-plan-2.md](backend-plan-2.md), and the source tree is now canonical
for exact behavior.

## Current State

The current backend uses Obelisk's default routing dispatching to `Snap ()` functions. These handlers manually manage:
- HTTP method dispatch.
- JSON request body parsing.
- Response `Content-Type` headers.
- Manual error status codes (401, 429, etc.).
- Explicit environment passing (`AuthEnv`).

## Implementation Steps

### 1. Dependency Setup
- Add `servant`, `servant-server`, and `servant-snap` to `backend.cabal` and `common.cabal`.
- Survey pinned package versions using `nix-instantiate` and add overrides in `default.nix` if necessary.

### 2. Environment & Monad Foundation
- Create `Backend.Env` and `Backend.App`.
- Implement `runApp` to hoist `App` into Servant's `Handler`.
- Keep `AuthEnv` as a deprecated alias to allow incremental migration.

### 3. API Specification & Combinators
- Define the `RoutesApi` Servant type in `Common.Api`.
- Implement `Backend.Auth.Combinator` and `Backend.RateLimit.Combinator` to handle cross-cutting concerns (Auth & Rate Limiting) at the type level.

### 4. Handler Migration
- Replace `serveBackendRoute` in `Backend.hs` with `serveSnapWithContext`.
- Refactor per-area handlers (Auth, Period, etc.) to run in the `App` monad.
- Remove manual boilerplace (parsing, content-types) and replace with Servant's declarative style.
- *Constraint*: HTTP-level behavior must remain byte-identical.

### 5. Frontend Integration & Cleanup
- Add generated Servant clients where useful, but keep the Obelisk-route API
  GADTs in `Common.Route`; they remain the route-rendering source for
  `Frontend.Api.apiUrl`.
- Remove obsolete Snap glue (`parseJsonBody`, `writeJson`, etc.) where no
  longer used.

## Verification

- **Build**: Ensure both `ghc.backend` and `ghcjs.frontend` build cleanly via `nix-build`.
- **Smoke Test**: `ob run` and verify all authentication flows (login, logout, register, etc.) still function as expected.
- **Compliance**: Verify 401 and 429 responses are still returned correctly by the new combinators.
