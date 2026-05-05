{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

module Backend.Auth.Register
  ( handler
  ) where

import Backend.App (App, runBeamApp, throwApp)
import Backend.Auth (generateToken, hashToken, loadUserResponse, newExpiry)
import Backend.Auth.Cookie (issueCookieHeaderText)
import Backend.Auth.Session (createSession)
import Backend.Db (Pg, runBeam)
import Backend.Env (envCookieSecure, envPool)
import Backend.RateLimit.Combinator (RateBucket)
import Backend.Schema.Db (LucianaDb (..), lucianaDb)
import Backend.Schema.User (PrimaryKey (UserId), TZName (TZName), UserT (..))
import Common.Auth
  ( RegisterRequest (rrLocale, rrPassword, rrTimezone, rrUsername)
  , RegisterResult (RegisterOk, UsernameTaken)
  , Username
  , unPassword
  , unUsername
  )
import Common.I18n (Locale)
import qualified Crypto.BCrypt as BCrypt (hashPassword)
import qualified Crypto.Random.Entropy as Entropy (getEntropy)
import Data.Time (getCurrentTime)
import Database.Beam (Table (primaryKey), default_, insertExpressions, val_)
import Database.Beam.Postgres ()
import Database.Beam.Postgres.Full (anyConflict, insertOnConflict, onConflictDoNothing, runPgInsertReturningList, returning)
import Database.Beam.Backend.SQL.Types (SqlSerial (..))
import Relude
import Servant.API (Header, Headers, addHeader, noHeader)
import Servant.Server (err500)

handler
  :: RateBucket
  -> RegisterRequest
  -> App (Headers '[Header "Set-Cookie" Text] RegisterResult)
handler _bucket req = do
  pool   <- asks envPool
  secure <- asks envCookieSecure
  let username = rrUsername req
      pw       = unPassword (rrPassword req)
      loc      = rrLocale req
      tz       = rrTimezone req

  mHashed <- liftIO $ hashPassword pw
  case mHashed of
    Nothing -> throwApp err500
    Just hashed -> do
      mUid <- liftIO $ runBeam pool $ insertUser username hashed loc tz
      case mUid of
        Nothing -> pure (noHeader UsernameTaken)
        Just uid -> do
          tok <- liftIO generateToken
          now <- liftIO getCurrentTime
          let h = hashToken (encodeUtf8 tok)
          runBeamApp $ createSession uid h (newExpiry now)
          mUr <- runBeamApp $ loadUserResponse uid
          case mUr of
            Just ur -> pure $ addHeader (issueCookieHeaderText secure tok) (RegisterOk ur)
            Nothing -> throwApp err500

hashPassword :: Text -> IO (Maybe Text)
hashPassword pw = do
  salt <- Entropy.getEntropy 16
  let m = BCrypt.hashPassword (encodeUtf8 pw) salt
  pure (decodeUtf8 <$> m)


insertUser :: Username -> Text -> Locale -> Text -> Pg (Maybe Int64)
insertUser username hashed loc tz = do
  now <- liftIO getCurrentTime
  mU <- runPgInsertReturningList $
    insertOnConflict (_users lucianaDb) (insertExpressions
      [ User
          { userId           = default_
          , userUsername     = val_ (unUsername username)
          , userPasswordHash = val_ hashed
          , userLocale       = val_ loc
          , userTimezone     = val_ (TZName tz)
          , userCreatedAt    = val_ now
          }
      ]) anyConflict onConflictDoNothing
    `returning` id
  case mU of
    [u] -> let UserId (SqlSerial uid) = primaryKey u in pure (Just uid)
    []  -> pure Nothing
    _   -> error "INSERT users ON CONFLICT DO NOTHING RETURNING produced more than 1 row"
