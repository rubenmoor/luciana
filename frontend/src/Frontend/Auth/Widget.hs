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
  , EventName (Click)
  , MonadHold
  , PerformEvent
  , Performable
  , PostBuild
  , current
  , def
  , domEvent
  , dynText
  , elAttr
  , elAttr'
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
  elAttr "h1" ("class" =: "card-title text-2xl mb-2") $ text "Sign in"
  emailIn <- labelled "Email" $ inputElement $ def
    & inputElementConfig_elementConfig . elementConfig_initialAttributes
        .~ ("type" =: "email" <> "autocomplete" =: "email"
            <> "class" =: "input input-bordered w-full")
  pwIn    <- labelled "Password" $ inputElement $ def
    & inputElementConfig_elementConfig . elementConfig_initialAttributes
        .~ ("type" =: "password" <> "autocomplete" =: "current-password"
            <> "class" =: "input input-bordered w-full")
  submit  <- buttonClass "btn btn-primary w-full mt-2" "Sign in"
  errorD  <- holdDyn "" errorEv
  elAttr "p" ("class" =: "text-error text-sm mt-2 min-h-[1.25rem]") $ dynText errorD
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
  elAttr "h1" ("class" =: "card-title text-2xl mb-2") $ text "Create account"
  emailIn <- labelled "Email" $ inputElement $ def
    & inputElementConfig_elementConfig . elementConfig_initialAttributes
        .~ ("type" =: "email" <> "autocomplete" =: "email"
            <> "class" =: "input input-bordered w-full")
  pwIn    <- labelled "Password" $ inputElement $ def
    & inputElementConfig_elementConfig . elementConfig_initialAttributes
        .~ ("type" =: "password" <> "autocomplete" =: "new-password"
            <> "class" =: "input input-bordered w-full")
  submit  <- buttonClass "btn btn-primary w-full mt-2" "Create account"
  errorD  <- holdDyn "" errorEv
  elAttr "p" ("class" =: "text-error text-sm mt-2 min-h-[1.25rem]") $ dynText errorD
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
labelled lbl inner = elAttr "div" ("class" =: "form-control w-full mb-2") $ do
  elAttr "label" ("class" =: "label") $
    elAttr "span" ("class" =: "label-text") $ text lbl
  inner

-- | A button element that accepts a CSS class string.
buttonClass
  :: DomBuilder t m => Text -> Text -> m (Event t ())
buttonClass cls label = do
  (e, _) <- elAttr' "button"
    ("type" =: "button" <> "class" =: cls)
    (text label)
  pure $ domEvent Click e

hush :: Either e a -> Maybe a
hush = either (const Nothing) Just
