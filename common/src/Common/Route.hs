{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE UndecidableInstances #-}

module Common.Route
  ( BackendRoute (..)
  , ApiRoute (..)
  , AuthRoute (..)
  , PeriodRoute (..)
  , NotificationsRoute (..)
  , PushRoute (..)
  , FrontendRoute (..)
  , PeriodEntryId (..)
  , fullRouteEncoder
  ) where

import Control.Monad.Except (MonadError)
import Obelisk.Route
  ( Encoder
  , FullRoute (FullRoute_Backend)
  , PageName
  , R
  , SegmentResult (PathEnd, PathSegment)
  , mkFullRouteEncoder
  , pathComponentEncoder
  , pathParamEncoder
  , pattern (:/)
  , unitEncoder
  , unsafeTshowEncoder
  )
import Obelisk.Route.TH (deriveRouteComponent)
import Relude

newtype PeriodEntryId = PeriodEntryId { unPeriodEntryId :: Int64 }
  deriving stock (Eq, Ord)
  deriving newtype (Show, Read)

data BackendRoute :: Type -> Type where
  BackendRoute_Missing :: BackendRoute ()
  BackendRoute_Api     :: BackendRoute (R ApiRoute)
  BackendRoute_Vapid   :: BackendRoute ()

data ApiRoute :: Type -> Type where
  ApiRoute_Auth          :: ApiRoute (R AuthRoute)
  ApiRoute_Period        :: ApiRoute (R PeriodRoute)
  ApiRoute_Notifications :: ApiRoute (R NotificationsRoute)
  ApiRoute_Push          :: ApiRoute (R PushRoute)

data AuthRoute :: Type -> Type where
  AuthRoute_Register :: AuthRoute ()
  AuthRoute_Login    :: AuthRoute ()
  AuthRoute_Logout   :: AuthRoute ()
  AuthRoute_Me       :: AuthRoute ()

data PeriodRoute :: Type -> Type where
  PeriodRoute_Status  :: PeriodRoute ()
  PeriodRoute_Entries :: PeriodRoute ()
  PeriodRoute_Entry   :: PeriodRoute (PeriodEntryId, ())

data NotificationsRoute :: Type -> Type where
  NotificationsRoute_Prefs :: NotificationsRoute ()

data PushRoute :: Type -> Type where
  PushRoute_Subscribe   :: PushRoute ()
  PushRoute_Unsubscribe :: PushRoute ()

data FrontendRoute :: Type -> Type where
  FrontendRoute_Home     :: FrontendRoute ()
  FrontendRoute_Calendar :: FrontendRoute ()
  FrontendRoute_History  :: FrontendRoute ()
  FrontendRoute_Settings :: FrontendRoute ()
  FrontendRoute_Login    :: FrontendRoute ()
  FrontendRoute_Signup   :: FrontendRoute ()

fullRouteEncoder
  :: Encoder (Either Text) Identity (R (FullRoute BackendRoute FrontendRoute)) PageName
fullRouteEncoder = mkFullRouteEncoder
  (FullRoute_Backend BackendRoute_Missing :/ ())
  backendSegment
  frontendSegment
  where
    backendSegment :: BackendRoute a -> SegmentResult (Either Text) (Either Text) a
    backendSegment = \case
      BackendRoute_Missing -> PathSegment "missing" $ unitEncoder mempty
      BackendRoute_Api     -> PathSegment "api" apiRouteEncoder
      BackendRoute_Vapid   -> PathSegment "vapid-public-key" $ unitEncoder mempty

    frontendSegment :: FrontendRoute a -> SegmentResult (Either Text) (Either Text) a
    frontendSegment = \case
      FrontendRoute_Home     -> PathEnd $ unitEncoder mempty
      FrontendRoute_Calendar -> PathSegment "calendar" $ unitEncoder mempty
      FrontendRoute_History  -> PathSegment "history" $ unitEncoder mempty
      FrontendRoute_Settings -> PathSegment "settings" $ unitEncoder mempty
      FrontendRoute_Login    -> PathSegment "login" $ unitEncoder mempty
      FrontendRoute_Signup   -> PathSegment "signup" $ unitEncoder mempty

apiRouteEncoder
  :: (MonadError Text check, MonadError Text parse)
  => Encoder check parse (R ApiRoute) PageName
apiRouteEncoder = pathComponentEncoder $ \case
  ApiRoute_Auth          -> PathSegment "auth"          authRouteEncoder
  ApiRoute_Period        -> PathSegment "period"        periodRouteEncoder
  ApiRoute_Notifications -> PathSegment "notifications" notificationsRouteEncoder
  ApiRoute_Push          -> PathSegment "push"          pushRouteEncoder

authRouteEncoder
  :: (MonadError Text check, MonadError Text parse)
  => Encoder check parse (R AuthRoute) PageName
authRouteEncoder = pathComponentEncoder $ \case
  AuthRoute_Register -> PathSegment "register" $ unitEncoder mempty
  AuthRoute_Login    -> PathSegment "login"    $ unitEncoder mempty
  AuthRoute_Logout   -> PathSegment "logout"   $ unitEncoder mempty
  AuthRoute_Me       -> PathSegment "me"       $ unitEncoder mempty

periodRouteEncoder
  :: (MonadError Text check, MonadError Text parse)
  => Encoder check parse (R PeriodRoute) PageName
periodRouteEncoder = pathComponentEncoder $ \case
  PeriodRoute_Status  -> PathSegment "status"  $ unitEncoder mempty
  PeriodRoute_Entries -> PathSegment "entries" $ unitEncoder mempty
  PeriodRoute_Entry   -> PathSegment "entry"   $
    pathParamEncoder unsafeTshowEncoder (unitEncoder mempty)

notificationsRouteEncoder
  :: (MonadError Text check, MonadError Text parse)
  => Encoder check parse (R NotificationsRoute) PageName
notificationsRouteEncoder = pathComponentEncoder $ \case
  NotificationsRoute_Prefs -> PathSegment "prefs" $ unitEncoder mempty

pushRouteEncoder
  :: (MonadError Text check, MonadError Text parse)
  => Encoder check parse (R PushRoute) PageName
pushRouteEncoder = pathComponentEncoder $ \case
  PushRoute_Subscribe   -> PathSegment "subscribe"   $ unitEncoder mempty
  PushRoute_Unsubscribe -> PathSegment "unsubscribe" $ unitEncoder mempty

concat <$> mapM deriveRouteComponent
  [ ''BackendRoute
  , ''ApiRoute
  , ''AuthRoute
  , ''PeriodRoute
  , ''NotificationsRoute
  , ''PushRoute
  , ''FrontendRoute
  ]
