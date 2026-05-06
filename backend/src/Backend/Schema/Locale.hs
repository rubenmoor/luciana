-- | Backend-local bridge type for persisting 'Common.I18n.Locale' via Beam.
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE UndecidableInstances #-}

module Backend.Schema.Locale
  ( DbLocale (..)
  ) where

import Common.I18n (Locale, localeFromText, localeToText)
import Database.Beam.Backend.SQL (HasSqlValueSyntax (sqlValueSyntax))
import Database.Beam.Backend.SQL.Row (FromBackendRow (fromBackendRow))
import Database.Beam.Backend.Types (BeamBackend)
import Database.Beam.Migrate (HasDefaultSqlDataType (defaultSqlDataType))
import Database.Beam.Postgres (Postgres)
import Relude

newtype DbLocale = DbLocale { unDbLocale :: Locale }
  deriving stock (Eq, Show)

instance HasSqlValueSyntax be Text => HasSqlValueSyntax be DbLocale where
  sqlValueSyntax = sqlValueSyntax . localeToText . unDbLocale

instance (BeamBackend be, FromBackendRow be Text) => FromBackendRow be DbLocale where
  fromBackendRow = do
    t <- fromBackendRow
    case localeFromText t of
      Just l  -> pure (DbLocale l)
      Nothing -> fail $ "Unknown locale: " <> toString t

instance HasDefaultSqlDataType Postgres DbLocale where
  defaultSqlDataType _ p embedded = defaultSqlDataType (Proxy :: Proxy Text) p embedded
