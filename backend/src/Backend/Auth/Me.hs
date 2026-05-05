module Backend.Auth.Me
  ( handler
  ) where

import Backend.App (App, runBeamApp, throwApp)
import Backend.Auth (loadUserResponse)
import Backend.Auth.Combinator (UserId)
import Common.Auth (UserResponse)
import Relude
import Servant.Server (err401)

handler :: UserId -> App UserResponse
handler uid = do
  mUser <- runBeamApp (loadUserResponse uid)
  maybe (throwApp err401) pure mUser
