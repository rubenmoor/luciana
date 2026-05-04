{-# LANGUAGE PatternSynonyms #-}

module Backend where

import Backend.Api (serveApi)
import Backend.Auth (forkSessionCleanup)
import Backend.Db (loadDbUrl, withDbPool)
import Backend.Env (mkEnv)
import Backend.Schema.Migration (readMigrationMode, runMigrations)
import Common.Route (BackendRoute (..), FrontendRoute, fullRouteEncoder)
import Obelisk.Backend (Backend (Backend, _backend_run, _backend_routeEncoder))
import Obelisk.Route (pattern (:/))
import Relude

backend :: Backend BackendRoute FrontendRoute
backend = Backend
  { _backend_run = \serve -> do
      url  <- loadDbUrl
      mode <- readMigrationMode
      withDbPool url $ \pool -> do
        runMigrations pool mode
        env <- mkEnv pool
        _   <- forkSessionCleanup env
        serve $ \case
          BackendRoute_Missing :/ _ -> pass
          BackendRoute_Vapid   :/ _ -> pass  -- TODO: serve VAPID public key
          BackendRoute_Api     :/ _ -> serveApi env
  , _backend_routeEncoder = fullRouteEncoder
  }
