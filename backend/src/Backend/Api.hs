{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Backend.Api
  ( serveApi
  , buildContext
  ) where

import Backend.App (App, AppContext, runApp)
import Backend.Auth.Combinator (sessionAuthHandler)
import qualified Backend.Auth.Login as Login
import qualified Backend.Auth.Logout as Logout
import qualified Backend.Auth.Me as Me
import qualified Backend.Auth.Register as Register
import Backend.Auth.RateLimit ()
import Backend.Env (Env, envRateLimiter)
import qualified Backend.Notifications as Notifications
import qualified Backend.Period as Period
import qualified Backend.Push as Push
import Common.Api (RoutesApi, RoutesAuth)
import Relude
import Servant.API ((:<|>) ((:<|>)))
import Servant.Server
  ( Context (..)
  , HasServer (hoistServerWithContext)
  , ServerT
  , serveSnapWithContext
  )
import Snap.Core (Snap)

buildContext :: Env -> Context AppContext
buildContext env = sessionAuthHandler env :. envRateLimiter env :. EmptyContext

-- | Product of every per-route handler, in the same order as the
-- @:<|>@s in 'Common.Api.RoutesAuth'.
handlers :: ServerT RoutesApi AppContext App
handlers =
       authHandlers
  :<|> Period.handlers
  :<|> Notifications.handlers
  :<|> Push.handlers

authHandlers :: ServerT RoutesAuth AppContext App
authHandlers =
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
