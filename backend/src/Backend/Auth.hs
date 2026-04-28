-- | TypeApplications: typed `try` for the unique-violation catch in register.
-- NumericUnderscores: readable sleep interval literals.
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE TypeApplications #-}

module Backend.Auth
  ( AuthEnv
  , aePool
  , mkAuthEnv
  , forkSessionCleanup
  , requireUser
  , handleRegister
  , handleLogin
  , handleLogout
  , handleMe
  ) where

import Backend.Auth.Cookie
  ( clearCookieHeader
  , issueCookieHeader
  , readCookieToken
  )
import Backend.Auth.RateLimit
  ( RateLimiter
  , checkAndConsume
  , newRateLimiter
  , reset
  )
import Backend.Auth.Session
  ( bumpSession
  , createSession
  , deleteExpiredSessions
  , deleteSession
  , lookupSession
  )
import Backend.Db (DbPool, withConn)
import Common.Auth
  ( Email
  , LoginRequest (lrEmail, lrPassword)
  , RegisterRequest (rrEmail, rrLocale, rrPassword, rrTimezone)
  , UserResponse (UserResponse)
  , unEmail
  , unPassword
  )
import Common.I18n (Locale, localeFromText, localeToText)
import Control.Concurrent (ThreadId, forkIO, threadDelay)
import Control.Exception (try)
import qualified Crypto.BCrypt as BCrypt
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
import Database.PostgreSQL.Simple
  ( Connection
  , Only (Only)
  , SqlError
  , query
  , sqlState
  )
import Relude
import Snap.Core
  ( Method (GET, POST)
  , Snap
  , addHeader
  , finishWith
  , getResponse
  , getsRequest
  , method
  , modifyResponse
  , readRequestBody
  , rqClientAddr
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
-- Password & token helpers

hashPassword :: Text -> IO (Maybe Text)
hashPassword pw = do
  m <- BCrypt.hashPasswordUsingPolicy
         BCrypt.slowerBcryptHashingPolicy { BCrypt.preferredHashCost = 12 }
         (encodeUtf8 pw)
  pure (decodeUtf8 <$> m)

verifyPassword :: Text -> Text -> Bool
verifyPassword pw hashed =
  BCrypt.validatePassword (encodeUtf8 hashed) (encodeUtf8 pw)

generateToken :: IO Text
generateToken = do
  bytes <- Entropy.getEntropy 32 :: IO ByteString
  pure (decodeUtf8 (B64Url.encodeUnpadded bytes))

hashToken :: ByteString -> ByteString
hashToken raw = BA.convert (Hash.hash raw :: Hash.Digest Hash.SHA256)

----------------------------------------------------------------------
-- Session lifetime

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
-- Handlers

handleRegister :: AuthEnv -> Snap ()
handleRegister env = method POST $ do
  ip     <- getsRequest (decodeUtf8 . rqClientAddr)
  rateOk <- liftIO $ checkAndConsume (aeRateLimiter env) (ip, "register")
  unless rateOk $ errorStatus 429 "Too Many Requests"
  mReq <- parseJsonBody
  case mReq of
    Nothing  -> errorStatus 400 "Bad Request"
    Just req -> doRegister env req

doRegister :: AuthEnv -> RegisterRequest -> Snap ()
doRegister env req = do
  mHashed <- liftIO $ hashPassword (unPassword (rrPassword req))
  case mHashed of
    Nothing -> errorStatus 500 "Internal Server Error"
    Just hashed -> do
      let act = withConn (aePool env) $ \c ->
            insertUser c (rrEmail req) hashed (rrLocale req) (rrTimezone req)
      result <- liftIO (try @SqlError act)
      case result of
        Left e
          | sqlState e == "23505" -> errorStatus 409 "Email Taken"
          | otherwise             -> errorStatus 500 "Internal Server Error"
        Right uid -> issueAndSetSession env uid

handleLogin :: AuthEnv -> Snap ()
handleLogin env = method POST $ do
  ip   <- getsRequest (decodeUtf8 . rqClientAddr)
  mReq <- parseJsonBody
  case mReq of
    Nothing  -> errorStatus 400 "Bad Request"
    Just req -> do
      let key = (ip, unEmail (lrEmail req))
      rateOk <- liftIO $ checkAndConsume (aeRateLimiter env) key
      unless rateOk $ errorStatus 429 "Too Many Requests"
      mAuth <- liftIO $ withConn (aePool env) $ \c ->
        lookupUserForLogin c (lrEmail req)
      case mAuth of
        Just (uid, hashed)
          | verifyPassword (unPassword (lrPassword req)) hashed -> do
              liftIO $ reset (aeRateLimiter env) key
              issueAndSetSession env uid
        _ -> errorStatus 401 "Unauthorized"

handleLogout :: AuthEnv -> Snap ()
handleLogout env = method POST $ do
  mTok <- readCookieToken
  forM_ mTok $ \raw ->
    liftIO $ withConn (aePool env) $ \c ->
      deleteSession c (hashToken raw)
  modifyResponse $ addHeader "Set-Cookie"
    (clearCookieHeader (aeCookieSecure env))
  modifyResponse $ setResponseStatus 204 "No Content"

handleMe :: AuthEnv -> Snap ()
handleMe env = method GET $ do
  uid   <- requireUser env
  mUser <- liftIO $ withConn (aePool env) $ \c -> lookupUser c uid
  case mUser of
    Nothing -> errorStatus 401 "Unauthorized"
    Just ur -> writeJson ur

----------------------------------------------------------------------
-- DB queries (postgresql-simple)

insertUser :: Connection -> Email -> Text -> Locale -> Text -> IO Int64
insertUser conn email hashed loc tz = do
  rows <- query conn
    "INSERT INTO users (email, password_hash, locale, timezone) \
    \VALUES (?, ?, ?, ?) RETURNING id"
    (unEmail email, hashed, localeToText loc, tz)
    :: IO [Only Int64]
  case rows of
    [Only uid] -> pure uid
    _          -> error "INSERT users RETURNING id produced no row"

lookupUserForLogin :: Connection -> Email -> IO (Maybe (Int64, Text))
lookupUserForLogin conn email = do
  rows <- query conn
    "SELECT id, password_hash FROM users WHERE email = ?"
    (Only (unEmail email))
    :: IO [(Int64, Text)]
  pure $ case rows of
    [(uid, h)] -> Just (uid, h)
    _          -> Nothing

lookupUser :: Connection -> Int64 -> IO (Maybe UserResponse)
lookupUser conn uid = do
  rows <- query conn
    "SELECT id, email, locale, timezone FROM users WHERE id = ?"
    (Only uid)
    :: IO [(Int64, Text, Text, Text)]
  pure $ case rows of
    [(i, e, l, t)] -> case localeFromText l of
      Just loc -> Just (UserResponse i e loc t)
      Nothing  -> Nothing
    _ -> Nothing

----------------------------------------------------------------------
-- Session issuance

issueAndSetSession :: AuthEnv -> Int64 -> Snap ()
issueAndSetSession env uid = do
  tok <- liftIO generateToken
  now <- liftIO getCurrentTime
  let expiresAt = newExpiry now
      h         = hashToken (encodeUtf8 tok)
  liftIO $ withConn (aePool env) $ \c ->
    createSession c uid h expiresAt
  modifyResponse $ addHeader "Set-Cookie"
    (issueCookieHeader (aeCookieSecure env) tok)
  modifyResponse $ setResponseStatus 204 "No Content"

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
