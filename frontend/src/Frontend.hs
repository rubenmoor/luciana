{-# LANGUAGE TemplateHaskell #-}

module Frontend where

import Common.Route (FrontendRoute (..))
import Obelisk.Frontend (Frontend (Frontend, _frontend_body, _frontend_head))
import Obelisk.Generated.Static (static)
import Obelisk.Route (R)
import Obelisk.Route.Frontend (subRoute_)
import Reflex.Dom.Core (blank, el, elAttr, text, (=:))
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
  , _frontend_body = subRoute_ $ \case
      FrontendRoute_Home     -> placeholder "Home"
      FrontendRoute_Calendar -> placeholder "Calendar"
      FrontendRoute_History  -> placeholder "History"
      FrontendRoute_Settings -> placeholder "Settings"
      FrontendRoute_Login    -> placeholder "Login"
      FrontendRoute_Signup   -> placeholder "Signup"
  }
  where
    placeholder name = el "h1" $ text $ name <> " (TODO)"
