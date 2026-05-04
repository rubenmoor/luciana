module Backend.Auth.Me
  ( handler
  ) where

import Backend.App (App, throwApp)
import Backend.Auth (loadUserResponse)
import Backend.Auth.Combinator (UserId)
import Backend.Env (envPool)
import Common.Auth (UserResponse)
import Relude
import Servant.Server (err401)

handler :: UserId -> App UserResponse
handler uid = do
  pool  <- asks envPool
  mUser <- liftIO (loadUserResponse pool uid)
  maybe (throwApp err401) pure mUser
