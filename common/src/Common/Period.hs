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
import Deriving.Aeson
import Deriving.Aeson.Stock
import Relude
import Servant.API (FromHttpApiData, ToHttpApiData)

data PeriodPhase = PeriodPhaseGreen | PeriodPhaseYellow | PeriodPhaseRed
  deriving stock (Eq, Show, Generic)
  deriving (FromJSON, ToJSON) via PrefixedSnake "PeriodPhase" PeriodPhase

data PeriodStatusResponse = PeriodStatusResponse
  { psrPhase        :: PeriodPhase
  , psrDayInCycle   :: Int
  , psrNextExpected :: Day
  }
  deriving stock (Eq, Show, Generic)
  deriving (FromJSON, ToJSON) via PrefixedSnake "psr" PeriodStatusResponse

newtype PeriodEntryId = PeriodEntryId { unPeriodEntryId :: Int64 }
  deriving stock (Eq, Show, Generic)
  deriving newtype (FromJSON, ToJSON, FromHttpApiData, ToHttpApiData)

data PeriodEntryResponse = PeriodEntryResponse
  { perId        :: PeriodEntryId
  , perStartDate :: Day
  , perEndDate   :: Maybe Day
  , perNotes     :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)
  deriving (FromJSON, ToJSON) via PrefixedSnake "per" PeriodEntryResponse

data PeriodEntryRequest = PeriodEntryRequest
  { peqStartDate :: Day
  , peqEndDate   :: Maybe Day
  , peqNotes     :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)
  deriving (FromJSON, ToJSON) via PrefixedSnake "peq" PeriodEntryRequest

newtype CreatePeriodEntryResponse = CreatePeriodEntryResponse
  { cperId :: PeriodEntryId
  }
  deriving stock (Eq, Show, Generic)
  deriving (FromJSON, ToJSON) via PrefixedSnake "cper" CreatePeriodEntryResponse
