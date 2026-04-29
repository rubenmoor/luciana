module Backend.Auth.Login
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
import Backend.Auth.RateLimit (checkAndConsume, reset)
import Backend.Db (withConn)
import Common.Auth
  ( LoginRequest (lrPassword, lrUsername)
  , LoginResult (InvalidCredentials, LoginOk)
  , Username
  , unPassword
  , unUsername
  )
import qualified Crypto.BCrypt as BCrypt
import qualified Data.Text as T
import Database.PostgreSQL.Simple (Connection, Only (Only), query)
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
  ip   <- getsRequest (decodeUtf8 . rqClientAddr)
  mReq <- parseJsonBody
  case mReq of
    Nothing  -> errorStatus 400 "Bad Request"
    Just req -> do
      let key = (ip, T.toLower (unUsername (lrUsername req)))
      rateOk <- liftIO $ checkAndConsume (aeRateLimiter env) key
      if not rateOk
        then errorStatus 429 "Too Many Requests"
        else do
          mAuth <- liftIO $ withConn (aePool env) $ \c ->
            lookupUserForLogin c (lrUsername req)
          case mAuth of
            Just (uid, hashed)
              | verifyPassword (unPassword (lrPassword req)) hashed -> do
                  liftIO $ reset (aeRateLimiter env) key
                  setSessionCookie env uid
                  mUr <- liftIO $ loadUserResponse (aePool env) uid
                  case mUr of
                    Just ur -> writeJson (LoginOk ur)
                    Nothing -> errorStatus 500 "Internal Server Error"
            _ -> writeJson InvalidCredentials

verifyPassword :: Text -> Text -> Bool
verifyPassword pw hashed =
  BCrypt.validatePassword (encodeUtf8 hashed) (encodeUtf8 pw)

-- | Case-insensitive lookup matches the unique index on @lower(username)@.
lookupUserForLogin :: Connection -> Username -> IO (Maybe (Int64, Text))
lookupUserForLogin conn username = do
  rows <- query conn
    "SELECT id, password_hash FROM users WHERE lower(username) = lower(?)"
    (Only (unUsername username))
    :: IO [(Int64, Text)]
  pure $ case rows of
    [(uid, h)] -> Just (uid, h)
    _          -> Nothing
