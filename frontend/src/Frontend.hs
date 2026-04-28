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
  , button
  , dyn
  , el
  , elAttr
  , ffor
  , fmapMaybe
  , leftmost
  , never
  , prerender_
  , switchDyn
  , switchHold
  , text
  , (=:)
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
    placeholder name = el "h1" $ text $ name <> " (TODO)"

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
    AuthSignedIn u -> el "header" $ do
      el "span" $ text (urEmail u)
      button "Log out"
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
  loginEv <- loginWidget errEv
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
  regEv <- signupWidget errEv
  res   <- performRegister regEv
  let success = fmapMaybe (either (const Nothing) Just) res
      errEv   = fmapMaybe (either Just (const Nothing)) res
  setRoute ((FrontendRoute_Home :/ ()) <$ success)
  pure success
