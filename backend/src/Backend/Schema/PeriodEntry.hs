{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}

module Backend.Schema.PeriodEntry
  ( PeriodEntryT (..)
  , PeriodEntry
  , PeriodEntryId
  , PrimaryKey (PeriodEntryId)
  ) where

import Backend.Schema.User (UserT)
import Data.Functor.Identity (Identity)
import Data.Time (Day)
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

deriving stock instance Show PeriodEntry
deriving stock instance Eq PeriodEntry
