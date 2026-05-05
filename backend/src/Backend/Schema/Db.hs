{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}

module Backend.Schema.Db
  ( LucianaDb (..)
  , lucianaDb
  , checkedLucianaDb
  ) where

import Backend.Schema.NotificationPref (NotificationPrefT(..))
import Backend.Schema.PeriodEntry (PeriodEntryT(..))
import Backend.Schema.PushSubscription (PushSubscriptionT(..))
import Backend.Schema.Session (SessionT(..))
import Backend.Schema.User (UserT(..))
import Database.Beam
  ( Database
  , DatabaseSettings
  , dbModification
  , defaultDbSettings
  , modifyTableFields
  , withDbModification
  , Beamable
  )
import Database.Beam.Schema.Tables
  ( FieldModification(..)
  , TableField(..)
  , fieldNamed
  , _fieldName
  , changeBeamRep
  , Columnar'(..)
  , TableEntity
  , DatabaseEntity(..)
  , DatabaseEntityDescriptor(..)
  )
import Database.Beam.Migrate
  ( CheckedDatabaseSettings
  , defaultMigratableDbSettings
  )
import Database.Beam.Postgres (Postgres)
import Relude
import qualified Data.Text as T
import Data.Char (isUpper, toLower)
import Data.List (stripPrefix)

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
lucianaDb = 
  let db = defaultDbSettings
      extract (DatabaseEntity (DatabaseTable _ _ _ settings)) = settings
  in db `withDbModification`
    dbModification
      { _users             = modifyTableFields (applyGlobalNaming (extract (_users db)))
      , _sessions          = modifyTableFields (applyGlobalNaming (extract (_sessions db)))
      , _periodEntries     = modifyTableFields (applyGlobalNaming (extract (_periodEntries db)))
      , _pushSubscriptions = modifyTableFields (applyGlobalNaming (extract (_pushSubscriptions db)))
      , _notificationPrefs = modifyTableFields (applyGlobalNaming (extract (_notificationPrefs db)))
      }

-- | customSnakeCase maps camelCase to snake_case, but also
-- handles our specific "concise" requirements:
-- 1. Strip common prefixes (e.g., 'user', 'session', 'periodEntry').
-- 2. Map resulting 'Id' to 'id'.
-- 3. Map other fields to snake_case.
customSnakeCase :: String -> String
customSnakeCase name =
  let
    prefixes = ["user", "session", "periodEntry", "pushSubscription", "notificationPref"]
    stripPrefixes [] s = s
    stripPrefixes (p:ps) s =
      case stripPrefix p s of
        Just res -> res
        Nothing -> stripPrefixes ps s
    s' = stripPrefixes prefixes name
  in if s' == "Id" then "id" else camelToSnake s'

camelToSnake :: String -> String
camelToSnake [] = []
camelToSnake (c:cs) = toLower c : concatMap (\x -> if isUpper x then ['_', toLower x] else [x]) cs

-- | A generic function that strips prefixes and converts to snake_case.
applyGlobalNaming :: (Beamable table) => table (TableField table) -> table (FieldModification (TableField table))
applyGlobalNaming = changeBeamRep $ \(Columnar' field) ->
  Columnar' (fieldNamed (T.pack (customSnakeCase (T.unpack (_fieldName field)))))
