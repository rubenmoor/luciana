-- | DeriveAnyClass / DeriveGeneric: empty `Beamable` instance from stock
-- `Generic`. The remaining four extensions are required by the beam SQL
-- instances for `NotificationMode`: same multi-parameter / Paterson story as
-- in Backend.Schema.User.
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE UndecidableInstances #-}

module Backend.Schema.NotificationPref
  ( NotificationPrefT (..)
  , NotificationPref
  , NotificationPrefId
  , PrimaryKey (NotificationPrefKey)
  , NotificationMode (..)
  , notificationModeToText
  , notificationModeFromText
  ) where

import Backend.Schema.User (UserT)
import Data.Functor.Identity (Identity)
import Data.Time (TimeOfDay, UTCTime)
import Database.Beam
  ( Beamable
  , C
  , PrimaryKey
  , Table (PrimaryKey, primaryKey)
  )
import Database.Beam.Backend.SQL (HasSqlValueSyntax (sqlValueSyntax))
import Database.Beam.Backend.SQL.Row (FromBackendRow (fromBackendRow))
import Database.Beam.Backend.Types (BeamBackend)
import Database.Beam.Migrate (HasDefaultSqlDataType (defaultSqlDataType))
import Database.Beam.Postgres (Postgres)
import Relude
  ( Applicative (pure)
  , Bounded
  , Enum
  , Eq
  , Generic
  , Maybe (Just, Nothing)
  , MonadFail (fail)
  , Proxy (Proxy)
  , Show
  , Text
  , ($)
  , (.)
  , (<$>)
  , (<>)
  , toString
  )

data NotificationMode
  = ModeDaily
  | ModeYellowRed
  | ModeRedOnly
  deriving stock (Bounded, Enum, Eq, Generic, Show)

notificationModeToText :: NotificationMode -> Text
notificationModeToText = \case
  ModeDaily     -> "Daily"
  ModeYellowRed -> "YellowRed"
  ModeRedOnly   -> "RedOnly"

notificationModeFromText :: Text -> Maybe NotificationMode
notificationModeFromText = \case
  "Daily"     -> Just ModeDaily
  "YellowRed" -> Just ModeYellowRed
  "RedOnly"   -> Just ModeRedOnly
  _           -> Nothing

instance HasSqlValueSyntax be Text => HasSqlValueSyntax be NotificationMode where
  sqlValueSyntax = sqlValueSyntax . notificationModeToText

instance (BeamBackend be, FromBackendRow be Text) => FromBackendRow be NotificationMode where
  fromBackendRow = do
    t <- fromBackendRow
    case notificationModeFromText t of
      Just m  -> pure m
      Nothing -> fail $ "Unknown notification mode: " <> toString t

instance HasDefaultSqlDataType Postgres NotificationMode where
  defaultSqlDataType _ p embedded = defaultSqlDataType (Proxy :: Proxy Text) p embedded

data NotificationPrefT f = NotificationPref
  { notificationPrefUserId    :: PrimaryKey UserT f
  , notificationPrefSendTime  :: C f TimeOfDay
  , notificationPrefMode      :: C f NotificationMode
  , notificationPrefUpdatedAt :: C f UTCTime
  }
  deriving stock (Generic)
  deriving anyclass (Beamable)

type NotificationPref = NotificationPrefT Identity

type NotificationPrefId = PrimaryKey NotificationPrefT Identity

instance Table NotificationPrefT where
  data PrimaryKey NotificationPrefT f = NotificationPrefKey (PrimaryKey UserT f)
    deriving stock (Generic)
    deriving anyclass (Beamable)
  primaryKey = NotificationPrefKey . notificationPrefUserId
