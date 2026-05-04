{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Backend.Api
  ( serveApi
  , buildContext
  ) where

import Backend.App (App, runApp)
import Backend.Auth.Combinator (UserId, sessionAuthHandler)
import qualified Backend.Auth.Login as Login
import qualified Backend.Auth.Logout as Logout
import qualified Backend.Auth.Me as Me
import qualified Backend.Auth.Register as Register
import Backend.Auth.RateLimit (RateLimiter)
import Backend.Env (Env, envRateLimiter)
import Common.Api (RoutesApi)
import Relude
import Servant.API ((:<|>) ((:<|>)))
import Servant.Server
  ( Context (..)
  , HasServer (hoistServerWithContext)
  , ServantErr
  , ServerT
  , serveSnapWithContext
  )
import Snap.Core (Snap)

-- | Servant @Context@ holding (a) the session-cookie auth handler that
-- @AuthRequired "session"@ dispatches to, and (b) the rate limiter the
-- @RateLimit "<bucket>"@ combinator queries.
type AppContext = '[Snap (Either ServantErr UserId), RateLimiter]

buildContext :: Env -> Context AppContext
buildContext env = sessionAuthHandler env :. envRateLimiter env :. EmptyContext

-- | Product of every per-route handler, in the same order as the
-- @:<|>@s in 'Common.Api.RoutesAuth'.
handlers :: ServerT RoutesApi AppContext App
handlers =
       Register.handler
  :<|> Login.handler
  :<|> Logout.handler
  :<|> Me.handler

-- | Hoist 'handlers' from 'App' down to 'Snap' so 'serveSnapWithContext'
-- can dispatch to them with a fresh request context.
serveApi :: Env -> Snap ()
serveApi env =
  serveSnapWithContext apiP ctx $
    hoistServerWithContext apiP ctxP (runApp env) handlers
  where
    apiP = Proxy :: Proxy RoutesApi
    ctxP = Proxy :: Proxy AppContext
    ctx  = buildContext env
