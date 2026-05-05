{-# LANGUAGE TypeApplications #-}

module Backend.Notifications
  ( handlers
  ) where

import Backend.App (App, AppContext, runBeamApp)
import Backend.Auth.Combinator ()
import Backend.RateLimit.Combinator ()
import Backend.Schema.Db (LucianaDb (..), lucianaDb)
import Backend.Schema.NotificationPref
  ( NotificationMode (..)
  , NotificationPrefT (..)
  )
import Backend.Schema.User (PrimaryKey (UserId))
import Common.Api (RoutesNotifications)
import Common.Notifications
  ( NotificationMode (Daily, RedOnly, YellowRed)
  , NotificationPrefsResponse (..)
  )
import Data.Time (TimeOfDay (..))
import Database.Beam
  ( (==.)
  , (<-.)
  , all_
  , default_
  , guard_
  , insertExpressions
  , runInsert
  , runSelectReturningOne
  , select
  , val_
  )
import Database.Beam.Postgres ()
import Database.Beam.Postgres.Full (insertOnConflict, onConflictUpdateSet, conflictingFields)
import Database.Beam.Backend.SQL.Types (SqlSerial (..))
import Relude
import Servant (ServerT, (:<|>) ((:<|>)))

handlers :: ServerT RoutesNotifications AppContext App
handlers = getPrefs :<|> putPrefs

getPrefs :: Int64 -> App NotificationPrefsResponse
getPrefs uid = do
  mPrefs <- runBeamApp $ runSelectReturningOne $ select $ do
    prefs <- all_ (_notificationPrefs lucianaDb)
    guard_ (notificationPrefUserId prefs ==. UserId (val_ (SqlSerial uid)))
    pure prefs
  case mPrefs of
    Just p -> pure $ toResponse p
    Nothing -> pure $ NotificationPrefsResponse (TimeOfDay 8 0 0) Daily

putPrefs :: Int64 -> NotificationPrefsResponse -> App NotificationPrefsResponse
putPrefs uid req = do
  _ <- runBeamApp $ runInsert $ insertOnConflict (_notificationPrefs lucianaDb)
    (insertExpressions
      [ NotificationPref
          { notificationPrefUserId    = UserId (val_ (SqlSerial uid))
          , notificationPrefSendTime  = val_ (nprSendTime req)
          , notificationPrefMode      = val_ (toSchemaMode $ nprMode req)
          , notificationPrefUpdatedAt = default_
          }
      ])
    (conflictingFields notificationPrefUserId)
    (onConflictUpdateSet $ \e _ -> mconcat
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
