# authentication.md

Status: implemented

Email + password authentication with server-side sessions. Multi-user from day one (per `goal.md` § Basic features). Schema lives in [`schema.md`](schema.md); library choices in [`architecture.md`](architecture.md).

## Scope

In v1:

- Self-serve registration with email + password.
- Login, logout, "who am I" probe.
- Server-issued session cookie, validated per request.
- Password hashing with **bcrypt**.
- Basic rate limiting on login.

Deferred to a later plan:

- Email verification (no SMTP wiring yet — registrations are trusted).
- Password reset flow (no SMTP).
- OAuth / social login.
- 2FA.
- Account deletion UI (the cascade delete is in the schema; UI comes later).

## Password hashing

`bcrypt` (Hackage `bcrypt` package, OpenBSD impl). Cost factor **12** — ~250 ms on commodity hardware in 2026, comfortably above brute-force economics for the threat model and below user-noticeable latency on login.

```haskell
hashPassword :: MonadIO m => Text -> m (Maybe ByteString)
hashPassword pw =
  liftIO $ hashPasswordUsingPolicy
             (slowerBcryptHashingPolicy { preferredHashCost = 12 })
             (encodeUtf8 pw)

verifyPassword :: Text -> ByteString -> Bool
verifyPassword pw hash = validatePassword (encodeUtf8 pw) hash
```

We pick bcrypt over Argon2 to avoid the libsodium C dep; revisit if cost-tuning becomes a real bottleneck.

## Session tokens

Opaque, random, server-issued. **No HMAC, no JWT** — the token is a database key, not a payload.

- Generation: `getEntropy 32` from `cryptonite`, base64url-encoded → 43-char ASCII.
- Storage: `sessions.token_hash = SHA-256(token_bytes)`. Raw token is never persisted server-side; a DB leak yields no usable cookies.
- Lookup: hash the cookie value, single-row lookup on the unique `token_hash` index, check `expires_at > now()`.
- Lifetime: 30 days sliding (extended on each request that's older than 24 h since last extension; avoids hammering the DB on every request).
- Logout: `DELETE FROM sessions WHERE token_hash = $1`.
- Cleanup: a small background thread deletes `expires_at < now()` rows once an hour.

## Cookie

Single cookie, `luciana_session`:

| Flag | Value | Why |
|---|---|---|
| `HttpOnly` | yes | Inaccessible from JS — XSS can't exfiltrate the token. |
| `Secure` | yes | TLS only. Dev exception via `config/backend/cookie-secure=false`. |
| `SameSite` | `Strict` | Same-origin SPA; no third-party context where we'd want cross-site auth. Also our CSRF defence — see below. |
| `Path` | `/` | All routes. |
| `Max-Age` | session lifetime | Persistent cookie so PWA users stay logged in across launches. |

## CSRF

`SameSite=Strict` is the primary defence: browsers do not send the cookie on cross-site requests. Combined with same-origin-only API endpoints, this is sufficient for v1. We will *not* add a CSRF token. If we later add cross-origin embedding, add a double-submit token at that point.

## Routes

Extend `Common.Route.BackendRoute` with an `Auth` sub-route. Signatures (subject to refinement during implementation):

| Route | Method | Body | Response |
|---|---|---|---|
| `auth/register` | POST | `{ email, password, locale, timezone }` | `204` + `Set-Cookie`, or `409` if email taken |
| `auth/login` | POST | `{ email, password }` | `204` + `Set-Cookie`, or `401` |
| `auth/logout` | POST | — | `204`, clears cookie |
| `auth/me` | GET | — | `{ id, email, locale, timezone }` or `401` |

`timezone` on register comes from `Intl.DateTimeFormat().resolvedOptions().timeZone` on the client. Refreshed on every successful login (UPDATE `users.timezone`) so device travel is picked up without a separate endpoint.

## Server middleware

```haskell
-- Backend.Auth
requireUser :: Snap UserId
requireUser = do
  cookie <- getCookie "luciana_session" >>= maybe (failWith Unauthorized) pure
  let h = sha256 (cookieValue cookie)
  mUser <- runDb $ lookupSessionUser h
  case mUser of
    Just (uid, _) -> bumpSessionIfStale uid >> pure uid
    Nothing       -> failWith Unauthorized
```

API handlers that need authentication call `requireUser` first and receive the `UserId` to scope queries with.

## Rate limiting

In-memory token bucket keyed by `(remoteAddr, email)`:

- 5 failed login attempts per 15 minutes per key → respond `429 Too Many Requests`.
- Successful login resets the bucket.
- Plain `IORef (HashMap (Text, Text) Bucket)` behind an MVar is fine at our scale; revisit if we ever run multiple backend instances (would move to Postgres or Redis).

Registration is rate-limited the same way, keyed by `remoteAddr` only, to deter signup-spam without locking out legitimate retries.

## Frontend

`Frontend.Auth` exposes:

```haskell
data AuthState
  = AuthLoading
  | AuthAnon
  | AuthSignedIn User

currentAuth :: m (Dynamic t AuthState)
```

Implemented by hitting `auth/me` on app start and re-fetching after login/logout events. Routes are guarded in `Frontend.hs`'s `subRoute_` dispatch:

```haskell
case route of
  FrontendRoute_Home    -> requireSignedIn homeWidget
  FrontendRoute_Login   -> loginWidget
  FrontendRoute_Signup  -> signupWidget
```

`requireSignedIn` redirects to `FrontendRoute_Login` when `AuthAnon`.

## Module layout

```
common/src/Common/
├── Auth.hs              -- Email, Password (newtypes with smart constructors), AuthError
└── Route.hs             -- + AuthRoute sub-route

backend/src/Backend/
├── Auth.hs              -- requireUser, login, register, logout, password ops
├── Auth/Cookie.hs       -- cookie issue/parse/clear
├── Auth/RateLimit.hs    -- in-memory bucket
└── Auth/Session.hs      -- DB ops over Backend.Schema.Session

frontend/src/Frontend/
├── Auth.hs              -- AuthState, currentAuth, login/logout actions
└── Auth/Widget.hs       -- loginWidget, signupWidget
```

## Validation

Performed in `Common.Auth` so frontend and backend agree:

- Email: non-empty, contains `@`, ≤ 254 chars. No regex theatrics; the verification step (deferred) is the real check.
- Password: 8 ≤ length ≤ 200. No composition rules (per current NIST guidance — length over complexity).

## Open

- Self-serve registration vs. invite-only: assume self-serve for v1 since this is intended for the user's own use plus anyone she shares it with. Easy to gate later by adding an `invites` table and requiring an invite token on `auth/register`.
- Multi-device session listing / "log out everywhere": out of scope for v1. The data model (`sessions.user_id`) supports it when we want it.
