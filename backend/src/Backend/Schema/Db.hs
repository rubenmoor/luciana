{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}

module Backend.Schema.Db
  ( LucianaDb (..)
  , lucianaDb
  , checkedLucianaDb
  ) where

import Backend.Schema.NotificationPref (NotificationPrefT (..))
import Backend.Schema.PeriodEntry (PeriodEntryT (..))
import Backend.Schema.PushSubscription (PushSubscriptionT (..))
import Backend.Schema.Session (SessionT (..))
import Backend.Schema.User (UserT (..))
import Database.Beam
  ( Database
  , DatabaseSettings
  , dbModification
  , defaultDbSettings
  , modifyTableFields
  , withDbModification
  )
import Database.Beam.Schema.Tables
  ( TableEntity
  , defaultFieldName
  , renamingFields
  )
import Database.Beam.Migrate
  ( CheckedDatabaseSettings
  , defaultMigratableDbSettings
  )
import Database.Beam.Postgres (Postgres)
import Relude
import qualified Data.Text as Text

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
lucianaDb = defaultDbSettings `withDbModification`
  dbModification
    { _users             = modifyTableFields (renamingFields (normalizeColumnName "user_"))
    , _sessions          = modifyTableFields (renamingFields (normalizeColumnName "session_"))
    , _periodEntries     = modifyTableFields (renamingFields (normalizeColumnName "period_entry_"))
    , _pushSubscriptions = modifyTableFields (renamingFields (normalizeColumnName "push_subscription_"))
    , _notificationPrefs = modifyTableFields (renamingFields (normalizeColumnName "notification_pref_"))
    }

normalizeColumnName :: Text -> NonEmpty Text -> Text
normalizeColumnName prefix path =
  stripNestedPkSuffix . stripPrefixOrSelf prefix $ defaultFieldName path

stripPrefixOrSelf :: Text -> Text -> Text
stripPrefixOrSelf prefix name =
  fromMaybe name (Text.stripPrefix prefix name)

stripNestedPkSuffix :: Text -> Text
stripNestedPkSuffix name =
  fromMaybe name (Text.stripSuffix "__id" name)
