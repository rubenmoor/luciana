module Backend.Auth.RateLimit
  ( RateLimiter
  , newRateLimiter
  , checkAndConsume
  , reset
  ) where

import Control.Concurrent.MVar (modifyMVar, modifyMVar_)
import qualified Data.HashMap.Strict as HM
import Data.Time (UTCTime, addUTCTime, getCurrentTime)
import Relude

data Bucket = Bucket
  { bCount       :: Int
  , bWindowStart :: UTCTime
  }

newtype RateLimiter
  = RateLimiter (MVar (HashMap (Text, Text) Bucket))

newRateLimiter :: IO RateLimiter
newRateLimiter = RateLimiter <$> newMVar HM.empty

windowSeconds :: Int
windowSeconds = 15 * 60

maxAttempts :: Int
maxAttempts = 5

-- | Returns 'True' if the request is within the limit, 'False' if rate-limited.
-- Each call counts as one attempt against the bucket.
checkAndConsume :: RateLimiter -> (Text, Text) -> IO Bool
checkAndConsume (RateLimiter mv) k = do
  now <- getCurrentTime
  modifyMVar mv $ \m -> do
    let bucket = case HM.lookup k m of
          Just b
            | addUTCTime (fromIntegral windowSeconds) (bWindowStart b) > now ->
                b { bCount = bCount b + 1 }
            | otherwise ->
                Bucket 1 now
          Nothing -> Bucket 1 now
        allowed = bCount bucket <= maxAttempts
    pure (HM.insert k bucket m, allowed)

reset :: RateLimiter -> (Text, Text) -> IO ()
reset (RateLimiter mv) k = modifyMVar_ mv (pure . HM.delete k)
