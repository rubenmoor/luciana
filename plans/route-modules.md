# route-modules.md

Status: reference

Convention for laying out the Haskell code that implements a route. The URL
→ route-constructor mapping lives in [`routes.md`](routes.md); this file is
only about module layout.

## The rule

Each route gets its own module that exports exactly one function —
`handler` for backend routes, `page` for frontend routes. The module name
mirrors the route constructor: `Backend.Auth.Login` for `AuthRoute_Login`,
`Frontend.Settings` for `FrontendRoute_Settings`. Helpers and types used
only by that route stay unexported.

Why:

- Handlers grow (body parse, auth, DB call, response shaping). One module
  per route keeps that growth from spilling sideways.
- Module path mirrors route path, so navigating from a constructor to its
  code is mechanical.
- One export per module forces shared helpers to be lifted out deliberately
  — into siblings like `Backend.Auth.Cookie` or `Frontend.Widget.*` —
  instead of accreting inside someone else's route module.

## Backend

```
ApiRoute_Auth   → AuthRoute_Login     →  Backend.Auth.Login     (handler)
ApiRoute_Period → PeriodRoute_Status  →  Backend.Period.Status  (handler)
```

The dispatcher (`Backend.Api`) pattern-matches on route constructors and
calls each module's `handler`. Cross-handler helpers within one area sit
in a sibling module (e.g. `Backend.Auth.Cookie`).

## Frontend

```
FrontendRoute_Login    →  Frontend.Login    (page)
FrontendRoute_Settings →  Frontend.Settings (page)
```

`Frontend.hs` dispatches by route to each module's `page`. Sub-widgets
used in only one page stay in that page's module; widgets reused across
pages graduate to `Frontend.Widget.*`.
