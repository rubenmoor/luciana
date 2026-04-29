-- | DeriveAnyClass / DeriveGeneric: empty `Beamable` instances generated from
-- stock `Generic`. GeneralizedNewtypeDeriving: `deriving newtype (Eq)` on
-- TZName lifts the underlying Text instance.
-- The remaining four extensions are required by the orphan beam SQL instances
-- for `Locale` and `TZName` below: those classes are multi-parameter
-- (HasSqlValueSyntax, FromBackendRow, HasDefaultSqlDataType) and the instance
-- heads contain free type variables (e.g. `HasSqlValueSyntax be TZName`),
-- triggering Paterson conditions that need UndecidableInstances.
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Backend.Schema.User
  ( UserT (..)
  , User
  , UserId
  , PrimaryKey (UserId)
  , TZName (..)
  ) where

import Common.I18n (Locale, localeFromText, localeToText)
import Data.Functor.Identity (Identity)
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
  ( Eq
  , Generic
  , Int64
  , Maybe (Just, Nothing)
  , MonadFail (fail)
  , Proxy (Proxy)
  , Show
  , Text
  , ($)
  , (.)
  , (<$>)
  , (<>)
  , pure
  , toString
  )

data UserT f = User
  { userId           :: C f (SqlSerial Int64)
  , userUsername     :: C f Text
  , userPasswordHash :: C f Text
  , userLocale       :: C f Locale
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
  deriving stock (Show)
  deriving newtype (Eq)

instance HasSqlValueSyntax be Text => HasSqlValueSyntax be TZName where
  sqlValueSyntax = sqlValueSyntax . unTZName

instance (BeamBackend be, FromBackendRow be Text) => FromBackendRow be TZName where
  fromBackendRow = TZName <$> fromBackendRow

instance HasDefaultSqlDataType Postgres TZName where
  defaultSqlDataType _ p embedded = defaultSqlDataType (Proxy :: Proxy Text) p embedded

instance HasSqlValueSyntax be Text => HasSqlValueSyntax be Locale where
  sqlValueSyntax = sqlValueSyntax . localeToText

instance (BeamBackend be, FromBackendRow be Text) => FromBackendRow be Locale where
  fromBackendRow = do
    t <- fromBackendRow
    case localeFromText t of
      Just l  -> pure l
      Nothing -> fail $ "Unknown locale: " <> toString t

instance HasDefaultSqlDataType Postgres Locale where
  defaultSqlDataType _ p embedded = defaultSqlDataType (Proxy :: Proxy Text) p embedded
