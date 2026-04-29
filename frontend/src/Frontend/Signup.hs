-- | FlexibleContexts: Reflex constraints commonly need it.
-- RecursiveDo: page wires the error event from performRegister back into
-- the widget that produced the submit event.
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RecursiveDo #-}

module Frontend.Signup
  ( page
  ) where

import Common.Auth (RegisterRequest (RegisterRequest), mkPassword, mkUsername)
import Common.I18n (Locale (LocaleEn))
import Common.Route (FrontendRoute (FrontendRoute_Home, FrontendRoute_Login))
import Control.Lens ((.~))
import Control.Monad.Fix (MonadFix)
import Frontend.Auth (getTimezone, performRegister)
import Frontend.Widget.Form (formEl, labelled, submitButtonClass)
import Frontend.Widget.Icon (iconUserPlus)
import Language.Javascript.JSaddle (MonadJSM)
import Obelisk.Route (R, pattern (:/))
import Obelisk.Route.Frontend (RouteToUrl, SetRoute, routeLink, setRoute)
import Reflex.Dom.Core
  ( DomBuilder
  , Event
  , MonadHold
  , PerformEvent
  , Performable
  , PostBuild
  , Prerender
  , TriggerEvent
  , current
  , def
  , dynText
  , elAttr
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

page
  :: ( DomBuilder t m
     , MonadFix m
     , MonadHold t m
     , PostBuild t m
     , PerformEvent t m
     , Prerender t m
     , TriggerEvent t m
     , MonadJSM (Performable m)
     , RouteToUrl (R FrontendRoute) m
     , SetRoute t (R FrontendRoute) m
     )
  => m (Event t ())
page = mdo
  regEv <-
    elAttr "div" ("class" =: "min-h-[calc(100vh-4rem)] flex items-center justify-center p-6") $
      elAttr "div" ("class" =: "card w-full max-w-sm bg-base-100 shadow-md") $
        elAttr "div" ("class" =: "card-body") $
          signupWidget errEv
  res <- performRegister regEv
  let okEv  = fmapMaybe (either (const Nothing) Just) res
      errEv = fmapMaybe (either Just (const Nothing)) res
  setRoute ((FrontendRoute_Home :/ ()) <$ okEv)
  pure (() <$ okEv)

-- | Reads timezone from the browser at PostBuild and uses the latest
-- value when the user submits. Locale defaults to English (no picker
-- yet).
signupWidget
  :: ( DomBuilder t m
     , MonadHold t m
     , PostBuild t m
     , PerformEvent t m
     , Prerender t m
     , MonadJSM (Performable m)
     , RouteToUrl (R FrontendRoute) m
     , SetRoute t (R FrontendRoute) m
     )
  => Event t Text
  -> m (Event t RegisterRequest)
signupWidget errorEv = do
  elAttr "h1" ("class" =: "card-title text-2xl mb-2") $ text "Create account"
  errorD <- holdDyn "" errorEv
  pb     <- getPostBuild
  tzEv   <- performEvent (getTimezone <$ pb)
  tzD    <- holdDyn "UTC" tzEv
  (submitEv, (usernameIn, pwIn)) <- formEl $ do
    usernameIn <- labelled "signup-username" "Username" $ inputElement $ def
      & inputElementConfig_elementConfig . elementConfig_initialAttributes
          .~ ( "type"         =: "text"
            <> "autocomplete" =: "username"
            <> "id"           =: "signup-username"
            <> "class"        =: "input input-bordered w-full"
             )
    pwIn <- labelled "signup-password" "Password" $ inputElement $ def
      & inputElementConfig_elementConfig . elementConfig_initialAttributes
          .~ ( "type"         =: "password"
            <> "autocomplete" =: "new-password"
            <> "id"           =: "signup-password"
            <> "class"        =: "input input-bordered w-full"
             )
    submitButtonClass "btn btn-primary w-full mt-2" iconUserPlus "Create account"
    elAttr "p" ("class" =: "text-error text-sm mt-2 min-h-[1.25rem]") $ dynText errorD
    pure (usernameIn, pwIn)
  elAttr "p" ("class" =: "text-sm text-center mt-2") $ do
    text "Already have an account? "
    routeLink (FrontendRoute_Login :/ ()) $
      elAttr "span" ("class" =: "link link-primary") $ text "Sign in"
    text "."
  let reqB = mkRegister
        <$> _inputElement_value usernameIn
        <*> _inputElement_value pwIn
        <*> tzD
  pure $ fmapMaybe id (current reqB <@ submitEv)

mkRegister :: Text -> Text -> Text -> Maybe RegisterRequest
mkRegister u p tz =
  RegisterRequest
    <$> hush (mkUsername u)
    <*> hush (mkPassword p)
    <*> pure LocaleEn
    <*> pure tz

hush :: Either e a -> Maybe a
hush = either (const Nothing) Just
