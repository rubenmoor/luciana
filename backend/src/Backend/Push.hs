{-# LANGUAGE TypeApplications #-}

module Backend.Push
  ( handlers
  ) where

import Backend.Api (AppContext)
import Backend.App (App, runBeamApp)
import Backend.Schema.Db (lucianaDb)
import Backend.Schema.PushSubscription
  ( PushSubscriptionT (..)
  )
import Backend.Schema.User (UserId)
import Common.Api (RoutesPush)
import Common.Push
  ( PushSubscribeRequest (..)
  , PushUnsubscribeRequest (..)
  )
import Data.Time (getCurrentTime)
import Database.Beam
import Database.Beam.Postgres (onConflict, onConflictUpdateSet, conflictingFields)
import Relude
import Servant (NoContent (..), ServerT, (:<|>) ((:<|>)))

handlers :: ServerT RoutesPush AppContext App
handlers = subscribe :<|> unsubscribe

subscribe :: UserId -> PushSubscribeRequest -> App NoContent
subscribe uid req = do
  now <- liftIO getCurrentTime
  _ <- runBeamApp $ runInsert $ insert (_pushSubscriptions lucianaDb) $
    insertExpressions
      [ PushSubscription
          { pushSubscriptionId         = default_
          , pushSubscriptionUserId     = val_ uid
          , pushSubscriptionEndpoint   = val_ (psrqEndpoint req)
          , pushSubscriptionP256dh     = val_ (psrqP256dh req)
          , pushSubscriptionAuth       = val_ (psrqAuth req)
          , pushSubscriptionUserAgent  = val_ (psrqUserAgent req)
          , pushSubscriptionCreatedAt  = val_ now
          , pushSubscriptionLastUsedAt = val_ Nothing
          }
      ]
    `onConflict` conflictingFields pushSubscriptionEndpoint
    `onConflictUpdateSet` (\e ->
        [ pushSubscriptionUserId e     <-. val_ uid
        , pushSubscriptionP256dh e     <-. val_ (psrqP256dh req)
        , pushSubscriptionAuth e       <-. val_ (psrqAuth req)
        , pushSubscriptionUserAgent e  <-. val_ (psrqUserAgent req)
        ]
      )
  pure NoContent

unsubscribe :: UserId -> PushUnsubscribeRequest -> App NoContent
unsubscribe uid req = do
  runBeamApp $ runDelete $ delete (_pushSubscriptions lucianaDb) $ \s ->
    pushSubscriptionUserId s ==. val_ uid &&.
    pushSubscriptionEndpoint s ==. val_ (purqEndpoint req)
  pure NoContent
