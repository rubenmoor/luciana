# backend-plan-2.md

Status: implemented

Implementation plan to finish the backend migration, picking up from the work-in-progress state in commit `3a76bfc`.

## Completed State

Commit `3a76bfc` established the core Servant infrastructure, and later work
completed the migration:
- **`App` Monad**: `ReaderT Env Snap` is implemented in `Backend.App`.
- **`Env`**: `Env` structure is in `Backend.Env`.
- **Combinators**: `AuthRequired` (injecting `UserId`) and `RateLimit` (injecting `RateBucket`) are implemented in `Backend.Auth.Combinator` and `Backend.RateLimit.Combinator`.
- **API Wiring**: `serveApi` in `Backend.Api` uses `serveSnapWithContext` to plug into the Obelisk pipeline.
- **Routes**: auth, period, notifications, and push routes are defined in
  `Common.Api` and wired in `Backend.Api`.
- **Handlers**: per-area handlers run in the `App` monad and use Beam for
  database access where implemented.
- **Frontend API**: `Frontend.Api` exposes both `apiUrl` for Obelisk-route URL
  rendering and derived `servant-reflex` clients via `apiClients`.
- **Catch-all Routing**: `BackendRoute_Api` in `Common.Route` is configured as a catch-all.

### Residual Follow-up

This plan tracks the Servant migration only. Feature completeness issues
inside migrated handlers are tracked by their feature plans and the source
tree. Examples: period status logic is still placeholder-level, and some API
request/response shapes may need refinement.

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
- Keep `Frontend.Api.apiUrl` for call sites that use the Obelisk route GADTs;
  the route docs make this the canonical URL-rendering convention.
- Verify that frontend-only errors are caught by `nix-build -A ghcjs.frontend`.

### 5. Final Cleanup
- Remove `Backend.Auth.AuthEnv` alias and any remaining legacy Snap utility functions (`parseJsonBody`, etc.).
- Keep `ApiRoute` and related GADTs in `Common.Route`; they are still used for
  typed URL rendering in `Frontend.Api.apiUrl`.

## Verification

- **Build**: `nix-build -A ghc.backend --no-out-link` and `nix-build -A ghcjs.frontend --no-out-link` must pass.
- **Data Integrity**: Verify that Beam migrations match the existing schema for `PeriodEntry`, etc.
- **E2E**: Use `ob run` to verify that the frontend can successfully talk to all new API endpoints.
