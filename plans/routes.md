# routes.md

URL routing for Luciana. All routes — frontend pages and backend API — are defined in [`common/src/Common/Route.hs`](../common/src/Common/Route.hs) so the backend dispatches by the same types the frontend navigates with.

Today the file holds only the Obelisk scaffold (`BackendRoute_Missing`, `FrontendRoute_Main`). This plan specifies the target shape; nothing here is implemented yet.

Note: `obelisk-route` encodes only the **path** (and optionally query). Request bodies (JSON) are not part of the route value — they're parsed in handlers using `aeson`.

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

Routes marked "required" redirect to `/login` when `AuthState = AuthAnon` (see [`authentication.md`](authentication.md) § Frontend).

```haskell
data FrontendRoute :: * -> * where
  FrontendRoute_Home     :: FrontendRoute ()
  FrontendRoute_Calendar :: FrontendRoute ()
  FrontendRoute_History  :: FrontendRoute ()
  FrontendRoute_Settings :: FrontendRoute ()
  FrontendRoute_Login    :: FrontendRoute ()
  FrontendRoute_Signup   :: FrontendRoute ()
```

---

## Backend routes

The backend's job, beyond serving the SPA, is the JSON API plus a couple of special endpoints.

```haskell
data BackendRoute :: * -> * where
  BackendRoute_Missing :: BackendRoute ()                 -- Obelisk default 404
  BackendRoute_Api     :: BackendRoute (R ApiRoute)       -- /api/*
  BackendRoute_Vapid   :: BackendRoute ()                 -- /vapid-public-key (text/plain)
```

`BackendRoute_Vapid` is a tiny GET that returns the server's VAPID public key so the service worker can subscribe; kept outside `Api` so it can be unauthenticated and cacheable.

### `ApiRoute` — JSON endpoints

```haskell
data ApiRoute :: * -> * where
  ApiRoute_Auth          :: ApiRoute (R AuthRoute)
  ApiRoute_Period        :: ApiRoute (R PeriodRoute)
  ApiRoute_Notifications :: ApiRoute (R NotificationsRoute)
  ApiRoute_Push          :: ApiRoute (R PushRoute)
```

#### `AuthRoute` — `/api/auth/*`

Mirrors [`authentication.md`](authentication.md) § Routes.

| Constructor | Method + Path | Body | Response | Auth |
|---|---|---|---|---|
| `AuthRoute_Register` | `POST /api/auth/register` | `{ email, password, locale, timezone }` | `204 + Set-Cookie` / `409` | anon |
| `AuthRoute_Login` | `POST /api/auth/login` | `{ email, password }` | `204 + Set-Cookie` / `401` / `429` | anon |
| `AuthRoute_Logout` | `POST /api/auth/logout` | — | `204` (clears cookie) | required |
| `AuthRoute_Me` | `GET /api/auth/me` | — | `{ id, email, locale, timezone }` / `401` | required |

#### `PeriodRoute` — `/api/period/*`

| Constructor | Method + Path | Body | Response |
|---|---|---|---|
| `PeriodRoute_Status` | `GET /api/period/status` | — | `{ phase: Green/Yellow/Red, dayInCycle, nextExpected }` |
| `PeriodRoute_Entries` | `GET /api/period/entries` | — (query: `?limit=`, `?before=`) | `[{ id, startDate, endDate, notes }]` |
| `PeriodRoute_NewEntry` | `POST /api/period/entries` | `{ startDate, endDate?, notes? }` | `201 { id }` |
| `PeriodRoute_Entry` | `PATCH/DELETE /api/period/entries/:id` | `{ startDate?, endDate?, notes? }` (PATCH) | `204` / `404` |

The `:id` segment is encoded via `pathParamEncoder` over a `PeriodEntryId` newtype.

```haskell
data PeriodRoute :: * -> * where
  PeriodRoute_Status   :: PeriodRoute ()
  PeriodRoute_Entries  :: PeriodRoute ()                  -- GET (with optional query)
  PeriodRoute_NewEntry :: PeriodRoute ()                  -- POST
  PeriodRoute_Entry    :: PeriodRoute (PeriodEntryId, ())
```

(`PeriodRoute_Entries` and `PeriodRoute_NewEntry` share a path; the handler dispatches by HTTP method. Splitting them at the route level would force two URLs and gain nothing.)

#### `NotificationsRoute` — `/api/notifications/*`

| Constructor | Method + Path | Body | Response |
|---|---|---|---|
| `NotificationsRoute_Prefs` | `GET / PUT /api/notifications/prefs` | `{ sendTime, mode }` (PUT) | `{ sendTime, mode }` |

```haskell
data NotificationsRoute :: * -> * where
  NotificationsRoute_Prefs :: NotificationsRoute ()
```

#### `PushRoute` — `/api/push/*`

| Constructor | Method + Path | Body | Response |
|---|---|---|---|
| `PushRoute_Subscribe` | `POST /api/push/subscribe` | `{ endpoint, p256dh, auth, userAgent?, timezone }` | `204` |
| `PushRoute_Unsubscribe` | `POST /api/push/unsubscribe` | `{ endpoint }` | `204` |

`timezone` on `subscribe` is the device's `Intl.DateTimeFormat().resolvedOptions().timeZone`, also written through to `users.timezone` on every login (see [`authentication.md`](authentication.md)).

```haskell
data PushRoute :: * -> * where
  PushRoute_Subscribe   :: PushRoute ()
  PushRoute_Unsubscribe :: PushRoute ()
```

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
/api/period/entries/:id        PATCH, DELETE
/api/notifications/prefs       GET, PUT
/api/push/subscribe            POST
/api/push/unsubscribe          POST

/static/*                      Obelisk static asset handler (manifest, sw.js, css, icons)
/missing                       Obelisk fallback 404
```

`/static/*` is provided by Obelisk's backend wiring; it does not appear in `BackendRoute`.

---

## Encoder strategy

The `fullRouteEncoder` in `Common.Route` is a single `mkFullRouteEncoder` whose backend arm dispatches on `BackendRoute_Api` into `apiRouteEncoder`, which in turn dispatches on each `ApiRoute_*` into the per-area encoder. Encoders compose as `PathSegment "api" . PathSegment "auth" . ...`.

Path-parameter encoding (`PeriodEntryId`) goes through `pathParamEncoder readMaybe show` over `PeriodEntryId` (a `newtype Int64`).

Query-string encoding for list endpoints (`?limit=`, `?before=`) is handled in the handler with Snap's `getQueryParam`, not in the route encoder — keeps the route GADT shape simple and matches how most Obelisk projects do pagination.

---

## Implementation ordering

Suggested order when we move from plan to code:

1. Add `BackendRoute_Api` + empty `ApiRoute` GADT and wire `apiRouteEncoder`. Verify `ob run` still serves the frontend.
2. Add `AuthRoute` and the four auth handlers. Brings up registration/login/logout end-to-end (depends on [`authentication.md`](authentication.md) and [`schema.md`](schema.md)).
3. Add `FrontendRoute_Login` and `FrontendRoute_Signup` widgets; wire `requireSignedIn` guard around `FrontendRoute_Home`.
4. Add `PeriodRoute` + handlers. Frontend home widget switches to real data.
5. Add `NotificationsRoute` + settings page.
6. Add `BackendRoute_Vapid` + `PushRoute` + service-worker registration. Last, because it depends on everything above.
