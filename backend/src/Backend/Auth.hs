-- | NumericUnderscores: readable sleep interval literals.
{-# LANGUAGE NumericUnderscores #-}

module Backend.Auth
  ( forkSessionCleanup
  , loadUserResponse
  , generateToken
  , hashToken
  , sessionLifetime
  , bumpThreshold
  , newExpiry
  , shouldBump
  ) where

import Backend.Auth.RateLimit ()
import Backend.Auth.Session (deleteExpiredSessions)
import Backend.Db (Pg, runBeam)
import Backend.Env (Env, envPool)
import Backend.Schema.Locale (unDbLocale)
import Backend.Schema.Db (LucianaDb (..), lucianaDb)
import Backend.Schema.User (TZName (unTZName), UserT (..))
import Common.Auth (UserResponse (..))
import Database.Beam
  ( (==.)
  , all_
  , guard_
  , runSelectReturningOne
  , select
  , val_
  )
import Database.Beam.Backend.SQL.Types (SqlSerial (..))
import Control.Concurrent (ThreadId, forkIO, threadDelay)
import Crypto.Hash (Digest, SHA256(..), hash)
import qualified Crypto.Random.Entropy as Entropy (getEntropy)
import qualified Data.ByteArray as BA (convert)
import qualified Data.ByteString.Base64.URL as B64Url (encodeUnpadded)
import Data.Time
  ( NominalDiffTime
  , UTCTime
  , addUTCTime
  , diffUTCTime
  )
import Relude

forkSessionCleanup :: Env -> IO ThreadId
forkSessionCleanup env = forkIO $ forever $ do
  threadDelay (60 * 60 * 1_000_000)
  runBeam (envPool env) (void deleteExpiredSessions)

----------------------------------------------------------------------
-- Token & timing

generateToken :: IO Text
generateToken = do
  bytes <- Entropy.getEntropy 32 :: IO ByteString
  pure (decodeUtf8 (B64Url.encodeUnpadded bytes))

hashToken :: ByteString -> ByteString
hashToken raw = BA.convert (hash raw :: Digest SHA256)

sessionLifetime :: NominalDiffTime
sessionLifetime = 60 * 60 * 24 * 30

bumpThreshold :: NominalDiffTime
bumpThreshold = 60 * 60 * 24

newExpiry :: UTCTime -> UTCTime
newExpiry = addUTCTime sessionLifetime

-- | True iff the last bump was more than 'bumpThreshold' ago, i.e. the
-- remaining lifetime is shorter than @sessionLifetime - bumpThreshold@.
shouldBump :: UTCTime -> UTCTime -> Bool
shouldBump now expiresAt =
  diffUTCTime expiresAt now < (sessionLifetime - bumpThreshold)

----------------------------------------------------------------------
-- User lookup (shared by Login, Register, Me)

loadUserResponse :: Int64 -> Pg (Maybe UserResponse)
loadUserResponse uid = do
  mUser <- runSelectReturningOne $ select $ do
    u <- all_ (_users lucianaDb)
    guard_ (userId u ==. val_ (SqlSerial uid))
    pure u
  pure $ toResponse <$> mUser

toResponse :: UserT Identity -> UserResponse
toResponse u = UserResponse
  { urId       = let SqlSerial i = userId u in i
  , urUsername = userUsername u
  , urLocale   = unDbLocale (userLocale u)
  , urTimezone = unTZName (userTimezone u)
  }
