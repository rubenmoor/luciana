{-# LANGUAGE GADTs #-}
{-# LANGUAGE PatternSynonyms #-}

module Backend.Api
  ( serveBackendRoute
  ) where

import Backend.Auth
  ( AuthEnv
  , handleLogin
  , handleLogout
  , handleMe
  , handleRegister
  )
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

serveBackendRoute :: AuthEnv -> R BackendRoute -> Snap ()
serveBackendRoute env (br :/ v) = case br of
  BackendRoute_Missing -> pure ()
  BackendRoute_Vapid   -> pure ()
  BackendRoute_Api     -> serveApiRoute env v

serveApiRoute :: AuthEnv -> R ApiRoute -> Snap ()
serveApiRoute env (ar :/ v) = case ar of
  ApiRoute_Auth          -> serveAuthRoute env v
  ApiRoute_Period        -> servePeriodRoute v
  ApiRoute_Notifications -> serveNotificationsRoute v
  ApiRoute_Push          -> servePushRoute v

serveAuthRoute :: AuthEnv -> R AuthRoute -> Snap ()
serveAuthRoute env (ar :/ _) = case ar of
  AuthRoute_Register -> handleRegister env
  AuthRoute_Login    -> handleLogin env
  AuthRoute_Logout   -> handleLogout env
  AuthRoute_Me       -> handleMe env

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
