module Backend.Db
  ( DbPool
  , withDbPool
  , withConn
  , loadDbUrl
  ) where

import Control.Exception (bracket)
import Data.Pool (Pool, createPool, destroyAllResources, withResource)
import Database.PostgreSQL.Simple (Connection, close, connectPostgreSQL)
import Obelisk.ExecutableConfig.Lookup (getConfigs)
import Relude
import qualified Data.ByteString.Char8 as BS8
import qualified Data.Map.Strict as Map

newtype DbPool = DbPool (Pool Connection)

withDbPool :: ByteString -> (DbPool -> IO a) -> IO a
withDbPool url action =
  bracket acquire destroyAllResources (action . DbPool)
  where
    acquire :: IO (Pool Connection)
    acquire = createPool (connectPostgreSQL url) close 1 60 10

withConn :: DbPool -> (Connection -> IO a) -> IO a
withConn (DbPool p) = withResource p

loadDbUrl :: IO ByteString
loadDbUrl = do
  cfgs <- getConfigs
  case Map.lookup "backend/db-url" cfgs of
    Nothing  -> die "config/backend/db-url is missing — run pg-init"
    Just raw -> pure (BS8.strip raw)
