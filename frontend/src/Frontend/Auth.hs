-- | FlexibleContexts: Reflex constraints typically require it.
-- ScopedTypeVariables: occasional explicit forall in helpers.
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Frontend.Auth
  ( AuthState (..)
  , LoginError (..)
  , RegisterError (..)
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
import qualified Data.Aeson as Aeson
import Data.Default (def)
import qualified Data.Text.Encoding as TE
import Frontend.Api (apiUrl)
import Frontend.Toast (ToastMsg (..))
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
  , _xhrResponse_responseText
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
-- Login/Register decode the typed JSON result from the response body.
-- Application-level outcomes (invalid credentials, username taken)
-- become 'LoginInvalid' / 'RegisterTaken' (handled inline by the page
-- as red text under the form). HTTP-layer failures (4xx, 5xx, decode
-- failure) become the @*Unexpected@ branch carrying a 'ToastMsg' and
-- optional diagnostic JSON for the renderer to display behind a
-- toggle.

data LoginError
  = LoginInvalid
  | LoginUnexpected ToastMsg (Maybe Aeson.Value)
  deriving stock (Eq, Show)

data RegisterError
  = RegisterTaken
  | RegisterUnexpected ToastMsg (Maybe Aeson.Value)
  deriving stock (Eq, Show)

performLogin
  :: ( PerformEvent t m
     , TriggerEvent t m
     , MonadJSM (Performable m)
     )
  => Event t LoginRequest
  -> m (Event t (Either LoginError UserResponse))
performLogin reqEv = do
  let url = apiUrl (BackendRoute_Api :/ ApiRoute_Auth :/ AuthRoute_Login :/ ())
  resp <- performRequestAsync (postJson url <$> reqEv)
  pure (decodeLogin url <$> resp)

decodeLogin :: Text -> XhrResponse -> Either LoginError UserResponse
decodeLogin url r
  | _xhrResponse_status r == 429 =
      Left (LoginUnexpected MsgRateLimited (diagnostic url "POST" r))
  | _xhrResponse_status r == 400 =
      Left (LoginUnexpected MsgBadRequest (diagnostic url "POST" r))
  | _xhrResponse_status r >= 500 =
      Left (LoginUnexpected MsgServerError (diagnostic url "POST" r))
  | not (statusOk r) =
      Left (LoginUnexpected MsgServerError (diagnostic url "POST" r))
  | otherwise = case decodeXhrResponse r of
      Just (LoginOk u)        -> Right u
      Just InvalidCredentials -> Left LoginInvalid
      Nothing                 ->
        Left (LoginUnexpected MsgServerError (diagnostic url "POST" r))

performRegister
  :: ( PerformEvent t m
     , TriggerEvent t m
     , MonadJSM (Performable m)
     )
  => Event t RegisterRequest
  -> m (Event t (Either RegisterError UserResponse))
performRegister reqEv = do
  let url = apiUrl (BackendRoute_Api :/ ApiRoute_Auth :/ AuthRoute_Register :/ ())
  resp <- performRequestAsync (postJson url <$> reqEv)
  pure (decodeRegister url <$> resp)

decodeRegister :: Text -> XhrResponse -> Either RegisterError UserResponse
decodeRegister url r
  | _xhrResponse_status r == 429 =
      Left (RegisterUnexpected MsgRateLimited (diagnostic url "POST" r))
  | _xhrResponse_status r == 400 =
      Left (RegisterUnexpected MsgBadRequest (diagnostic url "POST" r))
  | _xhrResponse_status r >= 500 =
      Left (RegisterUnexpected MsgServerError (diagnostic url "POST" r))
  | not (statusOk r) =
      Left (RegisterUnexpected MsgServerError (diagnostic url "POST" r))
  | otherwise = case decodeXhrResponse r of
      Just (RegisterOk u) -> Right u
      Just UsernameTaken  -> Left RegisterTaken
      Nothing             ->
        Left (RegisterUnexpected MsgServerError (diagnostic url "POST" r))

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

-- | Build a diagnostic JSON object from an HTTP response. The body
-- field embeds parsed JSON when the response text decodes as JSON,
-- and the raw text otherwise.
diagnostic :: Text -> Text -> XhrResponse -> Maybe Aeson.Value
diagnostic url method r = Just $ Aeson.object
  [ ("status", Aeson.toJSON (_xhrResponse_status r))
  , ("url",    Aeson.toJSON url)
  , ("method", Aeson.toJSON method)
  , ("body",   bodyJson)
  ]
  where
    bodyJson = case _xhrResponse_responseText r of
      Nothing -> Aeson.Null
      Just t  -> case Aeson.decodeStrict (TE.encodeUtf8 t) of
        Just v  -> v
        Nothing -> Aeson.toJSON t

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
