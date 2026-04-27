{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE StandaloneDeriving #-}

module Backend.Schema.Db
  ( LucianaDb (..)
  , lucianaDb
  , checkedLucianaDb
  ) where

import Backend.Schema.NotificationPref (NotificationPrefT)
import Backend.Schema.PeriodEntry (PeriodEntryT)
import Backend.Schema.PushSubscription (PushSubscriptionT)
import Backend.Schema.Session (SessionT)
import Backend.Schema.User (UserT)
import Database.Beam
  ( Database
  , DatabaseSettings
  , TableEntity
  )
import Database.Beam.Migrate
  ( CheckedDatabaseSettings
  , defaultMigratableDbSettings
  , unCheckDatabase
  )
import Database.Beam.Postgres (Postgres)
import Relude (Generic)

data LucianaDb f = LucianaDb
  { _users             :: f (TableEntity UserT)
  , _sessions          :: f (TableEntity SessionT)
  , _periodEntries     :: f (TableEntity PeriodEntryT)
  , _pushSubscriptions :: f (TableEntity PushSubscriptionT)
  , _notificationPrefs :: f (TableEntity NotificationPrefT)
  }
  deriving stock (Generic)
  deriving anyclass (Database be)

checkedLucianaDb :: CheckedDatabaseSettings Postgres LucianaDb
checkedLucianaDb = defaultMigratableDbSettings

lucianaDb :: DatabaseSettings Postgres LucianaDb
lucianaDb = unCheckDatabase checkedLucianaDb
