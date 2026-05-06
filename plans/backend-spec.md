# backend-spec.md

Status: spec

Architecture and technical stack for the backend JSON API and application state management.

## Technical Stack

- **Framework**: [Servant](https://haskell-servant.github.io/) for type-safe API definitions and routing.
- **Server Integration**: `servant-snap` to integrate Servant into the Obelisk/Snap pipeline.
- **Application Monad**: `type App = ReaderT Env Snap`. `servant-snap`
  hoists this directly into Snap; Servant's `Handler` is not used as the
  application monad.
- **Database**: [Beam](https://haskell-beam.github.io/beam/) for type-safe, composable SQL queries and migrations.

## API Definition (`Common.Api`)

The API is defined as a Servant type to handle method dispatch, JSON parsing, and response formatting.

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
```

## Application State (`Backend.Env`, `Backend.App`)

Shared state is threaded via a `ReaderT Env` monad.

```haskell
data Env = Env
  { envPool         :: DbPool
  , envRateLimiter  :: RateLimiter
  , envCookieSecure :: Bool
  }

type App = ReaderT Env Snap
```

## Custom Combinators

- **`AuthRequired "session"`**: Servant `AuthProtect` for session cookie resolution. Injects `UserId`.
- **`RateLimit "<bucket>"`**: Per-IP, per-bucket rate limiting. Injects `RateBucket` for manual clearing (e.g., on successful login).

## Module Layout

- `Backend.Env`: Environment definition and accessors.
- `Backend.App`: `App` monad and hoisting logic.
- `Backend.Api`: Servant server implementation and routing.
- `Backend.Auth.Combinator`: Session authentication logic.
- `Backend.RateLimit.Combinator`: Rate limiting logic.
- `Common.Api`: Shared Servant API types.
