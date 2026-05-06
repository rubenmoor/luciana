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
import Backend.Schema.User (PrimaryKey (UserId), UserT (..))
import Database.Beam
  ( Database
  , DatabaseSettings
  , dbModification
  , defaultDbSettings
  , modifyTableFields
  , withDbModification
  )
import Database.Beam.Schema.Tables
  ( FieldModification
  , TableField
  , fieldNamed
  , TableEntity
  )
import Database.Beam.Migrate
  ( CheckedDatabaseSettings
  , defaultMigratableDbSettings
  )
import Database.Beam.Postgres (Postgres)
import Relude

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
    { _users             = modifyTableFields userFields
    , _sessions          = modifyTableFields sessionFields
    , _periodEntries     = modifyTableFields periodEntryFields
    , _pushSubscriptions = modifyTableFields pushSubscriptionFields
    , _notificationPrefs = modifyTableFields notificationPrefFields
    }

userFields :: UserT (FieldModification (TableField UserT))
userFields = User
  { userId           = fieldNamed "id"
  , userUsername     = fieldNamed "username"
  , userPasswordHash = fieldNamed "password_hash"
  , userLocale       = fieldNamed "locale"
  , userTimezone     = fieldNamed "timezone"
  , userCreatedAt    = fieldNamed "created_at"
  }

sessionFields :: SessionT (FieldModification (TableField SessionT))
sessionFields = Session
  { sessionId        = fieldNamed "id"
  , sessionUserId    = UserId (fieldNamed "user_id")
  , sessionTokenHash = fieldNamed "token_hash"
  , sessionCreatedAt = fieldNamed "created_at"
  , sessionExpiresAt = fieldNamed "expires_at"
  }

periodEntryFields :: PeriodEntryT (FieldModification (TableField PeriodEntryT))
periodEntryFields = PeriodEntry
  { periodEntryId        = fieldNamed "id"
  , periodEntryUserId    = UserId (fieldNamed "user_id")
  , periodEntryStartDate = fieldNamed "start_date"
  , periodEntryEndDate   = fieldNamed "end_date"
  , periodEntryNotes     = fieldNamed "notes"
  , periodEntryCreatedAt = fieldNamed "created_at"
  }

pushSubscriptionFields :: PushSubscriptionT (FieldModification (TableField PushSubscriptionT))
pushSubscriptionFields = PushSubscription
  { pushSubscriptionId         = fieldNamed "id"
  , pushSubscriptionUserId     = UserId (fieldNamed "user_id")
  , pushSubscriptionEndpoint   = fieldNamed "endpoint"
  , pushSubscriptionP256dh     = fieldNamed "p256dh"
  , pushSubscriptionAuth       = fieldNamed "auth"
  , pushSubscriptionUserAgent  = fieldNamed "user_agent"
  , pushSubscriptionCreatedAt  = fieldNamed "created_at"
  , pushSubscriptionLastUsedAt = fieldNamed "last_used_at"
  }

notificationPrefFields :: NotificationPrefT (FieldModification (TableField NotificationPrefT))
notificationPrefFields = NotificationPref
  { notificationPrefUserId    = UserId (fieldNamed "user_id")
  , notificationPrefSendTime  = fieldNamed "send_time"
  , notificationPrefMode      = fieldNamed "mode"
  , notificationPrefUpdatedAt = fieldNamed "updated_at"
  }
