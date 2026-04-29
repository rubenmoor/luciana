-- | FlexibleContexts: Reflex constraints commonly need it.
-- ScopedTypeVariables: needed so `m` from formEl's signature is in scope
-- inside the body for the `Proxy :: Proxy (DomBuilderSpace m)` annotation.
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Frontend.Widget.Form
  ( labelled
  , formEl
  , buttonClass
  , submitButtonClass
  ) where

import Control.Lens ((%~))
import Reflex.Dom.Core
  ( DomBuilder
  , DomBuilderSpace
  , ElementConfig
  , Event
  , EventName (Click, Submit)
  , EventResult
  , addEventSpecFlags
  , def
  , domEvent
  , elAttr
  , elAttr'
  , element
  , elementConfig_eventSpec
  , preventDefault
  , text
  , (=:)
  )
import Relude

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

-- | A @type=button@ button with an icon preceding the text label. daisyUI's
--   @btn@ class applies the gap between icon and label.
buttonClass
  :: DomBuilder t m
  => Text   -- ^ button @class@ attribute
  -> m ()   -- ^ icon widget (rendered before the label)
  -> Text   -- ^ visible label text
  -> m (Event t ())
buttonClass cls icon label = do
  (e, _) <- elAttr' "button"
    ("type" =: "button" <> "class" =: cls) $ do
      icon
      text label
  pure $ domEvent Click e

-- | A @type=submit@ button with an icon preceding the text label. Inside a
--   <form>, this is the default button that receives Enter-key submission
--   and click submission alike.
submitButtonClass
  :: DomBuilder t m
  => Text   -- ^ button @class@ attribute
  -> m ()   -- ^ icon widget (rendered before the label)
  -> Text   -- ^ visible label text
  -> m ()
submitButtonClass cls icon label =
  elAttr "button"
    ("type" =: "submit" <> "class" =: cls) $ do
      icon
      text label
