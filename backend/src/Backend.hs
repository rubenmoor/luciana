module Backend where

import Backend.Db (loadDbUrl, withDbPool)
import Backend.Schema.Migration (readMigrationMode, runMigrations)
import Common.Route (BackendRoute, FrontendRoute, fullRouteEncoder)
import Obelisk.Backend (Backend (Backend, _backend_run, _backend_routeEncoder))
import Relude

backend :: Backend BackendRoute FrontendRoute
backend = Backend
  { _backend_run = \serve -> do
      url  <- loadDbUrl
      mode <- readMigrationMode
      withDbPool url $ \pool -> do
        runMigrations pool mode
        serve $ const (pure ())
  , _backend_routeEncoder = fullRouteEncoder
  }
