{-# LANGUAGE DataKinds #-}

module Backend.Auth.Login
  ( handler
  ) where

import Backend.App (App, runBeamApp, throwApp)
import Backend.Auth (generateToken, hashToken, loadUserResponse, newExpiry)
import Backend.Auth.Cookie (issueCookieHeaderText)
import Backend.Auth.Session (createSession)
import Backend.Db (Pg)
import Backend.Env (envCookieSecure)
import Backend.RateLimit.Combinator (RateBucket, clearBucket)
import Backend.Schema.Db (LucianaDb (..), lucianaDb)
import Backend.Schema.User (PrimaryKey (UserId), UserT (..))
import Common.Auth
  ( LoginRequest (lrPassword, lrUsername)
  , LoginResult (InvalidCredentials, LoginOk)
  , Username
  , unPassword
  , unUsername
  )
import qualified Crypto.BCrypt as BCrypt (validatePassword)
import Data.Time (getCurrentTime)
import Database.Beam
  ( Table (primaryKey)
  , (==.)
  , all_
  , guard_
  , lower_
  , runSelectReturningOne
  , select
  , val_
  )
import Database.Beam.Backend.SQL.Types (SqlSerial (..))
import Relude
import Servant.API (Header, Headers, addHeader, noHeader)
import Servant.Server (err500)

handler
  :: RateBucket
  -> LoginRequest
  -> App (Headers '[Header "Set-Cookie" Text] LoginResult)
handler bucket req = do
  secure <- asks envCookieSecure
  mAuth  <- runBeamApp $ lookupUserForLogin (lrUsername req)
  case mAuth of
    Just (uid, hashed)
      | verifyPassword (unPassword (lrPassword req)) hashed -> do
          clearBucket bucket
          tok <- liftIO generateToken
          now <- liftIO getCurrentTime
          let h = hashToken (encodeUtf8 tok)
          runBeamApp $ createSession uid h (newExpiry now)
          mUr <- runBeamApp $ loadUserResponse uid
          case mUr of
            Just ur -> pure $ addHeader (issueCookieHeaderText secure tok)
                                        (LoginOk ur)
            Nothing -> throwApp err500
    _ -> pure (noHeader InvalidCredentials)

verifyPassword :: Text -> Text -> Bool
verifyPassword pw hashed =
  BCrypt.validatePassword (encodeUtf8 hashed) (encodeUtf8 pw)

-- | Case-insensitive lookup matches the unique index on @lower(username)@.
lookupUserForLogin :: Username -> Pg (Maybe (Int64, Text))
lookupUserForLogin username = do
  mUser <- runSelectReturningOne $ select $ do
    u <- all_ (_users lucianaDb)
    guard_ (lower_ (userUsername u) ==. lower_ (val_ (unUsername username)))
    pure u
  pure $ (\u ->
    let UserId (SqlSerial uid) = primaryKey u
    in (uid, userPasswordHash u)) <$> mUser
