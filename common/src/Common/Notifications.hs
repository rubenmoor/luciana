{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}

module Common.Notifications
  ( NotificationMode (..)
  , NotificationPrefsResponse (..)
  ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Time (TimeOfDay)
import Deriving.Aeson
import Deriving.Aeson.Stock
import Relude

data NotificationMode = NotificationModeDaily | NotificationModeYellowRed | NotificationModeRedOnly
  deriving stock (Eq, Show, Read, Generic)
  deriving (FromJSON, ToJSON) via PrefixedSnake "NotificationMode" NotificationMode

data NotificationPrefsResponse = NotificationPrefsResponse
  { nprSendTime :: TimeOfDay
  , nprMode     :: NotificationMode
  }
  deriving stock (Eq, Show, Generic)
  deriving (FromJSON, ToJSON) via PrefixedSnake "npr" NotificationPrefsResponse
