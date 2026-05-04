{-# LANGUAGE DataKinds #-}

module Backend.Auth.Logout
  ( handler
  ) where

import Backend.App (App)
import Backend.Auth (hashToken)
import Backend.Auth.Combinator (UserId)
import Backend.Auth.Cookie (clearCookieHeaderText, readCookieToken)
import Backend.Auth.Session (deleteSession)
import Backend.Db (withConn)
import Backend.Env (envCookieSecure, envPool)
import Relude
import Servant.API (Header, Headers, NoContent (NoContent), addHeader)

handler :: UserId -> App (Headers '[Header "Set-Cookie" Text] NoContent)
handler _uid = do
  pool   <- asks envPool
  secure <- asks envCookieSecure
  mTok   <- lift readCookieToken
  forM_ mTok $ \raw ->
    liftIO $ withConn pool $ \c -> deleteSession c (hashToken raw)
  pure (addHeader (clearCookieHeaderText secure) NoContent)
