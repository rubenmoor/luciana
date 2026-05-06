{-# LANGUAGE DeriveGeneric #-}

module Common.I18n
  ( Locale (..)
  , localeToText
  , localeFromText
  ) where

import Data.Aeson (FromJSON, ToJSON)
import Deriving.Aeson
import Deriving.Aeson.Stock
import Relude

data Locale
  = LocaleDe
  | LocaleEn
  deriving stock (Bounded, Enum, Eq, Generic, Show)
  deriving (FromJSON, ToJSON) via PrefixedSnake "Locale" Locale

localeToText :: Locale -> Text
localeToText = \case
  LocaleDe -> "de"
  LocaleEn -> "en"

localeFromText :: Text -> Maybe Locale
localeFromText = \case
  "de" -> Just LocaleDe
  "en" -> Just LocaleEn
  _    -> Nothing
