module Backend.Auth.Session
  ( createSession
  , lookupSession
  , deleteSession
  , bumpSession
  , deleteExpiredSessions
  ) where

import Backend.Schema.Db (lucianaDb)
import Backend.Schema.Session
import Backend.Schema.User (PrimaryKey (UserId))
import Data.Time (UTCTime, getCurrentTime)
import Database.Beam
import Database.Beam.Backend.SQL.Types (SqlSerial (..))
import Database.Beam.Postgres (Postgres, runBeamPostgres)
import Database.PostgreSQL.Simple (Connection)
import Relude

createSession :: Connection -> Int64 -> ByteString -> UTCTime -> IO ()
createSession conn uid tokenHash expiresAt = do
  now <- getCurrentTime
  runBeamPostgres conn $ runInsert $ insert (_sessions lucianaDb) $
    insertExpressions
      [ Session
          { sessionId        = default_
          , sessionUserId    = val_ (UserId (SqlSerial uid))
          , sessionTokenHash = val_ tokenHash
          , sessionCreatedAt = val_ now
          , sessionExpiresAt = val_ expiresAt
          }
      ]

lookupSession :: Connection -> ByteString -> IO (Maybe (Int64, UTCTime))
lookupSession conn tokenHash = do
  mSession <- runBeamPostgres conn $ runSelectReturningOne $ select $ do
    s <- all_ (_sessions lucianaDb)
    guard_ (sessionTokenHash s ==. val_ tokenHash &&. sessionExpiresAt s >. now_())
    pure s
  pure $ case mSession of
    Just s -> let UserId (SqlSerial uid) = sessionUserId s in Just (uid, sessionExpiresAt s)
    Nothing -> Nothing

deleteSession :: Connection -> ByteString -> IO ()
deleteSession conn tokenHash =
  runBeamPostgres conn $ runDelete $ delete (_sessions lucianaDb) $ \s ->
    sessionTokenHash s ==. val_ tokenHash

bumpSession :: Connection -> ByteString -> UTCTime -> IO ()
bumpSession conn tokenHash newExpiry =
  runBeamPostgres conn $ runUpdate $ update (_sessions lucianaDb)
    (\s -> [ sessionExpiresAt s <-. val_ newExpiry ])
    (\s -> sessionTokenHash s ==. val_ tokenHash)

deleteExpiredSessions :: Connection -> IO Int64
deleteExpiredSessions conn =
  runBeamPostgres conn $ runDelete $ delete (_sessions lucianaDb) $ \s ->
    sessionExpiresAt s <. now_()
