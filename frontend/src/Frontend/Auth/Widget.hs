-- | FlexibleContexts: Reflex constraints commonly need it.
{-# LANGUAGE FlexibleContexts #-}

module Frontend.Auth.Widget
  ( loginWidget
  , signupWidget
  ) where

import Common.Auth
  ( LoginRequest (LoginRequest)
  , RegisterRequest (RegisterRequest)
  , mkEmail
  , mkPassword
  )
import Common.I18n (Locale (LocaleEn))
import Control.Lens ((.~))
import Frontend.Auth (getTimezone)
import Language.Javascript.JSaddle (MonadJSM)
import Reflex.Dom.Core
  ( DomBuilder
  , Event
  , MonadHold
  , PerformEvent
  , Performable
  , PostBuild
  , button
  , current
  , def
  , dynText
  , el
  , elementConfig_initialAttributes
  , fmapMaybe
  , getPostBuild
  , holdDyn
  , inputElement
  , inputElementConfig_elementConfig
  , performEvent
  , text
  , (<@)
  , (=:)
  , _inputElement_value
  )
import Relude

----------------------------------------------------------------------
-- loginWidget

loginWidget
  :: ( DomBuilder t m
     , MonadHold t m
     , PostBuild t m
     )
  => Event t Text
  -> m (Event t LoginRequest)
loginWidget errorEv = do
  el "h1" $ text "Sign in"
  emailIn <- labelled "Email" $ inputElement $ def
    & inputElementConfig_elementConfig . elementConfig_initialAttributes
        .~ ("type" =: "email" <> "autocomplete" =: "email")
  pwIn    <- labelled "Password" $ inputElement $ def
    & inputElementConfig_elementConfig . elementConfig_initialAttributes
        .~ ("type" =: "password" <> "autocomplete" =: "current-password")
  submit  <- button "Sign in"
  errorD  <- holdDyn "" errorEv
  el "p" $ dynText errorD
  let reqB = mkLoginRequest
        <$> _inputElement_value emailIn
        <*> _inputElement_value pwIn
  pure $ fmapMaybe id (current reqB <@ submit)

mkLoginRequest :: Text -> Text -> Maybe LoginRequest
mkLoginRequest e p = LoginRequest <$> hush (mkEmail e) <*> hush (mkPassword p)

----------------------------------------------------------------------
-- signupWidget
--
-- Reads timezone from the browser at PostBuild and uses the latest
-- value when the user submits. Locale defaults to English (no picker
-- yet).

signupWidget
  :: ( DomBuilder t m
     , MonadHold t m
     , PostBuild t m
     , PerformEvent t m
     , MonadJSM (Performable m)
     )
  => Event t Text
  -> m (Event t RegisterRequest)
signupWidget errorEv = do
  el "h1" $ text "Create account"
  emailIn <- labelled "Email" $ inputElement $ def
    & inputElementConfig_elementConfig . elementConfig_initialAttributes
        .~ ("type" =: "email" <> "autocomplete" =: "email")
  pwIn    <- labelled "Password" $ inputElement $ def
    & inputElementConfig_elementConfig . elementConfig_initialAttributes
        .~ ("type" =: "password" <> "autocomplete" =: "new-password")
  submit  <- button "Create account"
  errorD  <- holdDyn "" errorEv
  el "p" $ dynText errorD
  pb   <- getPostBuild
  tzEv <- performEvent (getTimezone <$ pb)
  tzD  <- holdDyn "UTC" tzEv
  let reqB = mkRegister
        <$> _inputElement_value emailIn
        <*> _inputElement_value pwIn
        <*> tzD
  pure $ fmapMaybe id (current reqB <@ submit)

mkRegister :: Text -> Text -> Text -> Maybe RegisterRequest
mkRegister e p tz =
  RegisterRequest
    <$> hush (mkEmail e)
    <*> hush (mkPassword p)
    <*> pure LocaleEn
    <*> pure tz

----------------------------------------------------------------------
-- helpers

labelled
  :: DomBuilder t m
  => Text
  -> m a
  -> m a
labelled lbl inner = el "label" $ do
  el "span" $ text lbl
  inner

hush :: Either e a -> Maybe a
hush = either (const Nothing) Just
