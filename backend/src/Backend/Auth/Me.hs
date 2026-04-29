module Backend.Auth.Me
  ( handler
  ) where

import Backend.Auth (AuthEnv, aePool, errorStatus, requireUser, writeJson)
import Backend.Db (withConn)
import Common.Auth (UserResponse (UserResponse))
import Common.I18n (localeFromText)
import Database.PostgreSQL.Simple (Connection, Only (Only), query)
import Relude
import Snap.Core (Method (GET), Snap, method)

handler :: AuthEnv -> Snap ()
handler env = method GET $ do
  uid   <- requireUser env
  mUser <- liftIO $ withConn (aePool env) $ \c -> lookupUser c uid
  case mUser of
    Nothing -> errorStatus 401 "Unauthorized"
    Just ur -> writeJson ur

lookupUser :: Connection -> Int64 -> IO (Maybe UserResponse)
lookupUser conn uid = do
  rows <- query conn
    "SELECT id, username, locale, timezone FROM users WHERE id = ?"
    (Only uid)
    :: IO [(Int64, Text, Text, Text)]
  pure $ case rows of
    [(i, u, l, t)] -> case localeFromText l of
      Just loc -> Just (UserResponse i u loc t)
      Nothing  -> Nothing
    _ -> Nothing
