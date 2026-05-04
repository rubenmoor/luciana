{-# LANGUAGE TypeApplications #-}

module Backend.Notifications
  ( handlers
  ) where

import Backend.Api (AppContext)
import Backend.App (App, runBeamApp)
import Backend.Schema.Db (lucianaDb)
import Backend.Schema.NotificationPref
  ( NotificationMode (..)
  , NotificationPrefT (..)
  )
import Backend.Schema.User (UserId)
import Common.Api (RoutesNotifications)
import Common.Notifications
  ( NotificationMode (Daily, RedOnly, YellowRed)
  , NotificationPrefsResponse (..)
  )
import Data.Time (TimeOfDay (..))
import Database.Beam
import Database.Beam.Postgres (onConflict, onConflictUpdateSet, conflictingFields)
import Relude
import Servant (ServerT, (:<|>) ((:<|>)))

handlers :: ServerT RoutesNotifications AppContext App
handlers = getPrefs :<|> putPrefs

getPrefs :: UserId -> App NotificationPrefsResponse
getPrefs uid = do
  mPrefs <- runBeamApp $ runSelectReturningOne $ select $ do
    prefs <- all_ (_notificationPrefs lucianaDb)
    guard_ (notificationPrefUserId prefs ==. val_ uid)
    pure prefs
  case mPrefs of
    Just p -> pure $ toResponse p
    Nothing -> pure $ NotificationPrefsResponse (TimeOfDay 8 0 0) Daily

putPrefs :: UserId -> NotificationPrefsResponse -> App NotificationPrefsResponse
putPrefs uid req = do
  _ <- runBeamApp $ runInsert $ insert (_notificationPrefs lucianaDb) $
    insertExpressions
      [ NotificationPref
          { notificationPrefUserId    = val_ uid
          , notificationPrefSendTime  = val_ (nprSendTime req)
          , notificationPrefMode      = val_ (toSchemaMode $ nprMode req)
          , notificationPrefUpdatedAt = default_
          }
      ]
    `onConflict` conflictingFields notificationPrefUserId
    `onConflictUpdateSet` (\e ->
        [ notificationPrefSendTime e <-. val_ (nprSendTime req)
        , notificationPrefMode e     <-. val_ (toSchemaMode $ nprMode req)
        , notificationPrefUpdatedAt e <-. default_
        ]
      )
  pure req

toResponse :: NotificationPrefT Identity -> NotificationPrefsResponse
toResponse p = NotificationPrefsResponse
  { nprSendTime = notificationPrefSendTime p
  , nprMode     = fromSchemaMode $ notificationPrefMode p
  }

toSchemaMode :: Common.Notifications.NotificationMode -> Backend.Schema.NotificationPref.NotificationMode
toSchemaMode = \case
  Daily     -> ModeDaily
  YellowRed -> ModeYellowRed
  RedOnly   -> ModeRedOnly

fromSchemaMode :: Backend.Schema.NotificationPref.NotificationMode -> Common.Notifications.NotificationMode
fromSchemaMode = \case
  ModeDaily     -> Daily
  ModeYellowRed -> YellowRed
  ModeRedOnly   -> RedOnly
