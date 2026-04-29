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

import Common.Auth
  ( LoginRequest
  , LoginResult (InvalidCredentials, LoginOk)
  , RegisterRequest
  , RegisterResult (RegisterOk, UsernameTaken)
  , UserResponse
  )
import Common.Route
  ( ApiRoute (ApiRoute_Auth)
  , AuthRoute (AuthRoute_Login, AuthRoute_Logout, AuthRoute_Me, AuthRoute_Register)
  , BackendRoute (BackendRoute_Api)
  , FrontendRoute (FrontendRoute_Login)
  )
import Data.Default (def)
import Frontend.Api (apiUrl)
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
meRequest = XhrRequest "GET"
  (apiUrl (BackendRoute_Api :/ ApiRoute_Auth :/ AuthRoute_Me :/ ()))
  def

----------------------------------------------------------------------
-- performLogin / performRegister / performLogout
--
-- Login/Register decode the typed JSON result from the response body
-- and translate it to @Either Text UserResponse@. Application-level
-- outcomes (invalid credentials, username taken) become @Left@ with a
-- localised message; @429@ becomes a rate-limit message; other HTTP
-- non-2xx and decode failures fall through to a generic "unexpected"
-- branch.

performLogin
  :: ( PerformEvent t m
     , TriggerEvent t m
     , MonadJSM (Performable m)
     )
  => Event t LoginRequest
  -> m (Event t (Either Text UserResponse))
performLogin reqEv = do
  let url = apiUrl (BackendRoute_Api :/ ApiRoute_Auth :/ AuthRoute_Login :/ ())
  resp <- performRequestAsync (postJson url <$> reqEv)
  pure (decodeLogin <$> resp)

decodeLogin :: XhrResponse -> Either Text UserResponse
decodeLogin r
  | _xhrResponse_status r == 429 = Left "Too many attempts — try again later"
  | not (statusOk r) = Left (unexpected r)
  | otherwise = case decodeXhrResponse r of
      Just (LoginOk u)        -> Right u
      Just InvalidCredentials -> Left "Invalid username or password"
      Nothing                 -> Left (unexpected r)

performRegister
  :: ( PerformEvent t m
     , TriggerEvent t m
     , MonadJSM (Performable m)
     )
  => Event t RegisterRequest
  -> m (Event t (Either Text UserResponse))
performRegister reqEv = do
  let url = apiUrl (BackendRoute_Api :/ ApiRoute_Auth :/ AuthRoute_Register :/ ())
  resp <- performRequestAsync (postJson url <$> reqEv)
  pure (decodeRegister <$> resp)

decodeRegister :: XhrResponse -> Either Text UserResponse
decodeRegister r
  | _xhrResponse_status r == 429 = Left "Too many attempts — try again later"
  | not (statusOk r) = Left (unexpected r)
  | otherwise = case decodeXhrResponse r of
      Just (RegisterOk u) -> Right u
      Just UsernameTaken  -> Left "Username already taken"
      Nothing             -> Left (unexpected r)

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
logoutRequest = XhrRequest "POST"
  (apiUrl (BackendRoute_Api :/ ApiRoute_Auth :/ AuthRoute_Logout :/ ()))
  def

statusOk :: XhrResponse -> Bool
statusOk r = let s = _xhrResponse_status r in s >= 200 && s < 300

unexpected :: XhrResponse -> Text
unexpected r = "Unexpected error (" <> show (_xhrResponse_status r) <> ")"

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
