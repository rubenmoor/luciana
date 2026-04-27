{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}

module Backend.Schema.PushSubscription
  ( PushSubscriptionT (..)
  , PushSubscription
  , PushSubscriptionId
  , PrimaryKey (PushSubscriptionId)
  ) where

import Backend.Schema.User (UserT)
import Data.Functor.Identity (Identity)
import Database.Beam
  ( Beamable
  , C
  , PrimaryKey
  , SqlSerial
  , Table (PrimaryKey, primaryKey)
  )
import Relude
  ( Eq
  , Generic
  , Int64
  , Maybe
  , Show
  , Text
  , UTCTime
  , (.)
  )

data PushSubscriptionT f = PushSubscription
  { pushSubscriptionId         :: C f (SqlSerial Int64)
  , pushSubscriptionUserId     :: PrimaryKey UserT f
  , pushSubscriptionEndpoint   :: C f Text
  , pushSubscriptionP256dh     :: C f Text
  , pushSubscriptionAuth       :: C f Text
  , pushSubscriptionUserAgent  :: C f (Maybe Text)
  , pushSubscriptionCreatedAt  :: C f UTCTime
  , pushSubscriptionLastUsedAt :: C f (Maybe UTCTime)
  }
  deriving stock (Generic)
  deriving anyclass (Beamable)

type PushSubscription = PushSubscriptionT Identity

type PushSubscriptionId = PrimaryKey PushSubscriptionT Identity

instance Table PushSubscriptionT where
  data PrimaryKey PushSubscriptionT f = PushSubscriptionId (C f (SqlSerial Int64))
    deriving stock (Generic)
    deriving anyclass (Beamable)
  primaryKey = PushSubscriptionId . pushSubscriptionId

deriving stock instance Show PushSubscription
deriving stock instance Eq PushSubscription
