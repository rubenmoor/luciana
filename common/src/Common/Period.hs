{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Common.Period
  ( PeriodPhase (..)
  , PeriodStatusResponse (..)
  , PeriodEntryId (..)
  , PeriodEntryResponse (..)
  , PeriodEntryRequest (..)
  , CreatePeriodEntryResponse (..)
  ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Time (Day)
import Relude
import Servant.API (FromHttpApiData)

data PeriodPhase = Green | Yellow | Red
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

data PeriodStatusResponse = PeriodStatusResponse
  { psrPhase        :: PeriodPhase
  , psrDayInCycle   :: Int
  , psrNextExpected :: Day
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

newtype PeriodEntryId = PeriodEntryId { unPeriodEntryId :: Int64 }
  deriving stock (Eq, Show, Generic)
  deriving newtype (FromJSON, ToJSON, FromHttpApiData)

data PeriodEntryResponse = PeriodEntryResponse
  { perId        :: PeriodEntryId
  , perStartDate :: Day
  , perEndDate   :: Maybe Day
  , perNotes     :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

data PeriodEntryRequest = PeriodEntryRequest
  { peqStartDate :: Day
  , peqEndDate   :: Maybe Day
  , peqNotes     :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

newtype CreatePeriodEntryResponse = CreatePeriodEntryResponse
  { cperId :: PeriodEntryId
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)
