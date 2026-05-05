module Backend.Schema.Migration
  ( MigrationMode (..)
  , readMigrationMode
  , runMigrations
  ) where

import Backend.Db (DbPool, withConn)
import Database.PostgreSQL.Simple
  ( Connection
  , Only (Only, fromOnly)
  , execute
  , execute_
  , query_
  , withTransaction
  )
import Database.PostgreSQL.Simple.Types (Query (Query))
import Relude
import System.Exit (ExitCode (ExitFailure))
import qualified Data.Set as Set (member)
import qualified Data.ByteString.Char8 as BS8

data MigrationMode
  = MigrateAuto    -- apply silently (dev default)
  | MigratePrint   -- print pending SQL, exit 1 if any
  | MigrateApply   -- print + apply in a transaction (prod)
  deriving stock (Eq, Show)

readMigrationMode :: IO MigrationMode
readMigrationMode = do
  v <- lookupEnv "LUCIANA_MIGRATIONS"
  case v of
    Nothing       -> pure MigrateAuto
    Just "auto"   -> pure MigrateAuto
    Just "print"  -> pure MigratePrint
    Just "apply"  -> pure MigrateApply
    Just other    -> die $ "LUCIANA_MIGRATIONS: unknown value " <> other

runMigrations :: DbPool -> MigrationMode -> IO ()
runMigrations pool mode = withConn pool $ \conn -> do
  _ <- execute_ conn migrationsTableDdl
  pending <- pendingSteps conn
  case (pending, mode) of
    ([], _) -> putTextLn "migrations: schema up to date"
    (steps, MigratePrint) -> do
      putTextLn "migrations: pending steps:"
      forM_ steps $ \(name, sql) -> do
        putTextLn $ "-- " <> name
        putStrLn (BS8.unpack sql)
      exitWith (ExitFailure 1)
    (steps, _) -> withTransaction conn $
      forM_ steps $ \(name, sql) -> do
        putTextLn $ "migrations: applying " <> name
        _ <- execute_ conn (Query sql)
        _ <- execute conn
          "INSERT INTO schema_migrations (version) VALUES (?)"
          (Only name)
        pass

migrationsTableDdl :: Query
migrationsTableDdl =
  "CREATE TABLE IF NOT EXISTS schema_migrations \
  \( version TEXT PRIMARY KEY \
  \, applied_at TIMESTAMPTZ NOT NULL DEFAULT now() )"

allSteps :: [(Text, ByteString)]
allSteps = [("0001_initial", initialSql)]

pendingSteps :: Connection -> IO [(Text, ByteString)]
pendingSteps conn = do
  rows <- query_ conn "SELECT version FROM schema_migrations" :: IO [Only Text]
  let applied = fromList (fromOnly <$> rows) :: Set Text
  pure [step | step@(name, _) <- allSteps, not (Set.member name applied)]

initialSql :: ByteString
initialSql = BS8.unlines
  [ "CREATE TABLE users"
  , "( id            BIGSERIAL  PRIMARY KEY"
  , ", username      TEXT       NOT NULL"
  , ", password_hash TEXT       NOT NULL"
  , ", locale        TEXT       NOT NULL CHECK (locale IN ('de','en'))"
  , ", timezone      TEXT       NOT NULL"
  , ", created_at    TIMESTAMPTZ NOT NULL DEFAULT now()"
  , ");"
  , "CREATE UNIQUE INDEX users_username_lower_idx ON users (lower(username));"
  , ""
  , "CREATE TABLE sessions"
  , "( id         BIGSERIAL  PRIMARY KEY"
  , ", user_id    BIGINT     NOT NULL REFERENCES users(id) ON DELETE CASCADE"
  , ", token_hash BYTEA      NOT NULL UNIQUE"
  , ", created_at TIMESTAMPTZ NOT NULL DEFAULT now()"
  , ", expires_at TIMESTAMPTZ NOT NULL"
  , ");"
  , "CREATE INDEX sessions_expires_at_idx ON sessions (expires_at);"
  , ""
  , "CREATE TABLE period_entries"
  , "( id         BIGSERIAL  PRIMARY KEY"
  , ", user_id    BIGINT     NOT NULL REFERENCES users(id) ON DELETE CASCADE"
  , ", start_date DATE       NOT NULL"
  , ", end_date   DATE       NULL"
  , ", notes      TEXT       NULL"
  , ", created_at TIMESTAMPTZ NOT NULL DEFAULT now()"
  , ", CHECK (end_date IS NULL OR end_date >= start_date)"
  , ");"
  , "CREATE INDEX period_entries_user_start_idx \
    \ON period_entries (user_id, start_date DESC);"
  , ""
  , "CREATE TABLE push_subscriptions"
  , "( id           BIGSERIAL  PRIMARY KEY"
  , ", user_id      BIGINT     NOT NULL REFERENCES users(id) ON DELETE CASCADE"
  , ", endpoint     TEXT       NOT NULL UNIQUE"
  , ", p256dh       TEXT       NOT NULL"
  , ", auth         TEXT       NOT NULL"
  , ", user_agent   TEXT       NULL"
  , ", created_at   TIMESTAMPTZ NOT NULL DEFAULT now()"
  , ", last_used_at TIMESTAMPTZ NULL"
  , ");"
  , "CREATE INDEX push_subscriptions_user_id_idx \
    \ON push_subscriptions (user_id);"
  , ""
  , "CREATE TABLE notification_prefs"
  , "( user_id    BIGINT     PRIMARY KEY \
    \REFERENCES users(id) ON DELETE CASCADE"
  , ", send_time  TIME       NOT NULL"
  , ", mode       TEXT       NOT NULL \
    \CHECK (mode IN ('Daily','YellowRed','RedOnly'))"
  , ", updated_at TIMESTAMPTZ NOT NULL DEFAULT now()"
  , ");"
  ]
