# backend.md

Status: spec

How the backend exposes its JSON API as a servant type, and how shared
state (DB pool, rate limiter, cookie config) is threaded into handlers.

The current backend dispatches `R ApiRoute` to per-handler `Snap ()`
functions that hand-roll method dispatch, JSON parsing, response
Content-Type, and error responses. Switching to servant collapses all
of that into the API type; cross-cutting concerns (auth, rate
limiting) become combinators in the type rather than lines at the top
of every handler.

The book-engine project follows the same pattern — see
`backend/src/Backend.hs` and `common/src/Common/Api.hs` in that repo
for the wiring this plan mirrors.

Two changes shipped together:

1. Move the JSON API description from `Common.Route` GADTs into a
   servant type `RoutesApi` in `Common.Api`. `Common.Route` keeps the
   *frontend* page GADT and a single catch-all `BackendRoute_Api` arm.
2. Run handlers in `App = ReaderT Env Servant.Handler`. Plug servant
   into Obelisk's Snap pipeline with `serveSnapWithContext`. Add two
   custom combinators — `AuthRequired "session"` and
   `RateLimit "<bucket>"` — so cookie resolution and 429-throwing
   never appear in handler bodies.

(1) deletes the boilerplate (method, JSON, Content-Type, 400 on
malformed body) by encoding it once at the type level. (2) lets every
handler share a monad and lifts auth + rate limiting out of every
handler's preamble.

## API type

`Common.Api` (new module):

```haskell
type RoutesApi = "api" :>
  (    "auth"          :> RoutesAuth
  :<|> "period"        :> RoutesPeriod
  :<|> "notifications" :> RoutesNotifications
  :<|> "push"          :> RoutesPush
  )

type RoutesAuth =
       RateLimit "register"
         :> "register" :> ReqBody '[JSON] RegisterRequest
                       :> Post '[JSON] (Headers '[Header "Set-Cookie" Text] RegisterResult)
  :<|> RateLimit "login"
         :> "login"    :> ReqBody '[JSON] LoginRequest
                       :> Post '[JSON] (Headers '[Header "Set-Cookie" Text] LoginResult)
  :<|> AuthRequired "session" :> "logout" :> Post '[JSON] (Headers '[Header "Set-Cookie" Text] NoContent)
  :<|> AuthRequired "session" :> "me"     :> Get  '[JSON] UserResponse

type RoutesPeriod =
       AuthRequired "session" :> "status"  :> Get  '[JSON] PeriodStatus
  :<|> AuthRequired "session" :> "entries" :> Get  '[JSON] [PeriodEntry]
  :<|> AuthRequired "session" :> "entries" :> ReqBody '[JSON] PeriodEntryNew :> Post '[JSON] PeriodEntryId
  :<|> AuthRequired "session" :> "entry"   :> Capture "id" PeriodEntryId
                              :> ReqBody '[JSON] PeriodEntryPatch
                              :> Patch  '[JSON] NoContent
  :<|> AuthRequired "session" :> "entry"   :> Capture "id" PeriodEntryId
                              :> Delete '[JSON] NoContent
```

`AuthRequired "session"` and `RateLimit "<bucket>"` are custom
combinators (see *Auth combinator* and *Rate-limit combinator* below).
Each route type sits in `Common.Api`; the request and response types
continue to live in `Common.Auth`, `Common.Period`, etc., so JSON
instances stay in their domain modules.

Routes that need to set or clear the session cookie return
`Headers '[Header "Set-Cookie" Text] r`; servant renders the header
from the `addHeader` value. The cookie string is built by
`Backend.Auth.Cookie` exactly as today.

## App monad

`Backend.Env` (new module):

```haskell
data Env = Env
  { envPool         :: DbPool
  , envRateLimiter  :: RateLimiter
  , envCookieSecure :: Bool
  }

mkEnv :: DbPool -> IO Env
mkEnv pool = Env pool <$> newRateLimiter <*> readSecureFlag
```

`Backend.App` (new module):

```haskell
type App = ReaderT Env Handler

runApp :: Env -> App a -> Handler a
runApp = flip runReaderT

throwApp :: ServerError -> App a
throwApp = lift . throwError
```

`Servant.Handler = ExceptT ServerError IO`. `App` adds `MonadReader Env`
on top, so handlers `asks envPool` instead of taking `Env` as an
argument. Servant's `HasServer` instance for `ReaderT r Handler` needs
no special hoisting — we hoist with `hoistServerWithContext` once at
the top boundary.

