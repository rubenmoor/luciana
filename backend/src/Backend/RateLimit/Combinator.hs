{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -fno-warn-orphans #-}

-- | @HasServer@ instance for the 'RateLimit' combinator.
--
-- The combinator reads the client IP from the current request, checks
-- the rate limiter against @(ip, bucket)@, and either short-circuits
-- with @429@ or injects a 'RateBucket' value into the handler. Login
-- uses the bucket to call 'clearBucket' on success.
module Backend.RateLimit.Combinator
  ( RateBucket (..)
  , clearBucket
  ) where

import Backend.Auth.RateLimit (RateLimiter, checkAndConsume, reset)
import Common.Api (RateLimit)
import qualified Data.Text as T (pack)
import GHC.TypeLits (KnownSymbol, Symbol, symbolVal)
import Relude
import Servant.API ((:>))
import Servant.Server
  ( HasContextEntry
  , HasServer
  , ServantErr (..)
  , ServerT
  , getContextEntry
  , hoistServerWithContext
  , route
  )
import Servant.Server.Internal
  ( addAuthCheck
  , delayedFailFatal
  , withRequest
  )
import Snap.Core (Request, rqClientAddr)

-- | Token handed to the handler so it can clear its own rate-limit
-- bucket on success (login) without re-spelling the bucket key.
data RateBucket = RateBucket
  { rbKey     :: (Text, Text)
  , rbLimiter :: RateLimiter
  }

clearBucket :: MonadIO m => RateBucket -> m ()
clearBucket (RateBucket k l) = liftIO (reset l k)

instance ( KnownSymbol bucket
         , HasServer api context m
         , HasContextEntry context RateLimiter
         )
      => HasServer (RateLimit bucket :> api) context m where

  type ServerT (RateLimit bucket :> api) context m =
    RateBucket -> ServerT api context m

  hoistServerWithContext _ pc nt s =
    \rb -> hoistServerWithContext (Proxy :: Proxy api) pc nt (s rb)

  route _ ctx subserver = route
    (Proxy :: Proxy api)
    ctx
    (addAuthCheck subserver $
       withRequest $ \req -> do
         let limiter = getContextEntry ctx :: RateLimiter
             key     = bucketKey (Proxy :: Proxy bucket) req
         ok <- liftIO (checkAndConsume limiter key)
         if ok
           then pure (RateBucket key limiter)
           else delayedFailFatal err429)

bucketKey :: forall (b :: Symbol). KnownSymbol b => Proxy b -> Request -> (Text, Text)
bucketKey p req =
  ( decodeUtf8 (rqClientAddr req)
  , T.pack (symbolVal p)
  )

-- | servant-snap doesn't ship a ready-made 'ServantErr' for status 429.
err429 :: ServantErr
err429 = ServantErr
  { errHTTPCode     = 429
  , errReasonPhrase = "Too Many Requests"
  , errBody         = ""
  , errHeaders      = []
  }
