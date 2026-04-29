-- | FlexibleContexts: Reflex constraints commonly need it.
-- RecursiveDo: page wires the error event from performLogin back into
-- the widget that produced the submit event.
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RecursiveDo #-}

module Frontend.Login
  ( page
  ) where

import Common.Auth (LoginRequest (LoginRequest), mkPassword, mkUsername)
import Common.Route (FrontendRoute (FrontendRoute_Home, FrontendRoute_Signup))
import Control.Lens ((.~))
import Control.Monad.Fix (MonadFix)
import Frontend.Auth (performLogin)
import Frontend.Widget.Form (formEl, labelled, submitButtonClass)
import Frontend.Widget.Icon (iconArrowRightEndOnRectangle)
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
  , holdDyn
  , inputElement
  , inputElementConfig_elementConfig
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
  loginEv <-
    elAttr "div" ("class" =: "min-h-[calc(100vh-4rem)] flex items-center justify-center p-6") $
      elAttr "div" ("class" =: "card w-full max-w-sm bg-base-100 shadow-md") $
        elAttr "div" ("class" =: "card-body") $
          loginWidget errEv
  res <- performLogin loginEv
  let success = fmapMaybe (either (const Nothing) Just) res
      errEv   = fmapMaybe (either Just (const Nothing)) res
  setRoute ((FrontendRoute_Home :/ ()) <$ success)
  pure success

loginWidget
  :: ( DomBuilder t m
     , MonadHold t m
     , PostBuild t m
     , Prerender t m
     , RouteToUrl (R FrontendRoute) m
     , SetRoute t (R FrontendRoute) m
     )
  => Event t Text
  -> m (Event t LoginRequest)
loginWidget errorEv = do
  elAttr "h1" ("class" =: "card-title text-2xl mb-2") $ text "Sign in"
  errorD <- holdDyn "" errorEv
  (submitEv, (usernameIn, pwIn)) <- formEl $ do
    usernameIn <- labelled "login-username" "Username" $ inputElement $ def
      & inputElementConfig_elementConfig . elementConfig_initialAttributes
          .~ ( "type"         =: "text"
            <> "autocomplete" =: "username"
            <> "id"           =: "login-username"
            <> "class"        =: "input input-bordered w-full"
             )
    pwIn <- labelled "login-password" "Password" $ inputElement $ def
      & inputElementConfig_elementConfig . elementConfig_initialAttributes
          .~ ( "type"         =: "password"
            <> "autocomplete" =: "current-password"
            <> "id"           =: "login-password"
            <> "class"        =: "input input-bordered w-full"
             )
    submitButtonClass "btn btn-primary w-full mt-2" iconArrowRightEndOnRectangle "Sign in"
    elAttr "p" ("class" =: "text-error text-sm mt-2 min-h-[1.25rem]") $ dynText errorD
    pure (usernameIn, pwIn)
  elAttr "p" ("class" =: "text-sm text-center mt-2") $ do
    text "Not registered? "
    routeLink (FrontendRoute_Signup :/ ()) $
      elAttr "span" ("class" =: "link link-primary") $ text "Sign up here"
    text "."
  let reqB = mkLoginRequest
        <$> _inputElement_value usernameIn
        <*> _inputElement_value pwIn
  pure $ fmapMaybe id (current reqB <@ submitEv)

mkLoginRequest :: Text -> Text -> Maybe LoginRequest
mkLoginRequest u p = LoginRequest <$> hush (mkUsername u) <*> hush (mkPassword p)

hush :: Either e a -> Maybe a
hush = either (const Nothing) Just
