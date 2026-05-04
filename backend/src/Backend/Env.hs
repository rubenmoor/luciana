module Backend.Env
  ( Env (..)
  , mkEnv
  ) where

import Backend.Auth.RateLimit (RateLimiter, newRateLimiter)
import Backend.Db (DbPool)
import Relude

data Env = Env
  { envPool         :: DbPool
  , envRateLimiter  :: RateLimiter
  , envCookieSecure :: Bool
  }

mkEnv :: DbPool -> IO Env
mkEnv pool = Env pool <$> newRateLimiter <*> readSecureFlag

-- | Cookie 'Secure' flag. Defaults to insecure (dev). Production deploys must
-- export @LUCIANA_COOKIE_SECURE=true@.
readSecureFlag :: IO Bool
readSecureFlag = do
  v <- lookupEnv "LUCIANA_COOKIE_SECURE"
  pure (v == Just "true")
