-- | FlexibleContexts: Reflex constraints commonly need it.
-- RecursiveDo: renderToasts ties the children's dismiss events back into
-- the map of currently-visible toasts.
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE TupleSections #-}

module Frontend.Toast
  ( Toast (..)
  , ToastMsg (..)
  , tellToast
  , translateToast
  , getBrowserLocale
  , toastLocale
  , renderToasts
  ) where

import Common.I18n (Locale (..), localeFromText)
import Control.Monad.Fix (MonadFix)
import qualified Data.Aeson as Aeson
import qualified Data.Map.Strict as Map (empty, fromList, keys, size, union)
import Data.Time.Clock (NominalDiffTime)
import Frontend.Widget.Icon (iconCheckCircle, iconExclamationTriangle)
import Language.Javascript.JSaddle
  ( MonadJSM
  , eval
  , fromJSValUnchecked
  , liftJSM
  )
import Reflex.Dom.Core
  ( DomBuilder
  , Dynamic
  , Event
  , EventName (Click)
  , EventWriter
  , MonadHold
  , PerformEvent
  , Performable
  , PostBuild
  , Reflex
  , TriggerEvent
  , attachWith
  , current
  , delay
  , domEvent
  , elAttr
  , elAttr'
  , elClass'
  , ffor2
  , foldDyn
  , gate
  , getPostBuild
  , headE
  , holdDyn
  , leftmost
  , listHoldWithKey
  , mergeMap
  , mergeWith
  , never
  , performEvent
  , switchDyn
  , tellEvent
  , text
  , (=:)
  )
import Relude

----------------------------------------------------------------------
-- Types

-- | Closed enum of every toast string the app can show. Translated to
-- Text at render time via 'translateToast'.
data ToastMsg
  = MsgLoggedIn
  | MsgLoggedOut
  | MsgAccountCreated
  | MsgServerError
  | MsgBadRequest
  | MsgRateLimited
  | MsgNetworkError
  deriving stock (Eq, Show)

-- | Two-case sum: success carries only a message; error optionally
-- carries arbitrary diagnostic JSON shown behind a "Details" toggle.
data Toast
  = ToastSuccess ToastMsg
  | ToastError   ToastMsg (Maybe Aeson.Value)
  deriving stock (Eq, Show)

-- | Helper for widgets that fire toasts; threads through 'EventWriter'.
tellToast
  :: (Reflex t, EventWriter t [Toast] m)
  => Event t Toast
  -> m ()
tellToast = tellEvent . fmap (:[])

----------------------------------------------------------------------
-- Translation

translateToast :: Locale -> ToastMsg -> Text
translateToast = \case
  LocaleEn -> \case
    MsgLoggedIn       -> "Logged in"
    MsgLoggedOut      -> "Logged out"
    MsgAccountCreated -> "Account created"
    MsgServerError    -> "Server error"
    MsgBadRequest     -> "Bad request"
    MsgRateLimited    -> "Too many attempts \x2014 try again later"
    MsgNetworkError   -> "Network error"
  LocaleDe -> \case
    MsgLoggedIn       -> "Angemeldet"
    MsgLoggedOut      -> "Abgemeldet"
    MsgAccountCreated -> "Konto erstellt"
    MsgServerError    -> "Serverfehler"
    MsgBadRequest     -> "Ung\xfcltige Anfrage"
    MsgRateLimited    -> "Zu viele Versuche \x2014 bitte sp\xe4ter erneut"
    MsgNetworkError   -> "Netzwerkfehler"

----------------------------------------------------------------------
-- Locale source

getBrowserLocale :: MonadJSM m => m Locale
getBrowserLocale = liftJSM $ do
  v <- eval ("(navigator.language || 'en').slice(0, 2)" :: Text)
  s <- fromJSValUnchecked v
  pure (fromMaybe LocaleEn (localeFromText s))

-- | Resolve the active locale: the user's stored preference when
-- signed in (passed in as @Just locale@), otherwise the browser's
-- @navigator.language@.
toastLocale
  :: ( PostBuild t m
     , PerformEvent t m
     , MonadHold t m
     , MonadJSM (Performable m)
     )
  => Dynamic t (Maybe Locale)
  -> m (Dynamic t Locale)
