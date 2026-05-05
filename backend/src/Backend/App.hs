module Backend.App
  ( App
  , runApp
  , throwApp
  , runBeamApp
  , AppContext
  ) where

import Backend.Auth.RateLimit (RateLimiter)
import Backend.Db (Pg, runBeam)
import Backend.Env (Env (envPool))
import Relude
import Servant.Server (ServantErr)
import qualified Servant.Server as Servant
import Snap.Core (Snap)

-- | Servant @Context@ holding (a) the session-cookie auth handler that
-- @AuthRequired "session"@ dispatches to, and (b) the rate limiter the
-- @RateLimit "<bucket>"@ combinator queries.
type AppContext = '[Snap (Either ServantErr Int64), RateLimiter]

-- | Per-request handler monad for servant routes.
--
-- @servant-snap@ runs handlers in any @MonadSnap m@; we add a Reader
-- carrying the application 'Env' so handlers can @asks envPool@ etc.
-- without threading an explicit argument.
type App = ReaderT Env Snap

-- | Lower an 'App' to plain 'Snap' for the top-level wiring boundary.
runApp :: Env -> App a -> Snap a
runApp = flip runReaderT

-- | Short-circuit the request with a servant error response.
-- @Servant.Server.throwError@ is a @MonadSnap m => ServantErr -> m a@
-- helper that calls @finishWith@ under the hood.
throwApp :: Servant.ServantErr -> App a
throwApp = lift . Servant.throwError

runBeamApp :: Pg a -> App a
runBeamApp action = do
  pool <- asks envPool
  liftIO $ runBeam pool action
