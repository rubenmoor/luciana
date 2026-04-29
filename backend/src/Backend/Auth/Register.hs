-- | TypeApplications: typed `try` for the unique-violation catch.
{-# LANGUAGE TypeApplications #-}

module Backend.Auth.Register
  ( handler
  ) where

import Backend.Auth
  ( AuthEnv
  , aePool
  , aeRateLimiter
  , errorStatus
  , loadUserResponse
  , parseJsonBody
  , setSessionCookie
  , writeJson
  )
import Backend.Auth.RateLimit (checkAndConsume)
import Backend.Db (withConn)
import Common.Auth
  ( RegisterRequest (rrLocale, rrPassword, rrTimezone, rrUsername)
  , RegisterResult (RegisterOk, UsernameTaken)
  , Username
  , unPassword
  , unUsername
  )
import Common.I18n (Locale, localeToText)
import Control.Exception (try)
import qualified Crypto.BCrypt as BCrypt
import Database.PostgreSQL.Simple
  ( Connection
  , Only (Only)
  , SqlError
  , query
  , sqlState
  )
import Relude
import Snap.Core
  ( Method (POST)
  , Snap
  , getsRequest
  , method
  , rqClientAddr
  )

handler :: AuthEnv -> Snap ()
handler env = method POST $ do
  ip     <- getsRequest (decodeUtf8 . rqClientAddr)
  rateOk <- liftIO $ checkAndConsume (aeRateLimiter env) (ip, "register")
  if not rateOk
    then errorStatus 429 "Too Many Requests"
    else do
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
            insertUser c (rrUsername req) hashed (rrLocale req) (rrTimezone req)
      result <- liftIO (try @SqlError act)
      case result of
        Left e
          | sqlState e == "23505" -> writeJson UsernameTaken
          | otherwise             -> errorStatus 500 "Internal Server Error"
        Right uid -> do
          setSessionCookie env uid
          mUr <- liftIO $ loadUserResponse (aePool env) uid
          case mUr of
            Just ur -> writeJson (RegisterOk ur)
            Nothing -> errorStatus 500 "Internal Server Error"

hashPassword :: Text -> IO (Maybe Text)
hashPassword pw = do
  m <- BCrypt.hashPasswordUsingPolicy
         BCrypt.slowerBcryptHashingPolicy { BCrypt.preferredHashCost = 12 }
         (encodeUtf8 pw)
  pure (decodeUtf8 <$> m)

insertUser :: Connection -> Username -> Text -> Locale -> Text -> IO Int64
insertUser conn username hashed loc tz = do
  rows <- query conn
    "INSERT INTO users (username, password_hash, locale, timezone) \
    \VALUES (?, ?, ?, ?) RETURNING id"
    (unUsername username, hashed, localeToText loc, tz)
    :: IO [Only Int64]
  case rows of
    [Only uid] -> pure uid
    _          -> error "INSERT users RETURNING id produced no row"
