{-# LANGUAGE CPP #-}
{-# LANGUAGE TemplateHaskell #-}

module Frontend where

import Relude

import Common.Api (commonStuff)
import Common.Route (FrontendRoute)
import Control.Lens ((^.))
import qualified Data.Text as T (Text, pack)
import qualified Data.Text.Encoding as T (decodeUtf8')
import Language.Javascript.JSaddle (js, js1, jsg, liftJSM)
import Obelisk.Configs (getConfig)
import Obelisk.Frontend (Frontend (Frontend, _frontend_body, _frontend_head))
import Obelisk.Generated.Static (static)
import Obelisk.Route (R)
import Reflex.Dom.Core (blank, el, elAttr, prerender_, text, (=:))


-- This runs in a monad that can be run on the client or the server.
-- To run code in a pure client or pure server context, use one of the
-- `prerender` functions.
frontend :: Frontend (R FrontendRoute)
frontend = Frontend
  { _frontend_head = do
      el "title" $ text "Obelisk Minimal Example"
      elAttr "script" ("type" =: "application/javascript" <> "src" =: $(static "lib.js")) blank
      elAttr "link" ("href" =: $(static "main.css") <> "type" =: "text/css" <> "rel" =: "stylesheet") blank
  , _frontend_body = do
      el "h1" $ text "Welcome to Obelisk!"
      el "p" $ text $ T.pack commonStuff

      -- `prerender` and `prerender_` let you choose a widget to run on the server
      -- during prerendering and a different widget to run on the client with
      -- JavaScript. The following will generate a `blank` widget on the server and
      -- print "Hello, World!" on the client.
      prerender_ blank $ liftJSM $ void
        $ jsg ("window" :: T.Text)
        ^. js ("skeleton_lib" :: T.Text)
        ^. js1 ("log" :: T.Text) ("Hello, World!" :: T.Text)

      elAttr "img" ("src" =: $(static "obelisk.jpg")) blank
      el "div" $ do
        let
          cfg = "common/example"
          path = "config/" <> cfg
        getConfig cfg >>= \case
          Nothing -> text $ "No config file found in " <> path
          Just bytes -> case T.decodeUtf8' bytes of
            Left ue -> text $ "Couldn't decode " <> path <> " : " <> T.pack (show ue)
            Right s -> text s
      return ()
  }
