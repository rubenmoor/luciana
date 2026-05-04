# backend-plan-2.md

Status: spec

Implementation plan to finish the backend migration, picking up from the work-in-progress state in commit `3a76bfc`.

## Current State (Post-3a76bfc)

Commit `3a76bfc` established the core Servant infrastructure:
- **`App` Monad**: `ReaderT Env Snap` is implemented in `Backend.App`.
- **`Env`**: `Env` structure is in `Backend.Env`.
- **Combinators**: `AuthRequired` (injecting `UserId`) and `RateLimit` (injecting `RateBucket`) are implemented in `Backend.Auth.Combinator` and `Backend.RateLimit.Combinator`.
- **API Wiring**: `serveApi` in `Backend.Api` uses `serveSnapWithContext` to plug into the Obelisk pipeline.
- **Auth Routes**: `register`, `login`, `logout`, and `me` are migrated to Servant and the `App` monad.
- **Catch-all Routing**: `BackendRoute_Api` in `Common.Route` is correctly configured as a catch-all.

### Missing/Incomplete:
- **Missing Routes**: `RoutesPeriod`, `RoutesNotifications`, and `RoutesPush` are defined in the spec but missing from `Common.Api`.
- **Handler Migration**: Handlers for Period, Notifications, and Push routes are not yet implemented or wired.
- **Database Logic**: Handlers still use `postgresql-simple` (raw SQL) via `withConn`. The spec now mandates **Beam**.
- **Frontend Client**: `Frontend.Api` still uses manual URL building or has not been fully switched to `servant-client-ghcjs`.
- **Cleanup**: Legacy `AuthEnv` and Snap glue might still exist in some modules.

## Implementation Steps

### 1. Complete the API Specification
- Update `Common.Api` to include `RoutesPeriod`, `RoutesNotifications`, and `RoutesPush` as defined in [backend-spec.md](backend-spec.md).
- Ensure all necessary request/response types have JSON and `FromHttpApiData` instances where required.

### 2. Implement Missing Handlers (with Beam)
- Create or update handler modules (e.g., `Backend.Period`, `Backend.Push`) to implement the new routes.
- **Requirement**: Use `beam-postgres` for all database interactions. Refactor existing `postgresql-simple` calls to Beam queries.
- Ensure handlers run in the `App` monad and utilize `asks envPool`.

### 3. Wire New Handlers
- Update `handlers` in `Backend.Api` to include the new per-area handler products using `:<|>`.
- Verify that the `AppContext` in `Backend.Api` still covers all necessary requirements.

### 4. Frontend Integration
- Update `Frontend.Api` to derive type-safe clients for the entire `RoutesApi`.
- Replace manual `apiUrl` calls in the frontend with these derived clients.
- Verify that frontend-only errors are caught by `nix-build -A ghcjs.frontend`.

### 5. Final Cleanup
- Remove `Backend.Auth.AuthEnv` alias and any remaining legacy Snap utility functions (`parseJsonBody`, etc.).
- Remove the old `ApiRoute` and related GADTs from `Common.Route` if they still exist.

## Verification

- **Build**: `nix-build -A ghc.backend --no-out-link` and `nix-build -A ghcjs.frontend --no-out-link` must pass.
- **Data Integrity**: Verify that Beam migrations match the existing schema for `PeriodEntry`, etc.
- **E2E**: Use `ob run` to verify that the frontend can successfully talk to all new API endpoints.
