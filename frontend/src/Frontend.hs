-- | RecursiveDo: auth state and the refresh event are mutually recursive
-- (auth state is consumed by route widgets that produce the refresh event).
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE TemplateHaskell #-}

module Frontend where

import Common.Auth (UserResponse (urEmail))
import Control.Monad.Fix (MonadFix)
import Common.Route (FrontendRoute (..))
import Frontend.Auth
  ( AuthState (AuthSignedIn)
  , currentAuth
  , performLogin
  , performLogout
  , performRegister
  , requireSignedIn
  )
import Frontend.Auth.Widget (loginWidget, signupWidget)
import Language.Javascript.JSaddle (MonadJSM)
import Obelisk.Frontend (Frontend (Frontend, _frontend_body, _frontend_head))
import Obelisk.Generated.Static (static)
import Obelisk.Route (R, pattern (:/))
import Obelisk.Route.Frontend (SetRoute, setRoute, subRoute)
import Reflex.Dom.Core
  ( DomBuilder
  , Dynamic
  , Event
  , MonadHold
  , PerformEvent
  , Performable
  , PostBuild
  , TriggerEvent
  , blank
  , domEvent
  , dyn
  , el
  , elAttr
  , elAttr'
  , ffor
  , fmapMaybe
  , leftmost
  , never
  , prerender_
  , switchDyn
  , switchHold
  , text
  , (=:)
  , EventName (Click)
  )
import Relude

frontend :: Frontend (R FrontendRoute)
frontend = Frontend
  { _frontend_head = do
      el "title" $ text "Luciana"
      elAttr "link"
        ( "href" =: $(static "styles.css")
       <> "type" =: "text/css"
       <> "rel"  =: "stylesheet"
        ) blank
  , _frontend_body = prerender_ blank $ mdo
      authStateD    <- currentAuth refreshEv
      logoutClickEv <- topBar authStateD
      logoutDoneEv  <- performLogout logoutClickEv
      setRoute ((FrontendRoute_Login :/ ()) <$ logoutDoneEv)
      pageEvDyn <- subRoute $ \case
        FrontendRoute_Home     -> gateRoute authStateD (placeholder "Home")
        FrontendRoute_Calendar -> gateRoute authStateD (placeholder "Calendar")
        FrontendRoute_History  -> gateRoute authStateD (placeholder "History")
        FrontendRoute_Settings -> gateRoute authStateD (placeholder "Settings")
        FrontendRoute_Login    -> loginPage
        FrontendRoute_Signup   -> signupPage
      let pageEv    = switchDyn pageEvDyn
          refreshEv = leftmost [logoutDoneEv, pageEv]
      pure ()
  }
  where
    placeholder name = page name $ text "TODO"

----------------------------------------------------------------------
-- Helpers

-- | Render a page with a container and a bold title.
page :: DomBuilder t m => Text -> m a -> m a
page title inner = elAttr "main" ("class" =: "container mx-auto p-6") $ do
  elAttr "h1" ("class" =: "text-3xl font-bold mb-4") $ text title
  inner

-- | A button element that accepts a CSS class string.
buttonClass
  :: DomBuilder t m => Text -> Text -> m (Event t ())
buttonClass cls label = do
  (e, _) <- elAttr' "button"
    ("type" =: "button" <> "class" =: cls)
    (text label)
  pure $ domEvent Click e

----------------------------------------------------------------------

gateRoute
  :: ( DomBuilder t m
     , PostBuild t m
     , SetRoute t (R FrontendRoute) m
     )
  => Dynamic t AuthState
  -> m ()
  -> m (Event t ())
gateRoute st inner = do
  requireSignedIn st inner
  pure never

topBar
  :: ( DomBuilder t m
     , MonadHold t m
     , PostBuild t m
     )
  => Dynamic t AuthState
  -> m (Event t ())
topBar st = do
  evEv <- dyn $ ffor st $ \case
    AuthSignedIn u ->
      elAttr "div" ("class" =: "navbar bg-base-200 shadow-sm") $ do
        elAttr "div" ("class" =: "flex-1 px-2 text-lg font-semibold") $ text "Luciana"
        elAttr "div" ("class" =: "flex-none gap-2") $ do
          elAttr "span" ("class" =: "text-sm opacity-70") $ text (urEmail u)
          buttonClass "btn btn-sm btn-ghost" "Log out"
    _ -> pure never
  switchHold never evEv

loginPage
  :: ( DomBuilder t m
     , MonadFix m
     , MonadHold t m
     , PostBuild t m
     , PerformEvent t m
     , TriggerEvent t m
     , MonadJSM (Performable m)
     , SetRoute t (R FrontendRoute) m
     )
  => m (Event t ())
loginPage = mdo
  loginEv <-
    elAttr "div" ("class" =: "min-h-[calc(100vh-4rem)] flex items-center justify-center p-6") $
      elAttr "div" ("class" =: "card w-full max-w-sm bg-base-100 shadow-md") $
        elAttr "div" ("class" =: "card-body") $
          loginWidget errEv
  res     <- performLogin loginEv
  let success = fmapMaybe (either (const Nothing) Just) res
      errEv   = fmapMaybe (either Just (const Nothing)) res
  setRoute ((FrontendRoute_Home :/ ()) <$ success)
  pure success

signupPage
  :: ( DomBuilder t m
     , MonadFix m
     , MonadHold t m
     , PostBuild t m
     , PerformEvent t m
     , TriggerEvent t m
     , MonadJSM (Performable m)
     , SetRoute t (R FrontendRoute) m
     )
  => m (Event t ())
signupPage = mdo
  regEv <-
    elAttr "div" ("class" =: "min-h-[calc(100vh-4rem)] flex items-center justify-center p-6") $
      elAttr "div" ("class" =: "card w-full max-w-sm bg-base-100 shadow-md") $
        elAttr "div" ("class" =: "card-body") $
          signupWidget errEv
  res   <- performRegister regEv
  let success = fmapMaybe (either (const Nothing) Just) res
      errEv   = fmapMaybe (either Just (const Nothing)) res
  setRoute ((FrontendRoute_Home :/ ()) <$ success)
  pure success