toastLocale userLocaleD = do
  pb <- getPostBuild
  browserEv <- performEvent (getBrowserLocale <$ pb)
  browserD <- holdDyn LocaleEn browserEv
  pure $ ffor2 userLocaleD browserD (flip fromMaybe)

----------------------------------------------------------------------
-- Renderer

-- | Display newly-arriving toasts, keyed by an incrementing id, and
-- handle their auto-dismiss. The locale is sampled once per toast at
-- insert time; mid-flight locale changes do not reflow visible toasts.
renderToasts
  :: ( DomBuilder t m
     , MonadFix m
     , MonadHold t m
     , PostBuild t m
     , PerformEvent t m
     , TriggerEvent t m
     , MonadIO (Performable m)
     )
  => Dynamic t Locale
  -> Event t [Toast]
  -> m ()
renderToasts localeD toastsEv = do
  let snapshotEv = attachWith
        (\loc ts -> (loc,) <$> ts)
        (current localeD)
        toastsEv
  nextIdD <- foldDyn (+) (0 :: Int) (length <$> snapshotEv)
  let insertPatchEv = attachWith
        (\base lts -> Map.fromList $ zip [base ..] (Just <$> lts))
        (current nextIdD)
        snapshotEv
  rec
    let deletePatchEv = fmap (const Nothing) <$> dismissEv
        patchEv = mergeWith Map.union [insertPatchEv, deletePatchEv]
    childrenD <- elAttr "div" ("class" =: "toast toast-end") $
      listHoldWithKey Map.empty patchEv $ \_ (loc, t) -> renderOne loc t
    let dismissEv = switchDyn (mergeMap <$> childrenD)
  pure ()

-- | Render a single toast and return its dismiss event (auto-timer or
-- close button).
renderOne
  :: ( DomBuilder t m
     , MonadHold t m
     , PostBuild t m
     , PerformEvent t m
     , TriggerEvent t m
     , MonadIO (Performable m)
     )
  => Locale
  -> Toast
  -> m (Event t ())
renderOne loc = \case
  ToastSuccess msg -> do
    elAttr "div" ("class" =: "alert alert-success") $ do
      iconCheckCircle
      elAttr "span" mempty $ text (translateToast loc msg)
    timer 4
  ToastError msg mDetails ->
    elAttr "div" ("class" =: "alert alert-error") $ do
      iconExclamationTriangle
      elAttr "span" mempty $ text (translateToast loc msg)
      openEv <- case mDetails of
        Nothing  -> pure never
        Just val -> do
          (_detEl, sEl) <- elClass' "details" "w-full" $ do
            (s, _) <- elClass' "summary" "cursor-pointer text-xs opacity-70" $
              text "Details"
            elAttr "pre" ("class" =: "text-xs mt-1 whitespace-pre-wrap break-all") $
              text (prettyJson val)
            pure s
          pure (domEvent Click sEl)
      openOnceEv <- headE openEv
      armedD     <- holdDyn True (False <$ openOnceEv)
      autoDismiss <- timer 8
      let timerDismiss = gate (current armedD) autoDismiss
      (closeEl, _) <- elAttr' "button"
        ( "type"       =: "button"
       <> "class"      =: "btn btn-ghost btn-xs btn-circle"
       <> "aria-label" =: "Close"
        )
        (text "\x2715")
      let closeEv = domEvent Click closeEl
      pure (leftmost [timerDismiss, closeEv])

-- | Fire a single () event after @secs@ seconds of being on screen.
timer
  :: ( PostBuild t m
     , PerformEvent t m
     , TriggerEvent t m
     , MonadIO (Performable m)
     )
  => NominalDiffTime
  -> m (Event t ())
timer secs = do
  pb <- getPostBuild
  delay secs pb

prettyJson :: Aeson.Value -> Text
prettyJson = decodeUtf8 . Aeson.encode
