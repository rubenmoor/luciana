# routes.md

Status: partial — all route GADTs, `Common.Api`, backend handler wiring, and
the frontend API helper are implemented. Some feature semantics behind those
routes are still incomplete; source is canonical for exact behavior.

URL routing — frontend pages and JSON API both — lives in
[`common/src/Common/Route.hs`](../common/src/Common/Route.hs), so the backend
dispatches on the same types the frontend navigates with and URL changes
surface as compile errors on both sides.

Library mechanics (`Encoder`, `R`, `PageName`, `SegmentResult`,
`mkFullRouteEncoder`, `pathParamEncoder`) are documented upstream in
[`obsidiansystems/obelisk/docs/introduction.md`](https://github.com/obsidiansystems/obelisk/blob/master/docs/introduction.md).
Read it once if you need a refresher; do not restate it here.

`obelisk-route` encodes only path + query. HTTP method, headers, and body are
described by `Common.Api` for `/api/*` and implemented through Servant/Snap.

Module layout for the code that *implements* a route is in
[`route-modules.md`](route-modules.md).

---

## Frontend routes

User-facing pages, served as one SPA with client-side navigation.

| Constructor | URL | Auth | Purpose |
|---|---|---|---|
| `FrontendRoute_Home` | `/` | required | Today's status (green / yellow / red) and quick "log period start" action. |
| `FrontendRoute_Calendar` | `/calendar` | required | Month-view calendar with past entries. |
| `FrontendRoute_History` | `/history` | required | List of past period entries; edit / delete. |
| `FrontendRoute_Settings` | `/settings` | required | Locale, notification time + mode, manage push subscriptions, log out. |
| `FrontendRoute_Login` | `/login` | anon-only | Login form. |
| `FrontendRoute_Signup` | `/signup` | anon-only | Registration form. |

"required" routes redirect to `/login` when `AuthState = AuthAnon`
([`authentication.md`](authentication.md) § Frontend).

---

## Backend routes

```
BackendRoute_Missing                  Obelisk default 404
BackendRoute_Api    → R ApiRoute      /api/*
BackendRoute_Vapid                    /vapid-public-key  (text/plain VAPID pubkey)
```

`BackendRoute_Vapid` sits outside `/api` so it can stay unauthenticated and
cacheable.

### `ApiRoute` — JSON endpoints

#### `AuthRoute` — `/api/auth/*`

Mirrors [`authentication.md`](authentication.md) § Routes.

| Constructor | Method + Path | Body | Response | Auth |
|---|---|---|---|---|
| `AuthRoute_Register` | `POST /api/auth/register` | `{ username, password, locale, timezone }` | `200 RegisterResult` (+ `Set-Cookie` on `Ok`) | anon |
| `AuthRoute_Login` | `POST /api/auth/login` | `{ username, password }` | `200 LoginResult` (+ `Set-Cookie` on `Ok`) | anon |
| `AuthRoute_Logout` | `POST /api/auth/logout` | — | `204` (clears cookie) | required |
| `AuthRoute_Me` | `GET /api/auth/me` | — | `{ id, username, locale, timezone }` / `401` | required |

Expected outcomes (invalid credentials, username taken, rate-limit) ride
inside the JSON `LoginResult` / `RegisterResult` types — see
[`authentication.md`](authentication.md) § Routes. Non-2xx is reserved
for unexpected conditions only.

#### `PeriodRoute` — `/api/period/*`

| Constructor | Method + Path | Body | Response |
|---|---|---|---|
| `PeriodRoute_Status` | `GET /api/period/status` | — | `{ phase: Green/Yellow/Red, dayInCycle, nextExpected }` |
| `PeriodRoute_Entries` | `GET / POST /api/period/entries` | `{ startDate, endDate?, notes? }` (POST) — GET takes query: `?limit=`, `?before=` | GET: `[{ id, startDate, endDate, notes }]` / POST: `201 { id }` |
| `PeriodRoute_Entry` | `PATCH/DELETE /api/period/entry/:id` | `{ startDate?, endDate?, notes? }` (PATCH) | `204` / `404` |

`:id` is `PeriodEntryId` (newtype `Int64`) encoded via `pathParamEncoder`
with `unsafeTshowEncoder`. The route-layer `PeriodEntryId` lives in
`Common.Route`; the backend has a separate beam-derived `PeriodEntryId` in
`Backend.Schema.PeriodEntry` and converts at the handler boundary.

The single-entry route uses `entry` (singular) because
`pathComponentEncoder` rejects two constructors that share their first path
segment — `/entries` and `/entries/:id` cannot share a `PeriodRoute`.

#### `NotificationsRoute` — `/api/notifications/*`

| Constructor | Method + Path | Body | Response |
|---|---|---|---|
| `NotificationsRoute_Prefs` | `GET / PUT /api/notifications/prefs` | `{ sendTime, mode }` (PUT) | `{ sendTime, mode }` |

#### `PushRoute` — `/api/push/*`

| Constructor | Method + Path | Body | Response |
|---|---|---|---|
| `PushRoute_Subscribe` | `POST /api/push/subscribe` | `{ endpoint, p256dh, auth, userAgent?, timezone }` | `204` |
| `PushRoute_Unsubscribe` | `POST /api/push/unsubscribe` | `{ endpoint }` | `204` |

`timezone` on `subscribe` is the device's
`Intl.DateTimeFormat().resolvedOptions().timeZone`. The planned behavior is
to refresh `users.timezone` from login and subscribe flows; check the current
handler source before relying on that behavior.

---

## URL summary

```
/                              Home (SPA)
/calendar                      Calendar (SPA)
/history                       History (SPA)
/settings                      Settings (SPA)
/login                         Login (SPA)
/signup                        Signup (SPA)

/vapid-public-key              text/plain — VAPID pubkey
/api/auth/register             POST
/api/auth/login                POST
/api/auth/logout               POST
/api/auth/me                   GET
/api/period/status             GET
/api/period/entries            GET, POST
/api/period/entry/:id          PATCH, DELETE
/api/notifications/prefs       GET, PUT
/api/push/subscribe            POST
/api/push/unsubscribe          POST

/static/*                      Obelisk static asset handler (manifest, sw.js, css, icons)
/missing                       Obelisk fallback 404
```

`/static/*` is wired by Obelisk's backend; it does not appear in
`BackendRoute`.

---

## Frontend API calls — type-safe URLs (rule)

**Never hard-code an API URL string in `frontend/`.** Build the typed route
value from the GADT and render it through the shared encoder. The
compiler must catch every URL change.

Forbidden:

```haskell
XhrRequest "GET" "/api/auth/me" def              -- ❌
postJson "/api/auth/login" reqEv                 -- ❌
```

Required:

```haskell
import Common.Route
  ( BackendRoute (..), ApiRoute (..), AuthRoute (..)
  )
import Frontend.Api (apiUrl)
import Obelisk.Route (pattern (:/))

XhrRequest "GET"
  (apiUrl (BackendRoute_Api :/ ApiRoute_Auth :/ AuthRoute_Me :/ ()))
  def

postJson
  (apiUrl (BackendRoute_Api :/ ApiRoute_Auth :/ AuthRoute_Login :/ ()))
  reqEv
```

### The `apiUrl` helper

Single home: [`frontend/src/Frontend/Api.hs`](../frontend/src/Frontend/Api.hs).

```haskell
apiUrl :: R BackendRoute -> Text
```

Implementation contract:

1. Run `checkEncoder fullRouteEncoder` once (top-level CAF; the result is
   a constant). Pattern-match `Right`; an invalid encoder is a programmer
   error caught at startup, not a runtime condition — let the pattern
   failure be the diagnostic.
2. Render with Obelisk's `renderBackendRoute` over the validated encoder.

The same approach already runs in
[`frontend/src-bin/main.hs`](../frontend/src-bin/main.hs) for the
top-level Obelisk encoder; `Frontend.Api` does the same for
backend-only URL rendering and exposes a single function.

### Path parameters

Slot in via the GADT — no string interpolation:

```haskell
apiUrl
  (BackendRoute_Api :/ ApiRoute_Period :/
   PeriodRoute_Entry :/ (PeriodEntryId 42, ()))
-- => "/api/period/entry/42"
```

### Query parameters and method

`apiUrl` only contributes the URL path. Query strings (`?limit=`,
`?before=`) are appended at the call-site for now (see *Encoder strategy*
below). HTTP method comes from how the `XhrRequest` / `postJson` is
constructed.

---

## Encoder strategy

Single top-level `fullRouteEncoder` (`mkFullRouteEncoder`); backend arm
dispatches into `apiRouteEncoder` → per-area encoders. Path-segment
composition reads as `PathSegment "api" . PathSegment "auth" . ...`.

Two constructors with the same first `PathSegment` literal fail at check
time with `enumEncoder: ambiguous encodings detected` — that is why the
per-id period route is `entry` (singular), not `entries`.

Query-string encoding for list endpoints (`?limit=`, `?before=`) stays in
the handler with `Snap.getQueryParam`; the route GADTs stay simple. If
some route accumulates enough query params to be worth typing, lift them
into the encoder rather than peppering call-sites with manual
concatenation.
