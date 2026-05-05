{-# LANGUAGE TypeApplications #-}

module Backend.Auth.Session
  ( createSession
  , lookupSession
  , deleteSession
  , bumpSession
  , deleteExpiredSessions
  ) where

import Backend.Db (Pg)
import Backend.Schema.Db (LucianaDb (..), lucianaDb)
import Backend.Schema.Session
  ( SessionT (..)
  )
import Backend.Schema.User (PrimaryKey (UserId))
import Data.Time (UTCTime, getCurrentTime)
import Database.Beam
  ( (==.)
  , (<.)
  , (<-.)
  , (>.)
  , (&&.)
  , all_
  , default_
  , delete
  , guard_
  , insert
  , insertExpressions
  , runDelete
  , runInsert
  , runSelectReturningOne
  , runUpdate
  , select
  , update
  , val_
  )
import Database.Beam.Backend.SQL.Types (SqlSerial (..))
import Relude

createSession :: Int64 -> ByteString -> UTCTime -> Pg ()
createSession uid tokenHash expiresAt = do
  now <- liftIO getCurrentTime
  runInsert $ insert (_sessions lucianaDb) $
    insertExpressions
      [ Session
          { sessionId        = default_
          , sessionUserId    = val_ (UserId (SqlSerial uid))
          , sessionTokenHash = val_ tokenHash
          , sessionCreatedAt = val_ now
          , sessionExpiresAt = val_ expiresAt
          }
      ]

lookupSession :: ByteString -> Pg (Maybe (Int64, UTCTime))
lookupSession tokenHash = do
  now <- liftIO getCurrentTime
  mSession <- runSelectReturningOne $ select $ do
    s <- all_ (_sessions lucianaDb)
    guard_ (sessionTokenHash s ==. val_ tokenHash &&. sessionExpiresAt s >. val_ now)
    pure s
  pure $ case mSession of
    Just s -> let UserId (SqlSerial uid) = sessionUserId s in Just (uid, sessionExpiresAt s)
    Nothing -> Nothing

deleteSession :: ByteString -> Pg ()
deleteSession tokenHash =
  runDelete $ delete (_sessions lucianaDb) $ \s ->
    sessionTokenHash s ==. val_ tokenHash

bumpSession :: ByteString -> UTCTime -> Pg ()
bumpSession tokenHash newExpiry =
  runUpdate $ update (_sessions lucianaDb)
    (\s -> sessionExpiresAt s <-. val_ newExpiry)
    (\s -> sessionTokenHash s ==. val_ tokenHash)

deleteExpiredSessions :: Pg ()
deleteExpiredSessions = do
  now <- liftIO getCurrentTime
  runDelete $ delete (_sessions lucianaDb) $ \s ->
    sessionExpiresAt s <. val_ now
