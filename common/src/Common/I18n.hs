module Common.I18n
  ( Locale (..)
  , localeToText
  , localeFromText
  ) where

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
