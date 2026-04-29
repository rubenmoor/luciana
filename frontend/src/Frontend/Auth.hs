-- | FlexibleContexts: Reflex constraints typically require it.
-- ScopedTypeVariables: occasional explicit forall in helpers.
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Frontend.Auth
  ( AuthState (..)
  , currentAuth
  , performLogin
  , performRegister
  , performLogout
  , requireSignedIn
  , getTimezone
  ) where

import Common.Auth (LoginRequest, RegisterRequest, UserResponse)
import Common.Route (FrontendRoute (FrontendRoute_Login))
import Data.Default (def)
import Language.Javascript.JSaddle
  ( MonadJSM
  , eval
  , fromJSValUnchecked
  , liftJSM
  )
import Obelisk.Route (R, pattern (:/))
import Obelisk.Route.Frontend (SetRoute, setRoute)
import Reflex.Dom.Core
  ( DomBuilder
  , Dynamic
  , Event
  , MonadHold
  , PerformEvent
  , Performable
  , PostBuild
  , TriggerEvent
  , current
  , dyn_
  , ffor
  , fmapMaybe
  , getPostBuild
  , holdDyn
  , leftmost
  , updated
  , (<@)
  )
import Reflex.Dom.Xhr
  ( XhrRequest (XhrRequest)
  , XhrResponse
  , decodeXhrResponse
  , performRequestAsync
  , postJson
  , _xhrResponse_status
  )
import Relude

data AuthState
  = AuthLoading
  | AuthAnon
  | AuthSignedIn UserResponse
  deriving stock (Eq, Show)

----------------------------------------------------------------------
-- currentAuth: GET /api/auth/me on PostBuild and on every refresh.

currentAuth
  :: ( PostBuild t m
     , MonadHold t m
     , PerformEvent t m
     , TriggerEvent t m
     , MonadJSM (Performable m)
     )
  => Event t ()
  -> m (Dynamic t AuthState)
currentAuth refreshEv = do
  pb <- getPostBuild
  let trigger = leftmost [pb, refreshEv]
      reqEv   = trigger $> meRequest
  respEv <- performRequestAsync reqEv
  let stateEv = ffor respEv $ \r ->
        if _xhrResponse_status r == 200
          then maybe AuthAnon AuthSignedIn (decodeXhrResponse r)
          else AuthAnon
  holdDyn AuthLoading stateEv

meRequest :: XhrRequest ()
meRequest = XhrRequest "GET" "/api/auth/me" def

----------------------------------------------------------------------
-- performLogin / performRegister / performLogout
--
-- Each returns @Either Text ()@ where @Left@ carries a human-readable
-- error string from the response status text and @Right ()@ indicates
-- HTTP success (2xx).

performLogin
  :: ( PerformEvent t m
     , TriggerEvent t m
     , MonadJSM (Performable m)
     )
  => Event t LoginRequest
  -> m (Event t (Either Text ()))
performLogin reqEv = do
  resp <- performRequestAsync (postJson "/api/auth/login" <$> reqEv)
  pure (statusToEither <$> resp)

performRegister
  :: ( PerformEvent t m
     , TriggerEvent t m
     , MonadJSM (Performable m)
     )
  => Event t RegisterRequest
  -> m (Event t (Either Text ()))
performRegister reqEv = do
  resp <- performRequestAsync (postJson "/api/auth/register" <$> reqEv)
  pure (statusToEither <$> resp)

performLogout
  :: ( PerformEvent t m
     , TriggerEvent t m
     , MonadJSM (Performable m)
     )
  => Event t ()
  -> m (Event t ())
performLogout ev = do
  resp <- performRequestAsync (ev $> logoutRequest)
  pure (() <$ resp)

logoutRequest :: XhrRequest ()
logoutRequest = XhrRequest "POST" "/api/auth/logout" def

statusToEither :: XhrResponse -> Either Text ()
statusToEither r =
  let s = _xhrResponse_status r
  in if s >= 200 && s < 300
       then Right ()
       else Left (statusErr s)

statusErr :: Word -> Text
statusErr 401 = "Invalid username or password"
statusErr 409 = "Username already taken"
statusErr 429 = "Too many attempts — try again later"
statusErr 400 = "Bad request"
statusErr s   = "Unexpected error (" <> show s <> ")"

----------------------------------------------------------------------
-- requireSignedIn: render @inner@ when signed in, redirect to /login
-- otherwise. AuthLoading renders nothing (avoids flashing the redirect).

requireSignedIn
  :: ( DomBuilder t m
     , PostBuild t m
     , SetRoute t (R FrontendRoute) m
     )
  => Dynamic t AuthState
  -> m ()
  -> m ()
requireSignedIn stD inner = do
  pb <- getPostBuild
  let initialEv = current stD <@ pb
      changesEv = updated stD
      anonEv    = fmapMaybe isAnon (leftmost [initialEv, changesEv])
  setRoute ((FrontendRoute_Login :/ ()) <$ anonEv)
  dyn_ $ ffor stD $ \case
    AuthLoading    -> pass
    AuthAnon       -> pass
    AuthSignedIn _ -> inner
  where
    isAnon AuthAnon = Just ()
    isAnon _        = Nothing

----------------------------------------------------------------------
-- getTimezone: read IANA TZ name from the browser via JS.

getTimezone :: MonadJSM m => m Text
getTimezone = liftJSM $ do
  v <- eval ("Intl.DateTimeFormat().resolvedOptions().timeZone" :: Text)
  fromJSValUnchecked v
