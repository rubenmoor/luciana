# authentication.md

Status: partial

Username + password authentication with server-side sessions. Multi-user from day one (per `goal.md` § Basic features). Schema lives in [`schema.md`](schema.md); library choices in [`architecture.md`](architecture.md).

No email is collected. The user picks any username they like (subject to the rules in [Validation](#validation) below); we do not attempt to verify identity outside of the password.

## Scope

In v1:

- Self-serve registration with username + password.
- Login, logout, "who am I" probe.
- Server-issued session cookie, validated per request.
- Password hashing with **bcrypt**.
- Basic rate limiting on login.

Deferred to a later plan:

- Password reset flow. Without email there is no self-serve recovery path; out of scope until we decide whether to add email or a recovery code mechanism.
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
| `auth/register` | POST | `{ username, password, locale, timezone }` | `200 RegisterResult` (+ `Set-Cookie` on `Ok`), `429` if rate-limited |
| `auth/login` | POST | `{ username, password }` | `200 LoginResult` (+ `Set-Cookie` on `Ok`), `429` if rate-limited |
| `auth/logout` | POST | — | `204`, clears cookie |
| `auth/me` | GET | — | `200 { id, username, locale, timezone }` or `401` (no / expired session) |

Application-level outcomes — invalid credentials, username taken — are
encoded as JSON in the response body, not HTTP status codes. Rate
limiting, by contrast, is an HTTP-level concern and surfaces as `429
Too Many Requests` with no body. Other non-2xx: `400` for malformed
JSON, `401` only on `auth/me` (the missing-session case the frontend
already treats as `AuthAnon`), `5xx` for server errors.

```haskell
-- Common.Auth
data LoginResult    = LoginOk UserResponse | InvalidCredentials
data RegisterResult = RegisterOk UserResponse | UsernameTaken
```

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

In-memory token bucket keyed by `(remoteAddr, username)`:

- 5 failed login attempts per 15 minutes per key → respond with `429
  Too Many Requests` (empty body).
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

### Cross-links between login and signup

The login page renders a small footer line — *"Not registered? Sign up here."* — where "Sign up here" is a link (Obelisk `routeLink`) to `FrontendRoute_Signup`. Symmetrically, the signup page links back to `FrontendRoute_Login` with *"Already have an account? Sign in."* This avoids dead-ends for users who land on the wrong page.

## Module layout

Per-route handlers follow the convention in [`route-modules.md`](route-modules.md):
each route gets its own module exporting `handler` (backend) or `page`
(frontend). Cross-cutting helpers sit in sibling modules.

```
common/src/Common/
├── Auth.hs              -- Username, Password (newtypes with smart constructors),
│                           LoginResult, RegisterResult
└── Route.hs             -- + AuthRoute sub-route

backend/src/Backend/
├── Auth.hs              -- AuthEnv, requireUser, issueAndSetSession,
│                           token + snap helpers (cross-cutting)
├── Auth/Cookie.hs       -- cookie issue/parse/clear
├── Auth/Login.hs        -- POST /api/auth/login
├── Auth/Logout.hs       -- POST /api/auth/logout
├── Auth/Me.hs           -- GET  /api/auth/me
├── Auth/RateLimit.hs    -- in-memory bucket
├── Auth/Register.hs     -- POST /api/auth/register
└── Auth/Session.hs      -- DB ops over Backend.Schema.Session

frontend/src/Frontend/
├── Auth.hs              -- AuthState, currentAuth, login/logout actions
├── Login.hs             -- login page (loginWidget inline, unexported)
├── Signup.hs            -- signup page (signupWidget inline, unexported)
└── Widget/Form.hs       -- shared form helpers (labelled, formEl, submitButtonClass)
```

## Validation

Performed in `Common.Auth` so frontend and backend agree:

- Username: any non-empty string after trimming surrounding whitespace, ≤ 64 chars. Case-sensitive on storage but compared case-insensitively for the uniqueness check (the unique index is on `lower(username)` — see [`schema.md`](schema.md)). No restrictions on which characters appear; the user can pick whatever they want.
- Password: any non-empty string, ≤ 200. No composition rules. (Minimum length of 8 removed to avoid 'stuck' UI on short inputs).

## Open

- Self-serve registration vs. invite-only: assume self-serve for v1 since this is intended for the user's own use plus anyone she shares it with. Easy to gate later by adding an `invites` table and requiring an invite token on `auth/register`.
- Multi-device session listing / "log out everywhere": out of scope for v1. The data model (`sessions.user_id`) supports it when we want it.
