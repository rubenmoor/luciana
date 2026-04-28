{-# LANGUAGE GADTs #-}
{-# LANGUAGE PatternSynonyms #-}

module Backend.Api
  ( serveBackendRoute
  ) where

import Common.Route
  ( ApiRoute (..)
  , AuthRoute (..)
  , BackendRoute (..)
  , NotificationsRoute (..)
  , PeriodRoute (..)
  , PushRoute (..)
  )
import Obelisk.Route (R, pattern (:/))
import Relude
import Snap.Core (Snap)

serveBackendRoute :: R BackendRoute -> Snap ()
serveBackendRoute (br :/ v) = case br of
  BackendRoute_Missing -> pure ()
  BackendRoute_Vapid   -> pure ()
  BackendRoute_Api     -> serveApiRoute v

serveApiRoute :: R ApiRoute -> Snap ()
serveApiRoute (ar :/ v) = case ar of
  ApiRoute_Auth          -> serveAuthRoute v
  ApiRoute_Period        -> servePeriodRoute v
  ApiRoute_Notifications -> serveNotificationsRoute v
  ApiRoute_Push          -> servePushRoute v

serveAuthRoute :: R AuthRoute -> Snap ()
serveAuthRoute (ar :/ _) = case ar of
  AuthRoute_Register -> pure ()
  AuthRoute_Login    -> pure ()
  AuthRoute_Logout   -> pure ()
  AuthRoute_Me       -> pure ()

servePeriodRoute :: R PeriodRoute -> Snap ()
servePeriodRoute (pr :/ _) = case pr of
  PeriodRoute_Status  -> pure ()
  PeriodRoute_Entries -> pure ()
  PeriodRoute_Entry   -> pure ()

serveNotificationsRoute :: R NotificationsRoute -> Snap ()
serveNotificationsRoute (nr :/ _) = case nr of
  NotificationsRoute_Prefs -> pure ()

servePushRoute :: R PushRoute -> Snap ()
servePushRoute (pr :/ _) = case pr of
  PushRoute_Subscribe   -> pure ()
  PushRoute_Unsubscribe -> pure ()
