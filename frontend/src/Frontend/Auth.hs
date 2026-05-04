-- | FlexibleContexts: Reflex constraints typically require it.
-- ScopedTypeVariables: occasional explicit forall in helpers.
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

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
import Common.Route (FrontendRoute (FrontendRoute_Login))
import qualified Data.Aeson as Aeson
import qualified Data.Text.Encoding as TE
import Frontend.Api (apiClients)
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
import Reflex.Dom.Xhr
  ( XhrResponse
  , _xhrResponse_responseText
  , _xhrResponse_status
  )
import Relude
import Servant.API ((:<|>) ((:<|>)), Header, Headers (..), NoContent)
import Servant.Reflex (BaseUrl (BasePath), ReqResult (..))

data AuthState
  = AuthLoading
  | AuthAnon
  | AuthSignedIn UserResponse
  deriving stock (Eq, Show)

-- | Auth clients product.
-- In servant-reflex-0.4.0, the tag is set to () in Frontend.Api.
-- ReqBody routes take Dynamic (Either Text body) and Event trigger.
authClients
  :: forall t m. (MonadWidget t m)
  => ( (Dynamic t (Either Text RegisterRequest) -> Event t () -> m (Event t (ReqResult () (Headers '[Header "Set-Cookie" Text] RegisterResult))))
     :<|> (Dynamic t (Either Text LoginRequest) -> Event t () -> m (Event t (ReqResult () (Headers '[Header "Set-Cookie" Text] LoginResult))))
     :<|> (Event t () -> m (Event t (ReqResult () (Headers '[Header "Set-Cookie" Text] NoContent))))
     :<|> (Event t () -> m (Event t (ReqResult () UserResponse)))
     )
authClients = let (c :<|> _) = apiClients (pure $ BasePath "/") in c

----------------------------------------------------------------------
-- currentAuth: GET /api/auth/me on PostBuild and on every refresh.

currentAuth
  :: ( MonadWidget t m )
  => Event t ()
  -> m (Dynamic t AuthState)
currentAuth refreshEv = do
  pb <- getPostBuild
  let trigger = leftmost [pb, refreshEv]
      (_ :<|> _ :<|> _ :<|> me) = authClients
  respEv <- me trigger
  let stateEv = ffor respEv $ \case
        ResponseSuccess _ u _ -> AuthSignedIn u
        _                     -> AuthAnon
  holdDyn AuthLoading stateEv

----------------------------------------------------------------------
-- performLogin / performRegister / performLogout

data LoginError
  = LoginInvalid
  | LoginUnexpected ToastMsg (Maybe Aeson.Value)
  deriving stock (Eq, Show)

data RegisterError
  = RegisterTaken
  | RegisterUnexpected ToastMsg (Maybe Aeson.Value)
  deriving stock (Eq, Show)

performLogin
  :: ( MonadWidget t m )
  => Event t LoginRequest
  -> m (Event t (Either LoginError UserResponse))
performLogin reqEv = do
  let (_ :<|> login :<|> _ :<|> _) = authClients
  bodyD <- holdDyn (Left "no-login-yet") (Right <$> reqEv)
  respEv <- login bodyD (() <$ reqEv)
  pure $ ffor respEv $ \case
    ResponseSuccess _ (Headers result _) _ -> case result of
      LoginOk u          -> Right u
      InvalidCredentials -> Left LoginInvalid
    ResponseFailure _ _ r ->
      Left (LoginUnexpected (statusToMsg r) (diagnostic "/api/auth/login" "POST" r))
    RequestFailure _ _ ->
      Left (LoginUnexpected MsgServerError Nothing)

performRegister
  :: ( MonadWidget t m )
  => Event t RegisterRequest
  -> m (Event t (Either RegisterError UserResponse))
performRegister reqEv = do
  let (register :<|> _ :<|> _ :<|> _) = authClients
  bodyD <- holdDyn (Left "no-register-yet") (Right <$> reqEv)
  respEv <- register bodyD (() <$ reqEv)
  pure $ ffor respEv $ \case
    ResponseSuccess _ (Headers result _) _ -> case result of
      RegisterOk u  -> Right u
      UsernameTaken -> Left RegisterTaken
    ResponseFailure _ _ r ->
      Left (RegisterUnexpected (statusToMsg r) (diagnostic "/api/auth/register" "POST" r))
    RequestFailure _ _ ->
      Left (RegisterUnexpected MsgServerError Nothing)

performLogout
  :: ( MonadWidget t m )
  => Event t ()
  -> m (Event t ())
performLogout ev = do
  let (_ :<|> _ :<|> logout :<|> _) = authClients
  resp <- logout ev
  pure (() <$ resp)

statusToMsg :: XhrResponse -> ToastMsg
statusToMsg r
  | _xhrResponse_status r == 429 = MsgRateLimited
  | _xhrResponse_status r == 400 = MsgBadRequest
  | otherwise = MsgServerError

-- | Build a diagnostic JSON object from an HTTP response.
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
