-- | DeriveAnyClass / DeriveGeneric: empty `Beamable` instances generated from
-- stock `Generic`. GeneralizedNewtypeDeriving: `deriving newtype (Eq)` on
-- TZName lifts the underlying Text instance.
-- The remaining four extensions are required by the beam SQL instances for
-- `TZName`: same multi-parameter / Paterson story as for `NotificationMode`.
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE UndecidableInstances #-}

module Backend.Schema.User
  ( UserT (..)
  , User
  , UserId
  , PrimaryKey (UserId)
  , TZName (..)
  ) where

import Backend.Schema.Locale (DbLocale)
import Data.Aeson (FromJSON, ToJSON)
import Data.Time (UTCTime)
import Database.Beam
  ( Beamable
  , C
  , PrimaryKey
  , Table (PrimaryKey, primaryKey)
  )
import Database.Beam.Backend.SQL (HasSqlValueSyntax (sqlValueSyntax))
import Database.Beam.Backend.SQL.Row (FromBackendRow (fromBackendRow))
import Database.Beam.Backend.SQL.Types (SqlSerial)
import Database.Beam.Backend.Types (BeamBackend)
import Database.Beam.Migrate (HasDefaultSqlDataType (defaultSqlDataType))
import Database.Beam.Postgres (Postgres)
import Relude

data UserT f = User
  { userId           :: C f (SqlSerial Int64)
  , userUsername     :: C f Text
  , userPasswordHash :: C f Text
  , userLocale       :: C f DbLocale
  , userTimezone     :: C f TZName
  , userCreatedAt    :: C f UTCTime
  }
  deriving stock (Generic)
  deriving anyclass (Beamable)

type User = UserT Identity

type UserId = PrimaryKey UserT Identity

instance Table UserT where
  data PrimaryKey UserT f = UserId (C f (SqlSerial Int64))
    deriving stock (Generic)
    deriving anyclass (Beamable)
  primaryKey = UserId . userId

newtype TZName = TZName { unTZName :: Text }
  deriving stock (Eq, Show)
  deriving newtype (FromJSON, ToJSON)

instance HasSqlValueSyntax be Text => HasSqlValueSyntax be TZName where
  sqlValueSyntax = sqlValueSyntax . unTZName

instance (BeamBackend be, FromBackendRow be Text) => FromBackendRow be TZName where
  fromBackendRow = TZName <$> fromBackendRow

instance HasDefaultSqlDataType Postgres TZName where
  defaultSqlDataType _ p embedded = defaultSqlDataType (Proxy :: Proxy Text) p embedded
