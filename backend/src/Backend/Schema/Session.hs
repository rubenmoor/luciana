{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}

module Backend.Schema.Session
  ( SessionT (..)
  , Session
  , SessionId
  , PrimaryKey (SessionId)
  ) where

import Backend.Schema.User (UserT)
import Data.ByteString (ByteString)
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
  , Show
  , UTCTime
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

deriving stock instance Show Session
deriving stock instance Eq Session
