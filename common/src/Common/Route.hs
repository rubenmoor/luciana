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
  , FrontendRoute (..)
  , fullRouteEncoder
  ) where

import qualified Control.Category as Cat
import Obelisk.Route
  ( Encoder
  , FullRoute (FullRoute_Backend)
  , PageName
  , R
  , SegmentResult (PathEnd, PathSegment)
  , mkFullRouteEncoder
  , pattern (:/)
  , unitEncoder
  )
import Obelisk.Route.TH (deriveRouteComponent)
import Relude

data BackendRoute :: Type -> Type where
  BackendRoute_Missing :: BackendRoute ()
  -- | Catch-all for the JSON API. The 'PageName' carries the path
  -- segments + query string after @/api/@; servant parses them via
  -- the 'Common.Api.RoutesApi' type at handler dispatch time.
  BackendRoute_Api     :: BackendRoute PageName
  BackendRoute_Vapid   :: BackendRoute ()

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
      BackendRoute_Api     -> PathSegment "api" Cat.id
      BackendRoute_Vapid   -> PathSegment "vapid-public-key" $ unitEncoder mempty

    frontendSegment :: FrontendRoute a -> SegmentResult (Either Text) (Either Text) a
    frontendSegment = \case
      FrontendRoute_Home     -> PathEnd $ unitEncoder mempty
      FrontendRoute_Calendar -> PathSegment "calendar" $ unitEncoder mempty
      FrontendRoute_History  -> PathSegment "history" $ unitEncoder mempty
      FrontendRoute_Settings -> PathSegment "settings" $ unitEncoder mempty
      FrontendRoute_Login    -> PathSegment "login" $ unitEncoder mempty
      FrontendRoute_Signup   -> PathSegment "signup" $ unitEncoder mempty

concat <$> mapM deriveRouteComponent
  [ ''BackendRoute
  , ''FrontendRoute
  ]
