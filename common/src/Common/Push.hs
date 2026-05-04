{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}

module Common.Push
  ( PushSubscribeRequest (..)
  , PushUnsubscribeRequest (..)
  ) where

import Data.Aeson (FromJSON, ToJSON)
import Relude

data PushSubscribeRequest = PushSubscribeRequest
  { psrqEndpoint  :: Text
  , psrqP256dh    :: Text
  , psrqAuth      :: Text
  , psrqUserAgent :: Maybe Text
  , psrqTimezone  :: Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

newtype PushUnsubscribeRequest = PushUnsubscribeRequest
  { purqEndpoint :: Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)
