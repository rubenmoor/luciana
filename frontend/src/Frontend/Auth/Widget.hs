-- | FlexibleContexts: Reflex constraints commonly need it.
-- ScopedTypeVariables: needed so `m` from the formEl signature is in scope
-- inside the body for the `Proxy :: Proxy (DomBuilderSpace m)` annotation.
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}

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
import Control.Lens ((%~), (.~))
import Data.Proxy (Proxy (Proxy))
import Frontend.Auth (getTimezone)
import Language.Javascript.JSaddle (MonadJSM)
import Reflex.Dom.Core
  ( DomBuilder
  , DomBuilderSpace
  , ElementConfig
  , Event
  , EventName (Submit)
  , EventResult
  , MonadHold
  , PerformEvent
  , Performable
  , PostBuild
  , addEventSpecFlags
  , current
  , def
  , domEvent
  , dynText
  , elAttr
  , element
  , elementConfig_eventSpec
  , elementConfig_initialAttributes
  , fmapMaybe
  , getPostBuild
  , holdDyn
  , inputElement
  , inputElementConfig_elementConfig
  , performEvent
  , preventDefault
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
  errorD <- holdDyn "" errorEv
  (submitEv, (emailIn, pwIn)) <- formEl $ do
    emailIn <- labelled "login-email" "Email" $ inputElement $ def
      & inputElementConfig_elementConfig . elementConfig_initialAttributes
          .~ ( "type"         =: "email"
            <> "autocomplete" =: "email"
            <> "id"           =: "login-email"
            <> "class"        =: "input input-bordered w-full"
             )
    pwIn <- labelled "login-password" "Password" $ inputElement $ def
      & inputElementConfig_elementConfig . elementConfig_initialAttributes
          .~ ( "type"         =: "password"
            <> "autocomplete" =: "current-password"
            <> "id"           =: "login-password"
            <> "class"        =: "input input-bordered w-full"
             )
    submitButtonClass "btn btn-primary w-full mt-2" "Sign in"
    elAttr "p" ("class" =: "text-error text-sm mt-2 min-h-[1.25rem]") $ dynText errorD
    pure (emailIn, pwIn)
  let reqB = mkLoginRequest
        <$> _inputElement_value emailIn
        <*> _inputElement_value pwIn
  pure $ fmapMaybe id (current reqB <@ submitEv)

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
  errorD <- holdDyn "" errorEv
  pb     <- getPostBuild
  tzEv   <- performEvent (getTimezone <$ pb)
  tzD    <- holdDyn "UTC" tzEv
  (submitEv, (emailIn, pwIn)) <- formEl $ do
    emailIn <- labelled "signup-email" "Email" $ inputElement $ def
      & inputElementConfig_elementConfig . elementConfig_initialAttributes
          .~ ( "type"         =: "email"
            <> "autocomplete" =: "email"
            <> "id"           =: "signup-email"
            <> "class"        =: "input input-bordered w-full"
             )
    pwIn <- labelled "signup-password" "Password" $ inputElement $ def
      & inputElementConfig_elementConfig . elementConfig_initialAttributes
          .~ ( "type"         =: "password"
            <> "autocomplete" =: "new-password"
            <> "id"           =: "signup-password"
            <> "class"        =: "input input-bordered w-full"
             )
    submitButtonClass "btn btn-primary w-full mt-2" "Create account"
    elAttr "p" ("class" =: "text-error text-sm mt-2 min-h-[1.25rem]") $ dynText errorD
    pure (emailIn, pwIn)
  let reqB = mkRegister
        <$> _inputElement_value emailIn
        <*> _inputElement_value pwIn
        <*> tzD
  pure $ fmapMaybe id (current reqB <@ submitEv)

mkRegister :: Text -> Text -> Text -> Maybe RegisterRequest
mkRegister e p tz =
  RegisterRequest
    <$> hush (mkEmail e)
    <*> hush (mkPassword p)
    <*> pure LocaleEn
    <*> pure tz

----------------------------------------------------------------------
-- helpers

-- | Wrap a labelled input. The id binds the <label>'s for= to the
--   input's id; callers are responsible for putting the matching
--   "id" =: fieldId on the input's initial attributes.
labelled
  :: DomBuilder t m
  => Text  -- ^ id of the form control (matches the input's id)
  -> Text  -- ^ visible label text
  -> m a
  -> m a
labelled fieldId lbl inner = elAttr "div" ("class" =: "form-control w-full mb-2") $ do
  elAttr "label" ("class" =: "label" <> "for" =: fieldId) $
    elAttr "span" ("class" =: "label-text") $ text lbl
  inner

-- | Wrap inner widgets in a <form>. The returned event fires on form
--   submission (Enter pressed in any field, or activation of the submit
--   button) with preventDefault, so the browser does not navigate.
formEl
  :: forall t m a
   . DomBuilder t m
  => m a
  -> m (Event t (), a)
formEl inner = do
  let cfg = (def :: ElementConfig EventResult t (DomBuilderSpace m))
        & elementConfig_eventSpec %~ addEventSpecFlags
            (Proxy :: Proxy (DomBuilderSpace m))
            Submit
            (const preventDefault)
  (formE, x) <- element "form" cfg inner
  pure (domEvent Submit formE, x)

-- | A submit-type button. Inside a <form>, this is the default button
--   that receives Enter-key submission and click submission alike.
submitButtonClass
  :: DomBuilder t m => Text -> Text -> m ()
submitButtonClass cls lbl =
  elAttr "button"
    ("type" =: "submit" <> "class" =: cls)
    (text lbl)

hush :: Either e a -> Maybe a
hush = either (const Nothing) Just
