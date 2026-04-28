module Backend.Auth.Session
  ( createSession
  , lookupSession
  , deleteSession
  , bumpSession
  , deleteExpiredSessions
  ) where

import Data.Time (UTCTime)
import Database.PostgreSQL.Simple
  ( Connection
  , Only (Only)
  , execute
  , execute_
  , query
  )
import Database.PostgreSQL.Simple.Types (Binary (Binary))
import Relude

createSession :: Connection -> Int64 -> ByteString -> UTCTime -> IO ()
createSession conn uid tokenHash expiresAt = do
  _ <- execute conn
    "INSERT INTO sessions (user_id, token_hash, expires_at) VALUES (?, ?, ?)"
    (uid, Binary tokenHash, expiresAt)
  pass

lookupSession :: Connection -> ByteString -> IO (Maybe (Int64, UTCTime))
lookupSession conn tokenHash = do
  rows <-
    query conn
      "SELECT user_id, expires_at FROM sessions \
      \WHERE token_hash = ? AND expires_at > now()"
      (Only (Binary tokenHash))
  pure $ case rows of
    [(uid, expiresAt)] -> Just (uid, expiresAt)
    _                  -> Nothing

deleteSession :: Connection -> ByteString -> IO ()
deleteSession conn tokenHash = do
  _ <- execute conn
    "DELETE FROM sessions WHERE token_hash = ?"
    (Only (Binary tokenHash))
  pass

bumpSession :: Connection -> ByteString -> UTCTime -> IO ()
bumpSession conn tokenHash newExpiry = do
  _ <- execute conn
    "UPDATE sessions SET expires_at = ? WHERE token_hash = ?"
    (newExpiry, Binary tokenHash)
  pass

deleteExpiredSessions :: Connection -> IO Int64
deleteExpiredSessions conn =
  execute_ conn "DELETE FROM sessions WHERE expires_at < now()"
