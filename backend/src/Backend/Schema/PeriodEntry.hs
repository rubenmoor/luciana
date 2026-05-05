-- | DeriveAnyClass / DeriveGeneric: same rationale as Backend.Schema.Session.
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}

module Backend.Schema.PeriodEntry
  ( PeriodEntryT (..)
  , PeriodEntry
  , PeriodEntryId
  , PrimaryKey (PeriodEntryId)
  ) where

import Backend.Schema.User (UserT)
import Data.Time (Day, UTCTime)
import Database.Beam
  ( Beamable
  , C
  , PrimaryKey
  , Table (PrimaryKey, primaryKey)
  )
import Database.Beam.Backend.SQL.Types (SqlSerial)
import Relude

data PeriodEntryT f = PeriodEntry
  { periodEntryId        :: C f (SqlSerial Int64)
  , periodEntryUserId    :: PrimaryKey UserT f
  , periodEntryStartDate :: C f Day
  , periodEntryEndDate   :: C f (Maybe Day)
  , periodEntryNotes     :: C f (Maybe Text)
  , periodEntryCreatedAt :: C f UTCTime
  }
  deriving stock (Generic)
  deriving anyclass (Beamable)

type PeriodEntry = PeriodEntryT Identity

type PeriodEntryId = PrimaryKey PeriodEntryT Identity

instance Table PeriodEntryT where
  data PrimaryKey PeriodEntryT f = PeriodEntryId (C f (SqlSerial Int64))
    deriving stock (Generic)
    deriving anyclass (Beamable)
  primaryKey = PeriodEntryId . periodEntryId
