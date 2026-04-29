-- | NumericUnderscores: readable sleep interval literals.
{-# LANGUAGE NumericUnderscores #-}

module Backend.Auth
  ( AuthEnv
  , aePool
  , aeRateLimiter
  , aeCookieSecure
  , mkAuthEnv
  , forkSessionCleanup
  , requireUser
  , setSessionCookie
  , loadUserResponse
  , generateToken
  , hashToken
  , parseJsonBody
  , writeJson
  , errorStatus
  , unauthorized
  ) where

import Backend.Auth.Cookie (issueCookieHeader, readCookieToken)
import Backend.Auth.RateLimit (RateLimiter, newRateLimiter)
import Backend.Auth.Session
  ( bumpSession
  , createSession
  , deleteExpiredSessions
  , lookupSession
  )
import Backend.Db (DbPool, withConn)
import Common.Auth (UserResponse (UserResponse))
import Common.I18n (localeFromText)
import Database.PostgreSQL.Simple (Only (Only), query)
import Control.Concurrent (ThreadId, forkIO, threadDelay)
import qualified Crypto.Hash as Hash
import qualified Crypto.Random.Entropy as Entropy
import qualified Data.Aeson as Aeson
import qualified Data.ByteArray as BA
import qualified Data.ByteString.Base64.URL as B64Url
import Data.Time
  ( NominalDiffTime
  , UTCTime
  , addUTCTime
  , diffUTCTime
  , getCurrentTime
  )
import Relude
import Snap.Core
  ( Snap
  , addHeader
  , finishWith
  , getResponse
  , modifyResponse
  , readRequestBody
  , setHeader
  , setResponseStatus
  , writeLBS
  )

data AuthEnv = AuthEnv
  { aePool         :: DbPool
  , aeRateLimiter  :: RateLimiter
  , aeCookieSecure :: Bool
  }

mkAuthEnv :: DbPool -> IO AuthEnv
mkAuthEnv pool = AuthEnv pool <$> newRateLimiter <*> readSecureFlag

-- | Cookie 'Secure' flag. Defaults to insecure (dev). Production deploys must
-- export @LUCIANA_COOKIE_SECURE=true@.
readSecureFlag :: IO Bool
readSecureFlag = do
  v <- lookupEnv "LUCIANA_COOKIE_SECURE"
  pure (v == Just "true")

forkSessionCleanup :: AuthEnv -> IO ThreadId
forkSessionCleanup env = forkIO $ forever $ do
  threadDelay (60 * 60 * 1_000_000)
  withConn (aePool env) $ \c ->
    void (deleteExpiredSessions c)

----------------------------------------------------------------------
-- Token & timing

generateToken :: IO Text
generateToken = do
  bytes <- Entropy.getEntropy 32 :: IO ByteString
  pure (decodeUtf8 (B64Url.encodeUnpadded bytes))

hashToken :: ByteString -> ByteString
hashToken raw = BA.convert (Hash.hash raw :: Hash.Digest Hash.SHA256)

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
-- requireUser

requireUser :: AuthEnv -> Snap Int64
requireUser env = do
  mTok <- readCookieToken
  case mTok of
    Nothing  -> unauthorized
    Just raw -> do
      let h = hashToken raw
      mFound <- liftIO $ withConn (aePool env) $ \c ->
        lookupSession c h
      case mFound of
        Nothing -> unauthorized
        Just (uid, expiresAt) -> do
          now <- liftIO getCurrentTime
          when (shouldBump now expiresAt) $
            liftIO $ withConn (aePool env) $ \c ->
              bumpSession c h (newExpiry now)
          pure uid

----------------------------------------------------------------------
-- Session issuance (shared by Register and Login)
--
-- Sets the session cookie only; the caller writes the JSON response
-- body (and Snap defaults to 200 OK).

setSessionCookie :: AuthEnv -> Int64 -> Snap ()
setSessionCookie env uid = do
  tok <- liftIO generateToken
  now <- liftIO getCurrentTime
  let expiresAt = newExpiry now
      h         = hashToken (encodeUtf8 tok)
  liftIO $ withConn (aePool env) $ \c ->
    createSession c uid h expiresAt
  modifyResponse $ addHeader "Set-Cookie"
    (issueCookieHeader (aeCookieSecure env) tok)

----------------------------------------------------------------------
-- User lookup (shared by Login, Register, Me)

loadUserResponse :: DbPool -> Int64 -> IO (Maybe UserResponse)
loadUserResponse pool uid = withConn pool $ \c -> do
  rows <- query c
    "SELECT id, username, locale, timezone FROM users WHERE id = ?"
    (Only uid)
    :: IO [(Int64, Text, Text, Text)]
  pure $ case rows of
    [(i, u, l, t)] -> case localeFromText l of
      Just loc -> Just (UserResponse i u loc t)
      Nothing  -> Nothing
    _ -> Nothing

----------------------------------------------------------------------
-- Snap helpers

parseJsonBody :: Aeson.FromJSON a => Snap (Maybe a)
parseJsonBody = do
  raw <- readRequestBody (64 * 1024)
  pure (Aeson.decode raw)

writeJson :: Aeson.ToJSON a => a -> Snap ()
writeJson v = do
  modifyResponse $ setHeader "Content-Type" "application/json"
  writeLBS (Aeson.encode v)

errorStatus :: Int -> ByteString -> Snap a
errorStatus code msg = do
  modifyResponse $ setResponseStatus code msg
  getResponse >>= finishWith

unauthorized :: Snap a
unauthorized = errorStatus 401 "Unauthorized"
