{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}

module Common.Notifications
  ( NotificationMode (..)
  , NotificationPrefsResponse (..)
  ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Time (TimeOfDay)
import Relude

data NotificationMode = Daily | YellowRed | RedOnly
  deriving stock (Eq, Show, Read, Generic)
  deriving anyclass (FromJSON, ToJSON)

data NotificationPrefsResponse = NotificationPrefsResponse
  { nprSendTime :: TimeOfDay
  , nprMode     :: NotificationMode
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)
