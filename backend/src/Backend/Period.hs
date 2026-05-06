{-# LANGUAGE TypeApplications #-}

module Backend.Period
  ( handlers
  ) where

import Backend.App (App, AppContext, runBeamApp)
import Backend.Auth.Combinator ()
import Backend.RateLimit.Combinator ()
import Backend.Schema.Db (LucianaDb (..), lucianaDb)
import Backend.Schema.PeriodEntry
  ( PeriodEntryId
  , PeriodEntryT (..)
  , PrimaryKey (PeriodEntryId)
  )
import Backend.Schema.User (PrimaryKey (UserId))
import Common.Api (RoutesPeriod)
import Common.Period
  ( CreatePeriodEntryResponse (..)
  , PeriodEntryId (..)
  , PeriodEntryRequest (..)
  , PeriodEntryResponse (..)
  , PeriodPhase (..)
  , PeriodStatusResponse (..)
  )
import Data.Time (Day, getCurrentTime, utctDay)
import Database.Beam
  ( Table (primaryKey)
  , (&&.)
  , (==.)
  , (<.)
  , (<-.)
  , all_
  , default_
  , delete
  , desc_
  , guard_
  , insert
  , insertExpressions
  , limit_
  , orderBy_
  , runDelete
  , runSelectReturningList
  , runUpdate
  , select
  , update
  , val_
  )
import Database.Beam.Postgres ()
import Database.Beam.Postgres.Full (returning, runPgInsertReturningList)
import Database.Beam.Backend.SQL.Types (SqlSerial (..))
import Relude
import Servant (NoContent (..), ServerT, (:<|>) ((:<|>)))

handlers :: ServerT RoutesPeriod AppContext App
handlers =
       getStatus
  :<|> getEntries
  :<|> postEntries
  :<|> patchEntry
  :<|> deleteEntry

-- | Placeholder for cycle logic.
getStatus :: Int64 -> App PeriodStatusResponse
getStatus _uid = do
  now <- liftIO getCurrentTime
  pure $ PeriodStatusResponse PeriodPhaseGreen 1 (utctDay now)

getEntries :: Int64 -> Maybe Int -> Maybe Day -> App [PeriodEntryResponse]
getEntries uid mLimit mBefore = do
  entries <- runBeamApp $ runSelectReturningList $ select $
    limit_ (fromIntegral $ fromMaybe 100 mLimit) $
    orderBy_ (desc_ . periodEntryStartDate) $ do
      entry <- all_ (_periodEntries lucianaDb)
      guard_ (periodEntryUserId entry ==. UserId (val_ (SqlSerial uid)))
      case mBefore of
        Nothing -> pass
        Just b  -> guard_ (periodEntryStartDate entry <. val_ b)
      pure entry
  pure $ map toResponse entries

postEntries :: Int64 -> PeriodEntryRequest -> App CreatePeriodEntryResponse
postEntries uid req = do
  now <- liftIO getCurrentTime
  mEntry <- runBeamApp $ runPgInsertReturningList $
    returning (Database.Beam.insert (_periodEntries lucianaDb) (insertExpressions
      [ PeriodEntry
          { periodEntryId        = default_
          , periodEntryUserId    = UserId (val_ (SqlSerial uid))
          , periodEntryStartDate = val_ (peqStartDate req)
          , periodEntryEndDate   = val_ (peqEndDate req)
          , periodEntryNotes     = val_ (peqNotes req)
          , periodEntryCreatedAt = val_ now
          }
      ])) (\row -> row)
  case mEntry of
    [entry] -> pure $ CreatePeriodEntryResponse $ toCommonId (primaryKey entry)
    _       -> error "Insert failed to return exactly one entry"

patchEntry :: Int64 -> Common.Period.PeriodEntryId -> PeriodEntryRequest -> App NoContent
patchEntry uid (Common.Period.PeriodEntryId eid) req = do
  runBeamApp $ runUpdate $ update (_periodEntries lucianaDb)
    (\e -> mconcat
      [ periodEntryStartDate e <-. val_ (peqStartDate req)
      , periodEntryEndDate e   <-. val_ (peqEndDate req)
      , periodEntryNotes e     <-. val_ (peqNotes req)
      ]
    )
    (\e -> periodEntryId e ==. val_ (SqlSerial eid) &&. periodEntryUserId e ==. UserId (val_ (SqlSerial uid)))
  pure NoContent

deleteEntry :: Int64 -> Common.Period.PeriodEntryId -> App NoContent
deleteEntry uid (Common.Period.PeriodEntryId eid) = do
  runBeamApp $ runDelete $ delete (_periodEntries lucianaDb)
    (\e -> periodEntryId e ==. val_ (SqlSerial eid) &&. periodEntryUserId e ==. UserId (val_ (SqlSerial uid)))
  pure NoContent

toResponse :: PeriodEntryT Identity -> PeriodEntryResponse
toResponse e = PeriodEntryResponse
  { perId        = toCommonId (primaryKey e)
  , perStartDate = periodEntryStartDate e
  , perEndDate   = periodEntryEndDate e
  , perNotes     = periodEntryNotes e
  }

toCommonId :: Backend.Schema.PeriodEntry.PeriodEntryId -> Common.Period.PeriodEntryId
toCommonId (Backend.Schema.PeriodEntry.PeriodEntryId (SqlSerial i)) = Common.Period.PeriodEntryId i
