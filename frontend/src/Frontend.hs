-- | RecursiveDo: auth state and the refresh event are mutually recursive
-- (auth state is consumed by route widgets that produce the refresh event).
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE TemplateHaskell #-}

module Frontend where

import Common.Auth (UserResponse (urUsername))
import Common.Route (FrontendRoute (..))
import Frontend.Auth
  ( AuthState (AuthSignedIn)
  , currentAuth
  , performLogout
  , requireSignedIn
  )
import qualified Frontend.Login as Login
import qualified Frontend.Signup as Signup
import Obelisk.Frontend (Frontend (Frontend, _frontend_body, _frontend_head))
import Obelisk.Generated.Static (static)
import Obelisk.Route (R, pattern (:/))
import Obelisk.Route.Frontend (SetRoute, setRoute, subRoute)
import Reflex.Dom.Core
  ( DomBuilder
  , Dynamic
  , Event
  , MonadHold
  , PostBuild
  , blank
  , domEvent
  , dyn
  , el
  , elAttr
  , elAttr'
  , ffor
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
        FrontendRoute_Login    -> Login.page
        FrontendRoute_Signup   -> Signup.page
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
          elAttr "span" ("class" =: "text-sm opacity-70") $ text (urUsername u)
          buttonClass "btn btn-sm btn-ghost" "Log out"
    _ -> pure never
  switchHold never evEv