### Why a Reader and not "still pass `Env` explicitly"

The current pattern — `handler :: AuthEnv -> Snap ()` and every helper
taking `aePool env` — means every new field on `Env` ripples into every
signature that touches it. With Reader, adding e.g. a Vapid keypair or
a metrics handle is a change in `Backend.Env` plus the specific
`asks envVapid` site, nothing else.

## Wiring

`Backend.hs`:

```haskell
backend :: Backend BackendRoute FrontendRoute
backend = Backend
  { _backend_run = \serve -> do
      url  <- loadDbUrl
      mode <- readMigrationMode
      withDbPool url $ \pool -> do
        runMigrations pool mode
        env <- mkEnv pool
        _   <- forkSessionCleanup env
        let ctx     = sessionAuthHandler env :. EmptyContext
            api     = Proxy :: Proxy RoutesApi
            ctxP    = Proxy :: Proxy '[AuthHandler Snap UserId]
            handler = hoistServerWithContext api ctxP (runApp env) handlers
        serve $ \case
          BackendRoute_Missing :/ _ -> pure ()
          BackendRoute_Vapid   :/ _ -> serveVapid env
          BackendRoute_Api     :/ _ -> serveSnapWithContext api ctx handler
  , _backend_routeEncoder = fullRouteEncoder
  }
```

`handlers :: ServerT RoutesApi App` is the product of every per-area
handler block, joined with `:<|>` in `Backend.Api`.

## Common.Route changes

The API GADTs (`ApiRoute`, `AuthRoute`, `PeriodRoute`,
`NotificationsRoute`, `PushRoute`) are deleted from `Common.Route`.
`BackendRoute_Api` no longer carries an inner GADT — it becomes a
catch-all that swallows the rest of the path so servant can parse it:

```haskell
data BackendRoute :: Type -> Type where
  BackendRoute_Missing :: BackendRoute ()
  BackendRoute_Api     :: BackendRoute PageName
  BackendRoute_Vapid   :: BackendRoute ()
```

`backendSegment` for `BackendRoute_Api` becomes
`PathSegment "api" pageNameEncoder` (a tail encoder that consumes the
remaining segments and query). The frontend builds API URLs through the
servant API type (see *Frontend implications* below), not through the
encoder.

`PeriodEntryId` moves out of `Common.Route` into `Common.Period` next
to the entry types; servant `Capture`s it via a `FromHttpApiData`
instance.

## Auth combinator

Servant's *generalised authentication* slot lets us declare
`AuthRequired "session"` in the API type and resolve the cookie before
the handler runs. Implementation:

```haskell
-- Backend.Auth.Combinator
type instance AuthServerData (AuthProtect "session") = UserId

sessionAuthHandler :: Env -> AuthHandler Snap UserId
sessionAuthHandler env = mkAuthHandler $ \_req -> do
  mTok <- readCookieToken
  case mTok of
    Nothing  -> throwError err401
    Just raw -> do
      let h = hashToken raw
      mFound <- liftIO $ withConn (envPool env) (\c -> lookupSession c h)
      case mFound of
        Nothing               -> throwError err401
        Just (uid, expiresAt) -> do
          now <- liftIO getCurrentTime
          when (shouldBump now expiresAt) $
            liftIO $ withConn (envPool env) (\c -> bumpSession c h (newExpiry now))
          pure uid
```

`AuthRequired "session"` is a thin alias for `AuthProtect "session"`
re-exported from `Common.Auth` so `Common.Api` doesn't import servant's
internals directly.

The combinator subsumes the handler-level `requireUser` calls and the
401 short-circuit. Routes that omit `AuthRequired "session"` (login,
register, push subscribe before auth, vapid pubkey) are anonymous by
construction.

## Rate-limit combinator

`RateLimit "<bucket>"` is a custom combinator that mirrors the auth
combinator's shape: it consumes the client IP from the request,
checks the rate limiter against `(ip, bucket)`, throws `err429` on
miss, and otherwise injects a `RateBucket` value into the handler so
routes that want to *clear* the bucket on success (login) can do so
without re-naming the key.

