{-# LANGUAGE TypeApplications #-}

module Backend.Push
  ( handlers
  ) where

import Backend.App (App, AppContext, runBeamApp)
import Backend.Auth.Combinator ()
import Backend.RateLimit.Combinator ()
import Backend.Schema.Db (LucianaDb (..), lucianaDb)
import Backend.Schema.PushSubscription
  ( PushSubscriptionT (..)
  )
import Backend.Schema.User (PrimaryKey (UserId))
import Common.Api (RoutesPush)
import Common.Push
  ( PushSubscribeRequest (..)
  , PushUnsubscribeRequest (..)
  )
import Data.Time (getCurrentTime)
import Database.Beam
  ( (&&.)
  , (==.)
  , (<-.)
  , default_
  , delete
  , insertExpressions
  , runDelete
  , runInsert
  , val_
  )
import Database.Beam.Postgres ()
import Database.Beam.Postgres.Full (insertOnConflict, onConflictUpdateSet, conflictingFields)
import Database.Beam.Backend.SQL.Types (SqlSerial (..))
import Relude
import Servant (NoContent (..), ServerT, (:<|>) ((:<|>)))

handlers :: ServerT RoutesPush AppContext App
handlers = subscribe :<|> unsubscribe

subscribe :: Int64 -> PushSubscribeRequest -> App NoContent
subscribe uid req = do
  now <- liftIO getCurrentTime
  _ <- runBeamApp $ runInsert $ insertOnConflict (_pushSubscriptions lucianaDb)
    (insertExpressions
      [ PushSubscription
          { pushSubscriptionId         = default_
          , pushSubscriptionUserId     = UserId (val_ (SqlSerial uid))
          , pushSubscriptionEndpoint   = val_ (psrqEndpoint req)
          , pushSubscriptionP256dh     = val_ (psrqP256dh req)
          , pushSubscriptionAuth       = val_ (psrqAuth req)
          , pushSubscriptionUserAgent  = val_ (psrqUserAgent req)
          , pushSubscriptionCreatedAt  = val_ now
          , pushSubscriptionLastUsedAt = val_ Nothing
          }
      ])
    (conflictingFields pushSubscriptionEndpoint)
    (onConflictUpdateSet $ \e _ -> mconcat
        [ pushSubscriptionUserId e     <-. UserId (val_ (SqlSerial uid))
        , pushSubscriptionP256dh e     <-. val_ (psrqP256dh req)
        , pushSubscriptionAuth e       <-. val_ (psrqAuth req)
        , pushSubscriptionUserAgent e  <-. val_ (psrqUserAgent req)
        ]
      )
  pure NoContent

unsubscribe :: Int64 -> PushUnsubscribeRequest -> App NoContent
unsubscribe uid req = do
  runBeamApp $ runDelete $ delete (_pushSubscriptions lucianaDb) $ \s ->
    pushSubscriptionUserId s ==. UserId (val_ (SqlSerial uid)) &&.
    pushSubscriptionEndpoint s ==. val_ (purqEndpoint req)
  pure NoContent
