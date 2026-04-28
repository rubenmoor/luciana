# routes.md

URL routing for Luciana. All routes — frontend pages and backend API — are defined in [`common/src/Common/Route.hs`](../common/src/Common/Route.hs) so the backend dispatches by the same types the frontend navigates with.

Today the file holds only the Obelisk scaffold (`BackendRoute_Missing`, `FrontendRoute_Main`). This plan specifies the target shape; nothing here is implemented yet.

Note: `obelisk-route` encodes only the **path** (and optionally query). Request bodies (JSON) are not part of the route value — they're parsed in handlers using `aeson`.

---

## How `obelisk-route` works

A short recap of the library's vocabulary, since the rest of this file leans on it. Authoritative source: the upstream guide at [`obelisk/docs/introduction.md`](https://github.com/obsidiansystems/obelisk/blob/master/docs/introduction.md) — anything below is a summary of that.

### Bidirectional encoders

A route definition is a single `Encoder` that goes both ways:

- `decoded → encoded` (build a URL from a typed route value)
- `encoded → decoded` (parse an incoming URL back to a typed route value)

The library guarantees, at construction time, that `decode . encode = pure` ([introduction.md § Motivation](https://github.com/obsidiansystems/obelisk/blob/master/docs/introduction.md#motivation)). This is why route changes show up as compile errors at every call-site rather than at runtime: there is no separate "route table", just one total function.

`obelisk-route` covers `path` and `query` only; method, headers, and body are not part of the route value (so we dispatch on HTTP method inside handlers).

### Routes as GADTs and `R`

Each logical route is a constructor of a kind-`* -> *` GADT. The type parameter is the value the route carries — `()` for a parameterless page, `(PeriodEntryId, ())` for a route with a path param, `R SubRoute` for a nested set of routes, etc.

`R f` is a type alias for `DSum f Identity` from [`dependent-sum`](https://hackage.haskell.org/package/dependent-sum/docs/Data-Dependent-Sum.html#t:DSum). It hides the GADT's type index existentially so we can talk about "some route" without picking a concrete index. The pattern synonym `c :/ v` is how we construct/destructure those values: `FrontendRoute_Home :/ ()`, `PeriodRoute_Entry :/ (PeriodEntryId 42, ())`. ([introduction.md § Aside: `R`](https://github.com/obsidiansystems/obelisk/blob/master/docs/introduction.md#aside-r))

The `deriveRouteComponent` Template Haskell call at the bottom of `Common.Route` emits the `GShow`, `GEq`, `GCompare`, `UniverseSome` instances that `pathComponentEncoder` needs for each GADT.

### `PageName` is the encoded form

`type PageName = ([Text], Map Text (Maybe Text))` — a list of path segments plus a map of query parameters. Every route encoder eventually produces a `PageName`; the framework concatenates segments with `/` and serialises the query map.

### Building encoders compositionally

Encoders compose with `(.)`. The library ships small primitives we glue together:

- `unitEncoder x` — fixed value; used for `()`-carrying constructors with no path/query data
- `pathComponentEncoder` — dispatches on a GADT, asking for one `SegmentResult` per constructor
- `pathParamEncoder item rest` — consumes one path segment as a typed value, then continues with `rest`
- `queryOnlyEncoder`, `singlePathSegmentEncoder`, `unsafeTshowEncoder`, etc. — see the [Hackage-style module list](https://github.com/obsidiansystems/obelisk/blob/master/lib/route/src/Obelisk/Route.hs) and [introduction.md § Query Parameters](https://github.com/obsidiansystems/obelisk/blob/master/docs/introduction.md#query-parameters)

### `SegmentResult`: `PathEnd` vs `PathSegment`

`pathComponentEncoder` requires us to return a `SegmentResult` for each GADT constructor:

- `PathEnd e` — the path stops here; `e` encodes the constructor's value into the query map only.
- `PathSegment t e` — emit the literal text `t` as the next path segment, then let `e` encode the rest of the route into a `PageName`.

Two constructors with the same `PathSegment` literal will fail at check time with `enumEncoder: ambiguous encodings detected` — that is the constraint that forced us to use `entry` (singular) for the per-id route alongside `entries`. ([introduction.md § Nested Routes](https://github.com/obsidiansystems/obelisk/blob/master/docs/introduction.md#nested-routes))

### `FullRoute` and `mkFullRouteEncoder`

The Obelisk scaffold ties two route GADTs (backend + frontend) together via `FullRoute`. `mkFullRouteEncoder` takes:

1. a fallback `R (FullRoute br fr)` for unparseable URLs (`BackendRoute_Missing :/ ()` here),
2. a `BackendRoute -> SegmentResult …` function,
3. a `FrontendRoute -> SegmentResult …` function,

and returns a single top-level encoder. The frontend arm is automatically wrapped in `ObeliskRoute` so that framework-internal paths (`/static/*`, `/ghcjs/*`, `/jsaddle/*`, `/version`) coexist with our own without us having to enumerate them. ([introduction.md § Nested Routes](https://github.com/obsidiansystems/obelisk/blob/master/docs/introduction.md#nested-routes))

### Where these types live

- Library: [`obsidiansystems/obelisk` → `lib/route/src/Obelisk/Route.hs`](https://github.com/obsidiansystems/obelisk/blob/master/lib/route/src/Obelisk/Route.hs) (re-exported by `Obelisk.Route`)
- Frontend helpers (`subRoute_`, `RoutedT`, `askRoute`): [`lib/route/src/Obelisk/Route/Frontend.hs`](https://github.com/obsidiansystems/obelisk/blob/master/lib/route/src/Obelisk/Route/Frontend.hs)
- Template Haskell: `Obelisk.Route.TH.deriveRouteComponent`

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
| `PeriodRoute_Entries` | `GET / POST /api/period/entries` | `{ startDate, endDate?, notes? }` (POST) — GET takes query: `?limit=`, `?before=` | GET: `[{ id, startDate, endDate, notes }]` / POST: `201 { id }` |
| `PeriodRoute_Entry` | `PATCH/DELETE /api/period/entry/:id` | `{ startDate?, endDate?, notes? }` (PATCH) | `204` / `404` |

The `:id` segment is encoded via `pathParamEncoder` over a `PeriodEntryId` newtype.

```haskell
data PeriodRoute :: * -> * where
  PeriodRoute_Status  :: PeriodRoute ()
  PeriodRoute_Entries :: PeriodRoute ()                  -- GET, POST
  PeriodRoute_Entry   :: PeriodRoute (PeriodEntryId, ())
```

`PeriodRoute_Entries` covers both list and create; the handler dispatches by HTTP method. The single-entry route uses a distinct first segment (`entry`, singular) because `obelisk-route`'s `pathComponentEncoder` rejects two constructors that share their first path segment — so `/entries` and `/entries/:id` cannot both live on the same `PeriodRoute`.

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
/api/period/entry/:id          PATCH, DELETE
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

Path-parameter encoding (`PeriodEntryId`) goes through `pathParamEncoder` with `unsafeTshowEncoder` over `PeriodEntryId` (a `newtype Int64` with `Show`/`Read`). `PeriodEntryId` is defined in `Common.Route` for the route layer; the backend has its own beam-derived `PeriodEntryId` in `Backend.Schema.PeriodEntry` and converts at the handler boundary.

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
