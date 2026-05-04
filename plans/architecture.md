# architecture.md

Status: spec

This is a progressive web app:

* a web server with postgres database
* a client, serving html, using tailwind-css
* provide a user-experience similar to a native app and show notifications
    * on android devices
    * on iphones
* build with Haskell, full-stack
* using obsdidiansystems obelisk

## Layering

```
┌─ frontend/  (GHCJS, reflex-dom)         FRP UI, service worker registration, push subscription
│      │  HTTP/JSON over BackendRoute_Api
├─ common/   (GHC + GHCJS)                shared types, route definitions, JSON instances, period logic
│      │
├─ backend/  (GHC, Snap via Obelisk)      HTTP handlers, session, push dispatch, DB access
│      │
└─ Postgres                               users, period entries, push subscriptions, notification prefs
```

`common/` is the canonical home for *pure* domain logic (cycle/phase computation, status colour). Both sides import it so the frontend can render predictions optimistically and the backend can validate writes and decide notification state.

## Server

The Obelisk scaffold already gives us **Snap** plus `obelisk-backend` and `obelisk-route`. Recommended additions:

| Concern | Library | Why |
|---|---|---|
| Frontend page routing | `obelisk-route` (already in) | Type-safe `FrontendRoute` GADT shared with the backend; SPA navigation falls out for free. |
| JSON API description | `servant` (`Common.Api`) | Single API type drives the server, the frontend client, JSON shapes, method, status, and Content-Type. See [`backend-spec.md`](backend-spec.md). |
| HTTP handler glue | `servant-snap` over `snap-core` / `snap-server` | `serveSnapWithContext` plugs servant into the Snap pipeline Obelisk already gives us — no need to introduce warp. Pattern mirrors the book-engine project. |
| JSON | `aeson` | De-facto standard; pairs naturally with `deriving via` for newtype wrappers. |
| Logging | `co-log` or `katip` | `co-log` is lighter and composes cleanly with `relude`'s `WithLog`; `katip` if we want structured/JSON logs and severity contexts out of the box. |
| Env / config | `obelisk-executable-config-lookup` (already in) + `envparse` for typed env vars at boot | `config/` directory for static keys; env for secrets injected by deploy. |
| Push notifications | `web-push` (Hackage) | VAPID push to browser endpoints; works for Android Chrome and iOS Safari 16.4+ once the PWA is installed. |
| Scheduler (daily morning push) | plain `forkIO` with `Data.Time`, or `tickle` | App-internal scheduler is enough; cron-like external scheduling is overkill at this scale. |
| Session / auth | Hand-rolled: opaque random token in cookie, SHA-256 hash in DB. See [`authentication.md`](authentication.md). | Snap's `Snap.Snaplet.Session` ties us to snaplets, which Obelisk doesn't really use. Servant-auth would duplicate `obelisk-route`. |
| Password hashing | `bcrypt` (cost 12) | Pure-enough for our needs; avoids the libsodium C dep that Argon2 would bring. |

## Database

**Postgres.** Libraries:

| Library | Notes |
|---|---|
| `beam` + `beam-postgres` | No Template Haskell — schemas are records with `Beamable` instances, so type errors point at our code and GHCJS / cross-compilation stays painless. Composable, SQL-shaped query DSL with first-class joins, subqueries, aggregates, window functions. `beam-postgres` is the mature flagship backend. |
| `beam-migrate` | Diff schema values to produce migrations; usable as a library for our own bootstrap step. |
| `postgresql-simple` | Transitively present via `beam-postgres`; reach for it directly only as an escape hatch for the rare query beam can't express. |

### Schema

Defined in [`schema.md`](schema.md): tables `users`, `sessions`, `period_entries`, `push_subscriptions`, `notification_prefs`.

### Migrations

`beam-migrate` produces migration steps by diffing the in-Haskell schema against the live DB. For dev we apply diffs automatically at boot; for production we commit the generated SQL files (or serialised `MigrationSteps`) and run them through a bootstrap step in the backend executable so deploys are reproducible.

### Connection pool

`resource-pool` directly, wrapping `Database.PostgreSQL.Simple.Connection` from `postgresql-simple` (which `beam-postgres` runs over). Pool size + DB credentials read from `config/backend/`.

## Frontend (for completeness)

- `reflex-dom-core` (already in) — FRP widgets.
- **Tailwind CSS** — bundle via a small Node build invoked from `static/` or generated at Nix build time; resulting CSS lives under `static/`.
- Service worker — plain JS in `static/sw.js`, registered from `static/lib.js` (the FFI bridge per `obelisk.md`).
- Client-side routing — `obelisk-route` already covers it.

## i18n

- `Common.I18n` module exposing `Locale` and `translate :: Locale -> Key -> Text`.
- Keys defined in Haskell so FE and BE share them (e.g., notification body strings rendered server-side).
- Start with German + English; pick locale from user pref first, browser `Accept-Language` second.

## PWA / native-feel

Pure PWA, "Add to Home Screen" only — no app store, no Obelisk Android/iOS bundles:

- `manifest.webmanifest` under `static/` declares name, icons, `display: standalone`, theme colour.
- Service worker handles install, offline shell, and `push` events.
- iOS: requires the user to "Add to Home Screen" before push works; covered by an in-app prompt.
- Android: install banner appears automatically once engagement criteria are met.

## Push-notification flow

1. Frontend asks `Notification.requestPermission()`, then subscribes via the service worker with the server's VAPID public key (served from `config/common/`).
2. Frontend reads the device IANA timezone (`Intl.DateTimeFormat().resolvedOptions().timeZone`) and POSTs it together with the subscription (`endpoint`, `keys`) to `BackendRoute_Api/push/subscribe`. Re-sent on every login so device travel updates the stored zone.
3. A backend ticker (every minute) computes each user's local time from their stored IANA zone, selects users whose `send_time` matches now and whose status meets their `mode` filter, then dispatches via `web-push`.
4. Failed subscriptions (HTTP 410 Gone) are pruned.
