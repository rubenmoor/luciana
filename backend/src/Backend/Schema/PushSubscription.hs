-- | DeriveAnyClass / DeriveGeneric: same rationale as Backend.Schema.Session.
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}

module Backend.Schema.PushSubscription
  ( PushSubscriptionT (..)
  , PushSubscription
  , PushSubscriptionId
  , PrimaryKey (PushSubscriptionId)
  ) where

import Backend.Schema.User (UserT)
import Data.Functor.Identity (Identity)
import Data.Time (UTCTime)
import Database.Beam
  ( Beamable
  , C
  , PrimaryKey
  , Table (PrimaryKey, primaryKey)
  )
import Database.Beam.Backend.SQL.Types (SqlSerial)
import Relude
  ( Generic
  , Int64
  , Maybe
  , Text
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
