{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -fno-warn-orphans #-}

-- | @HasServer@ instance for the 'AuthRequired' combinator and the
-- session-cookie auth handler that the @servant@ context dispatches to.
module Backend.Auth.Combinator
  ( UserId
  , sessionAuthHandler
  ) where

import Backend.Auth
  ( hashToken
  , newExpiry
  , shouldBump
  )
import Backend.Auth.Cookie (readCookieToken)
import Backend.Auth.Session (bumpSession, lookupSession)
import Backend.Db (runBeam)
import Backend.Env (Env, envPool)
import Common.Api (AuthRequired)
import Data.Time (getCurrentTime)
import Relude
import Servant.API ((:>))
import Servant.Server
  ( HasContextEntry
  , HasServer
  , ServantErr
  , ServerT
  , err401
  , getContextEntry
  , hoistServerWithContext
  , route
  )
import Servant.Server.Internal
  ( DelayedM
  , addAuthCheck
  , delayedFailFatal
  , withRequest
  )
import Snap.Core (Snap)
import Snap.Internal.Core (evalSnap)

-- | Database id of the authenticated user. Plain alias for 'Int64' so
-- the combinator's injected argument has a name in handler signatures.
type UserId = Int64

-- | Snap action stored in the servant 'Context'. It reads the session
-- cookie, hashes it, looks up the session row, optionally bumps the
-- expiry, and yields either a @401@ 'ServantErr' or the 'UserId'.
type ContextAuth = Snap (Either ServantErr UserId)

instance ( HasServer api context m
         , HasContextEntry context ContextAuth
         )
      => HasServer (AuthRequired tag :> api) context m where

  type ServerT (AuthRequired tag :> api) context m =
    UserId -> ServerT api context m

  hoistServerWithContext _ pc nt s =
    hoistServerWithContext (Proxy :: Proxy api) pc nt . s

  route _ ctx subserver = route
    (Proxy :: Proxy api)
    ctx
    (addAuthCheck subserver $
       either delayedFailFatal pure =<< authCheck (getContextEntry ctx))

authCheck :: MonadIO m => ContextAuth -> DelayedM m (Either ServantErr UserId)
authCheck snapAct = withRequest $ \req -> liftIO $
  evalSnap snapAct (\_ -> pass) (\_ -> pass) req

-- | Build the auth-handler 'Snap' action that 'sessionAuthHandler' adds
-- to the servant 'Context'. Carries the 'Env' so the action can hit
-- the DB pool and rate limiter.
sessionAuthHandler :: Env -> ContextAuth
sessionAuthHandler env = do
  mTok <- readCookieToken
  case mTok of
    Nothing  -> pure (Left err401)
    Just raw -> do
      let h = hashToken raw
          pool = envPool env
      mFound <- liftIO $ runBeam pool $ lookupSession h
      case mFound of
        Nothing -> pure (Left err401)
        Just (uid, expiresAt) -> do
          now <- liftIO getCurrentTime
          when (shouldBump now expiresAt) $
            liftIO $ runBeam pool $ bumpSession h (newExpiry now)
          pure (Right uid)
