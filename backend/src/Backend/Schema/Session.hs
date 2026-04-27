-- | DeriveAnyClass: empty `Beamable` instance is generated from the stock
-- `Generic`; the alternative is hand-writing `zipBeamFieldsM`.
-- DeriveGeneric: required by `Beamable`'s default methods.
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}

module Backend.Schema.Session
  ( SessionT (..)
  , Session
  , SessionId
  , PrimaryKey (SessionId)
  ) where

import Backend.Schema.User (UserT)
import Data.ByteString (ByteString)
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
  , (.)
  )

data SessionT f = Session
  { sessionId        :: C f (SqlSerial Int64)
  , sessionUserId    :: PrimaryKey UserT f
  , sessionTokenHash :: C f ByteString
  , sessionCreatedAt :: C f UTCTime
  , sessionExpiresAt :: C f UTCTime
  }
  deriving stock (Generic)
  deriving anyclass (Beamable)

type Session = SessionT Identity

type SessionId = PrimaryKey SessionT Identity

instance Table SessionT where
  data PrimaryKey SessionT f = SessionId (C f (SqlSerial Int64))
    deriving stock (Generic)
    deriving anyclass (Beamable)
  primaryKey = SessionId . sessionId
