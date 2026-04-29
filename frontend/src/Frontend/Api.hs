module Frontend.Api
  ( apiUrl
  ) where

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

apiUrl :: R BackendRoute -> Text
apiUrl = renderBackendRoute validEncoder

validEncoder
  :: Encoder Identity Identity (R (FullRoute BackendRoute FrontendRoute)) PageName
validEncoder = case checkEncoder fullRouteEncoder of
  Right e  -> e
  Left err -> error $ "Frontend.Api: fullRouteEncoder failed check: " <> err
