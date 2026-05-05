{-# LANGUAGE DataKinds #-}

module Backend.Auth.Logout
  ( handler
  ) where

import Backend.App (App, runBeamApp)
import Backend.Auth (hashToken)
import Backend.Auth.Combinator (UserId)
import Backend.Auth.Cookie (clearCookieHeaderText, readCookieToken)
import Backend.Auth.Session (deleteSession)
import Backend.Env (envCookieSecure)
import Relude
import Servant.API (Header, Headers, NoContent (NoContent), addHeader)

handler :: UserId -> App (Headers '[Header "Set-Cookie" Text] NoContent)
handler _uid = do
  secure <- asks envCookieSecure
  mTok   <- lift readCookieToken
  forM_ mTok $ \raw ->
    runBeamApp $ deleteSession (hashToken raw)
  pure (addHeader (clearCookieHeaderText secure) NoContent)
