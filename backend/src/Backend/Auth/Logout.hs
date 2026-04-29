module Backend.Auth.Logout
  ( handler
  ) where

import Backend.Auth (AuthEnv, aeCookieSecure, aePool, hashToken)
import Backend.Auth.Cookie (clearCookieHeader, readCookieToken)
import Backend.Auth.Session (deleteSession)
import Backend.Db (withConn)
import Relude
import Snap.Core
  ( Method (POST)
  , Snap
  , addHeader
  , method
  , modifyResponse
  , setResponseStatus
  )

handler :: AuthEnv -> Snap ()
handler env = method POST $ do
  mTok <- readCookieToken
  forM_ mTok $ \raw ->
    liftIO $ withConn (aePool env) $ \c ->
      deleteSession c (hashToken raw)
  modifyResponse $ addHeader "Set-Cookie"
    (clearCookieHeader (aeCookieSecure env))
  modifyResponse $ setResponseStatus 204 "No Content"
