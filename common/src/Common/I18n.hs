-- | DeriveGeneric: stock-derive `Generic` so future serialisers (JSON, beam
-- backend instances) can use generic machinery without writing per-type code.
{-# LANGUAGE DeriveGeneric #-}

module Common.I18n
  ( Locale (..)
  , localeToText
  , localeFromText
  ) where

import Data.Aeson (FromJSON (parseJSON), ToJSON (toJSON), withText)
import Relude

data Locale
  = LocaleDe
  | LocaleEn
  deriving stock (Bounded, Enum, Eq, Generic, Show)

localeToText :: Locale -> Text
localeToText = \case
  LocaleDe -> "de"
  LocaleEn -> "en"

localeFromText :: Text -> Maybe Locale
localeFromText = \case
  "de" -> Just LocaleDe
  "en" -> Just LocaleEn
  _    -> Nothing

instance ToJSON Locale where
  toJSON = toJSON . localeToText

instance FromJSON Locale where
  parseJSON = withText "Locale" $ \t -> case localeFromText t of
    Just l  -> pure l
    Nothing -> fail "expected 'de' or 'en'"
