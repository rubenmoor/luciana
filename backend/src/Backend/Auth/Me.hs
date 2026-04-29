module Backend.Auth.Me
  ( handler
  ) where

import Backend.Auth
  ( AuthEnv
  , aePool
  , errorStatus
  , loadUserResponse
  , requireUser
  , writeJson
  )
import Relude
import Snap.Core (Method (GET), Snap, method)

handler :: AuthEnv -> Snap ()
handler env = method GET $ do
  uid   <- requireUser env
  mUser <- liftIO $ loadUserResponse (aePool env) uid
  case mUser of
    Nothing -> errorStatus 401 "Unauthorized"
    Just ur -> writeJson ur
