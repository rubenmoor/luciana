module Frontend.Api
  ( apiUrl
  , registerUrl
  , loginUrl
  , logoutUrl
  , meUrl
  ) where

import Common.Api (apiBase, authPath, loginPath, logoutPath, mePath, registerPath)
import Common.Route
  ( BackendRoute
  , FrontendRoute
  , fullRouteEncoder
  )
import Obelisk.Route
  ( Encoder
  , FullRoute
  , PageName
  , R
  , checkEncoder
  , renderBackendRoute
  )
import Relude

-- | Render a frontend-encoded backend route (currently used for the
-- VAPID public-key endpoint, which sits outside @/api/*@).
apiUrl :: R BackendRoute -> Text
apiUrl = renderBackendRoute validEncoder

validEncoder
  :: Encoder Identity Identity (R (FullRoute BackendRoute FrontendRoute)) PageName
validEncoder = case checkEncoder fullRouteEncoder of
  Right e  -> e
  Left err -> error $ "Frontend.Api: fullRouteEncoder failed check: " <> err

-- | URLs for the JSON API endpoints. Composed from named segments in
-- 'Common.Api' so the path strings stay in lock-step with the servant
-- @RoutesApi@ type the backend dispatches on.
registerUrl, loginUrl, logoutUrl, meUrl :: Text
registerUrl = apiBase <> authPath <> registerPath
loginUrl    = apiBase <> authPath <> loginPath
logoutUrl   = apiBase <> authPath <> logoutPath
meUrl       = apiBase <> authPath <> mePath