```haskell
-- Backend.RateLimit.Combinator
data RateLimit (bucket :: Symbol)

data RateBucket = RateBucket
  { rbKey     :: (Text, Text)     -- (ip, bucket symbol)
  , rbLimiter :: RateLimiter
  }

clearBucket :: MonadIO m => RateBucket -> m ()
clearBucket (RateBucket k l) = liftIO (RateLimit.reset l k)

instance ( KnownSymbol bucket
         , HasContextEntry context RateLimiter
         , HasServer api context
         )
      => HasServer (RateLimit bucket :> api) context where
  type ServerT (RateLimit bucket :> api) m = RateBucket -> ServerT api m
  hoistServerWithContext _ pc nt s =
    \rb -> hoistServerWithContext (Proxy :: Proxy api) pc nt (s rb)
  route _ ctx delayed = route (Proxy :: Proxy api) ctx $
    delayed `addAuthCheck` withRequest (\req -> do
      let limiter = getContextEntry ctx
          ip      = decodeUtf8 (rqClientAddr req)
          key     = (ip, T.pack (symbolVal (Proxy :: Proxy bucket)))
      ok <- liftIO (RateLimit.checkAndConsume limiter key)
      if ok then pure (RateBucket key limiter)
            else delayedFailFatal err429)
```

Wired through the servant `Context` alongside the auth handler:

```haskell
let ctx = sessionAuthHandler env :. envRateLimiter env :. EmptyContext
```

The handler signature for a route guarded by `RateLimit "login"` gains
a leading `RateBucket ->`. Routes that don't need to clear (Register)
bind it as `_`. The bucket symbol is the only string the callsite ever
spells; there is no `RateKey` to construct by hand.

## Putting it together: Login, after the migration

Without domain helpers, the handler inlines the DB lookup, password
check, and session creation against `Backend.Auth` and `Backend.Db`
primitives that already exist:

```haskell
loginH :: RateBucket -> LoginRequest -> App (Headers '[Header "Set-Cookie" Text] LoginResult)
loginH bucket req = do
  pool   <- asks envPool
  secure <- asks envCookieSecure
  mAuth  <- liftIO $ withConn pool $ \c ->
              lookupUserForLogin c (lrUsername req)
  case mAuth of
    Just (uid, hashed)
      | BCrypt.validatePassword (encodeUtf8 hashed)
                                (encodeUtf8 (unPassword (lrPassword req))) -> do
          clearBucket bucket
          tok <- liftIO generateToken
          now <- liftIO getCurrentTime
          let h = hashToken (encodeUtf8 tok)
          mUr <- liftIO $ withConn pool $ \c -> do
                   createSession c uid h (newExpiry now)
                   loadUserResponse c uid
          case mUr of
            Just ur -> pure $ addHeader (issueCookieHeader secure tok) (LoginOk ur)
            Nothing -> throwApp err500
    _ -> pure (noHeader InvalidCredentials)
```

The wins, separated:

- **API type**: method dispatch (`POST`), Content-Type, body parsing,
  the 400-on-malformed-body, and the 200-OK status all fall out of
  `ReqBody '[JSON] LoginRequest :> Post '[JSON] LoginResult`. None of
  those concerns appear in the handler body.
- **Auth combinator**: the `requireUser` / 401 cascade is gone from
  protected handlers — they just take `UserId ->`.
- **Rate-limit combinator**: the `getsRequest rqClientAddr` /
  `checkAndConsume` / `if not rateOk -> 429` block is gone — guarded
  handlers just take `RateBucket ->` and call `clearBucket` if they
  want to reset on success.
- **App monad**: no `aeRateLimiter env` / `aePool env` /
  `setSessionCookie env` plumbing.

What remains in the handler is the *route's domain logic*. We do not
introduce extra named helpers (`authenticate`, `signInAs`,
`createUser`, …) — each is called from exactly one site, so the
indirection costs more than it saves. If a step ever does end up
reused (likely candidates: `loadUserResponse`, the cookie + session
issuance pair), promote it then.

### Register, after the migration

