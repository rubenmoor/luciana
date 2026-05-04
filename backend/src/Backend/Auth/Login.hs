{-# LANGUAGE DataKinds #-}

module Backend.Auth.Login
  ( handler
  ) where

import Backend.App (App, throwApp)
import Backend.Auth (generateToken, hashToken, loadUserResponse, newExpiry)
import Backend.Auth.Cookie (issueCookieHeaderText)
import Backend.Auth.Session (createSession)
import Backend.Db (withConn)
import Backend.Env (envCookieSecure, envPool)
import Backend.RateLimit.Combinator (RateBucket, clearBucket)
import Backend.Schema.Db (lucianaDb)
import Backend.Schema.User (UserT (..))
import Common.Auth
  ( LoginRequest (lrPassword, lrUsername)
  , LoginResult (InvalidCredentials, LoginOk)
  , Username
  , unPassword
  , unUsername
  )
import qualified Crypto.BCrypt as BCrypt
import Data.Time (getCurrentTime)
import Database.Beam
import Database.Beam.Backend.SQL.Types (SqlSerial (..))
import Database.Beam.Postgres (runBeamPostgres)
import Database.PostgreSQL.Simple (Connection)
import Relude
import Servant.API (Header, Headers, addHeader, noHeader)
import Servant.Server (err500)

handler
  :: RateBucket
  -> LoginRequest
  -> App (Headers '[Header "Set-Cookie" Text] LoginResult)
handler bucket req = do
  pool   <- asks envPool
  secure <- asks envCookieSecure
  mAuth  <- liftIO $ withConn pool $ \c -> lookupUserForLogin c (lrUsername req)
  case mAuth of
    Just (uid, hashed)
      | verifyPassword (unPassword (lrPassword req)) hashed -> do
          clearBucket bucket
          tok <- liftIO generateToken
          now <- liftIO getCurrentTime
          let h = hashToken (encodeUtf8 tok)
          liftIO $ withConn pool $ \c -> createSession c uid h (newExpiry now)
          mUr <- liftIO $ loadUserResponse pool uid
          case mUr of
            Just ur -> pure $ addHeader (issueCookieHeaderText secure tok)
                                        (LoginOk ur)
            Nothing -> throwApp err500
    _ -> pure (noHeader InvalidCredentials)

verifyPassword :: Text -> Text -> Bool
verifyPassword pw hashed =
  BCrypt.validatePassword (encodeUtf8 hashed) (encodeUtf8 pw)

-- | Case-insensitive lookup matches the unique index on @lower(username)@.
lookupUserForLogin :: Connection -> Username -> IO (Maybe (Int64, Text))
lookupUserForLogin conn username = do
  mUser <- runBeamPostgres conn $ runSelectReturningOne $ select $ do
    u <- all_ (_users lucianaDb)
    guard_ (lower_ (userUsername u) ==. lower_ (val_ (unUsername username)))
    pure u
  pure $ ffor mUser $ \u ->
    let UserId (SqlSerial uid) = primaryKey u
    in (uid, userPasswordHash u)
