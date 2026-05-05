{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Frontend.Api
  ( apiUrl
  , apiClients
  ) where

import Common.Api (AuthRequired, RateLimit, RoutesApi)
import Common.Route (BackendRoute, FrontendRoute, fullRouteEncoder)
import GHC.TypeLits (Symbol)
import Obelisk.Route (Encoder, FullRoute, PageName, R, checkEncoder, renderBackendRoute)
import Reflex.Dom.Core (Dynamic)
import Relude
import Servant.API ((:>))
import Servant.Reflex (BaseUrl, Client, HasClient (..), client)

apiUrl :: R BackendRoute -> Text
apiUrl = renderBackendRoute validEncoder

validEncoder :: Encoder Identity Identity (R (FullRoute BackendRoute FrontendRoute)) PageName
validEncoder = case checkEncoder fullRouteEncoder of
  Right e  -> e
  Left err -> error $ "Frontend.Api: fullRouteEncoder failed check: " <> err

-- | Derived servant-reflex clients for the entire JSON API.
-- In servant-reflex-0.4.0, 'client' takes 4 arguments:
-- 1. api proxy, 2. m proxy, 3. tag proxy, 4. base url dynamic.
-- The timeline 't' is inferred from the base url.
apiClients
  :: forall t m. (HasClient t m RoutesApi ())
  => Dynamic t BaseUrl
  -> Client t m RoutesApi ()
apiClients base = client (Proxy @RoutesApi) (Proxy @m) (Proxy @()) base

-- | Client-side instances for custom combinators. Both are transparent
-- to the client: 'AuthRequired' relies on the browser-managed session
-- cookie, and 'RateLimit' is tracked server-side by IP.
instance (HasClient t m sub tag) => HasClient t m (AuthRequired (reqTag :: Symbol) :> sub) tag where
  type Client t m (AuthRequired reqTag :> sub) tag = Client t m sub tag
  clientWithRoute _ m p = clientWithRoute (Proxy @sub) m p
  clientWithRouteAndResultHandler _ m p = clientWithRouteAndResultHandler (Proxy @sub) m p

instance (HasClient t m sub tag) => HasClient t m (RateLimit (bucket :: Symbol) :> sub) tag where
  type Client t m (RateLimit bucket :> sub) tag = Client t m sub tag
  clientWithRoute _ m p = clientWithRoute (Proxy @sub) m p
  clientWithRouteAndResultHandler _ m p = clientWithRouteAndResultHandler (Proxy @sub) m p