```haskell
registerH :: RateBucket -> RegisterRequest
          -> App (Headers '[Header "Set-Cookie" Text] RegisterResult)
registerH _ req = do
  pool   <- asks envPool
  secure <- asks envCookieSecure
  let pwHashed = -- bcrypt cost 12, see Backend.Auth.Register today
        ...
  result <- liftIO $ try $ withConn pool $ \c ->
              insertUser c (rrUsername req) pwHashed (rrLocale req) (rrTimezone req)
  case result of
    Left e | sqlState e == "23505" -> pure (noHeader UsernameTaken)
           | otherwise             -> throwApp err500
    Right uid -> do
      tok <- liftIO generateToken
      now <- liftIO getCurrentTime
      let h = hashToken (encodeUtf8 tok)
      mUr <- liftIO $ withConn pool $ \c -> do
               createSession c uid h (newExpiry now)
               loadUserResponse c uid
      case mUr of
        Just ur -> pure $ addHeader (issueCookieHeader secure tok) (RegisterOk ur)
        Nothing -> throwApp err500
```

### Me, after the migration

```haskell
meH :: UserId -> App UserResponse
meH uid = do
  pool <- asks envPool
  liftIO (withConn pool (\c -> loadUserResponse c uid))
    >>= maybe (throwApp err401) pure
```

### Logout, after the migration

```haskell
logoutH :: UserId -> App (Headers '[Header "Set-Cookie" Text] NoContent)
logoutH uid = do
  pool <- asks envPool
  liftIO $ withConn pool $ \c -> deleteSessionsForUser c uid
  pure (addHeader clearSessionCookieValue NoContent)
```

## Module layout

```
backend/src/Backend/
├── Env.hs                  -- new: Env, mkEnv, env* accessors
├── App.hs                  -- new: type App = ReaderT Env Handler;
│                                   runApp, throwApp
├── Api.hs                  -- shrinks to: handlers :: ServerT RoutesApi App
│                                   wiring all per-area handler products
├── RateLimit/
│   └── Combinator.hs       -- new: data RateLimit (b :: Symbol);
│                                   HasServer instance, RateBucket,
│                                   clearBucket
├── Auth.hs                 -- shrinks. Keeps token utilities
│                                   (generateToken, hashToken),
│                                   `clearSessionCookieValue`, and
│                                   `issueCookieHeader` re-exports.
│                                   Drops AuthEnv, mkAuthEnv,
│                                   parseJsonBody, requireUser,
│                                   setSessionCookie, writeJson,
│                                   errorStatus, unauthorized
├── Auth/
│   ├── Combinator.hs       -- new: AuthProtect "session" instance,
│   │                              sessionAuthHandler
│   ├── Login.hs            -- handler :: RateBucket -> LoginRequest -> App ...
│   ├── Logout.hs
│   ├── Me.hs
│   └── Register.hs
common/src/Common/
├── Api.hs                  -- new home: RoutesApi, RoutesAuth, RoutesPeriod,
│                                  RoutesNotifications, RoutesPush
├── Auth.hs                 -- gains: AuthRequired alias for servant-auth-protect
├── Period.hs               -- new (or moved from Common.Route): PeriodEntryId,
│                                   FromHttpApiData/ToHttpApiData instances
└── Route.hs                -- shrinks: keeps FrontendRoute and a catch-all
                                    BackendRoute_Api with PageName payload;
                                    deletes ApiRoute / AuthRoute / PeriodRoute /
                                    NotificationsRoute / PushRoute
```

## Migration order

Each step compiles and the app runs after each step.

1. Add servant deps (`servant`, `servant-server`, `servant-snap`,
   `servant-auth-server` only if useful — see *Implications*) to
   `backend/luciana.cabal` and `common/luciana.cabal`. Add overrides
   in `default.nix` if the pinned set lacks any (survey first per
   `CLAUDE.md` § Adding a Haskell dependency).
2. Add `Backend.Env`, `Backend.App`, and `runApp`. Re-export `AuthEnv`
   as a deprecated synonym from `Backend.Auth`. Mechanical; nothing
   user-visible changes.
3. Write `Common.Api` with the full `RoutesApi` type. Add
   `Backend.Auth.Combinator` (`sessionAuthHandler`) and
   `Backend.RateLimit.Combinator` (`HasServer (RateLimit b :> api)`,
   `RateBucket`, `clearBucket`). Nothing wired yet — it just compiles.
4. Replace `Backend.Api.serveBackendRoute`'s body with
   `serveSnapWithContext`. Implement each handler against `App`.
   Collapse `BackendRoute_Api` to the catch-all `PageName` shape and
   delete the API GADTs from `Common.Route`. The HTTP-level behaviour
   on every endpoint must be byte-identical to today's. This is the
   one large step; review one handler per commit.
