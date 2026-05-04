{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

module Backend.Auth.Register
  ( handler
  ) where

import Backend.App (App, throwApp)
import Backend.Auth (generateToken, hashToken, loadUserResponse, newExpiry)
import Backend.Auth.Cookie (issueCookieHeaderText)
import Backend.Auth.Session (createSession)
import Backend.Db (withConn)
import Backend.Env (envCookieSecure, envPool)
import Backend.RateLimit.Combinator (RateBucket)
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
import Data.Time (getCurrentTime)
import Database.PostgreSQL.Simple
  ( Connection
  , Only (Only)
  , SqlError
  , query
  , sqlState
  )
import Relude
import Servant.API (Header, Headers, addHeader, noHeader)
import Servant.Server (err500)

handler
  :: RateBucket
  -> RegisterRequest
  -> App (Headers '[Header "Set-Cookie" Text] RegisterResult)
handler _bucket req = do
  pool    <- asks envPool
  secure  <- asks envCookieSecure
  mHashed <- liftIO $ hashPassword (unPassword (rrPassword req))
  case mHashed of
    Nothing -> throwApp err500
    Just hashed -> do
      let act = withConn pool $ \c ->
            insertUser c (rrUsername req) hashed (rrLocale req) (rrTimezone req)
      result <- liftIO (try @SqlError act)
      case result of
        Left e
          | sqlState e == "23505" -> pure (noHeader UsernameTaken)
          | otherwise             -> throwApp err500
        Right uid -> do
          tok <- liftIO generateToken
          now <- liftIO getCurrentTime
          let h = hashToken (encodeUtf8 tok)
          liftIO $ withConn pool $ \c -> createSession c uid h (newExpiry now)
          mUr <- liftIO $ loadUserResponse pool uid
          case mUr of
            Just ur -> pure $ addHeader (issueCookieHeaderText secure tok)
                                        (RegisterOk ur)
            Nothing -> throwApp err500

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