5. Rewrite `Frontend.Api` against the servant API type (see
   *Implications*). Delete dead code: the API-side route encoders,
   `Frontend.Api.apiUrl` if subsumed by servant-client, and any
   leftover Snap glue (`parseJsonBody`, `writeJson`, etc.).

Step 1 is mechanical. Steps 2–3 are additive and don't change behaviour.
Step 4 is where reviewers should slow down — it touches every handler
and the route encoder simultaneously. Step 5 is the frontend-side
cleanup that lands once the backend is stable.

## Implications of switching to servant

The switch is *not* purely a backend-internal refactor. Adopting
servant moves the source of truth for `/api/*` URLs and JSON shapes
from the obelisk-route GADTs into the servant type, which has knock-on
effects:

- **Frontend URL building** changes substrate. `Frontend.Api.apiUrl`
  rendered backend URLs from the GADT through the shared encoder
  ([`routes.md`](routes.md) § type-safe URLs); with servant, that
  encoder no longer covers `/api/*`. The replacement is
  `servant-client-ghcjs` (or `servant-reflex`) which derives one
  `XhrRequest`-shaped function per endpoint from `RoutesApi`. The
  type-safety property strengthens (params and bodies are typed, not
  just the path), and `routes.md` § *Frontend API calls* needs to be
  rewritten against the new helper. `BackendRoute_Vapid` and frontend
  pages stay on the obelisk-route encoder.
- **Method, body, status, and Content-Type leave the handlers** and
  live in the API type. Several `Backend.Auth` helpers
  (`parseJsonBody`, `writeJson`, `errorStatus`, `unauthorized`) become
  dead code and are removed in step 5.
- **Errors split into two channels.** Application-level outcomes (e.g.
  `InvalidCredentials`, `UsernameTaken`) keep riding inside the JSON
  result types as today. Transport errors (401, 429, 500) are raised
  with `throwError :: ServerError -> Handler a` instead of the current
  `errorStatus + finishWith`. The split was already the convention per
  [`authentication.md`](authentication.md); servant just enforces it
  syntactically.
- **Authentication is enforced by the type, not by a handler-level
  call.** Forgetting `AuthRequired "session"` is now a deliberate
  type-level choice rather than a forgotten `requireUser env` line.
- **Rate-limit keying becomes per-IP-per-route.** Today `Login` keys
  on `(ip, lowercased-username)`; the combinator only sees the IP and
  the bucket symbol because it runs before `ReqBody` parses, so the
  new key is `(ip, "login")`. The user-visible behaviour is slightly
  stricter (a brute-force attempt against user A from one IP also
  delays attempts against user B from the same IP) and acceptable for
  this app's threat model. If finer keying is needed later, the
  handler can do an extra bucket check post-body-parse.
- **Versioning the API gets cheaper.** Splitting `RoutesApi` into
  `RoutesApiV1 :<|> RoutesApiV2` is a one-line change to the type and
  costs nothing at the wire level — useful when we later want to
  evolve push/notification payloads without breaking pinned PWAs.
- **`servant-snap` is a smaller ecosystem than `servant-server` over
  warp.** It is maintained but lags features (e.g. streaming, modern
  combinator backports). If we hit a missing combinator, the workaround
  is usually a custom `HasServer` instance — known cost, but worth
  flagging.
- **Bootstrap cost.** Three new modules (`Common.Api`,
  `Backend.App`, `Backend.Auth.Combinator`) and a non-trivial cabal
  diff. After step 4 lands, every future endpoint is *cheaper* to add
  than today (one type alias + one `App` function), so the cost is
  paid back fast.

## Verification

- `nix-build -A ghc.backend --no-out-link` and
  `nix-build -A ghcjs.frontend --no-out-link` clean after each step.
- `ob run`, browser smoke covering the auth flows verified by
  [`authentication.md`](authentication.md)'s verification block
  (login, logout, invalid creds, rate-limit 429, register, register
  collision, me while signed in, me while signed out). HTTP-level
  behaviour must be byte-identical to today's; only the internal
  wiring is changing.

## Out of scope

- Migrating handlers from raw `postgresql-simple` to beam — tracked
  separately under "Remove plain SQL" in [`current-state.md`](current-state.md).
- Restructuring routes, response shapes, or any client-visible
  behaviour. The URL paths, HTTP methods, status codes, and JSON
  bodies must all match today's behaviour byte-for-byte.
