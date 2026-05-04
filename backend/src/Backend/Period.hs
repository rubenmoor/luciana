{-# LANGUAGE TypeApplications #-}

module Backend.Period
  ( handlers
  ) where

import Backend.App (App, runBeamApp)
import Backend.Schema.Db (lucianaDb)
import Backend.Schema.PeriodEntry
  ( PeriodEntryT (..)
  , PeriodEntryId
  , PrimaryKey (PeriodEntryId)
  )
import Backend.Schema.User (UserId)
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
import Database.Beam.Backend.SQL.Types (SqlSerial (..))
import Relude
import Servant (NoContent (..), (:<|>) ((:<|>)))

handlers :: ServerT RoutesPeriod AppContext App
handlers =
       getStatus
  :<|> getEntries
  :<|> postEntries
  :<|> patchEntry
  :<|> deleteEntry

-- | Placeholder for cycle logic.
getStatus :: UserId -> App PeriodStatusResponse
getStatus _uid = do
  now <- liftIO getCurrentTime
  pure $ PeriodStatusResponse Green 1 (utctDay now)

getEntries :: UserId -> Maybe Int -> Maybe Day -> App [PeriodEntryResponse]
getEntries uid mLimit mBefore = do
  entries <- runBeamApp $ runSelectReturningList $ select $
    limit_ (fromIntegral $ fromMaybe 100 mLimit) $
    orderBy_ (desc_ . periodEntryStartDate) $ do
      entry <- all_ (_periodEntries lucianaDb)
      guard_ (periodEntryUserId entry ==. val_ uid)
      case mBefore of
        Nothing -> pass
        Just b  -> guard_ (periodEntryStartDate entry <. val_ b)
      pure entry
  pure $ map toResponse entries

postEntries :: UserId -> PeriodEntryRequest -> App CreatePeriodEntryResponse
postEntries uid req = do
  now <- liftIO getCurrentTime
  mEntry <- runBeamApp $ runInsertReturningList $ insert (_periodEntries lucianaDb) $
    insertExpressions
      [ PeriodEntry
          { periodEntryId        = default_
          , periodEntryUserId    = val_ uid
          , periodEntryStartDate = val_ (peqStartDate req)
          , periodEntryEndDate   = val_ (peqEndDate req)
          , periodEntryNotes     = val_ (peqNotes req)
          , periodEntryCreatedAt = val_ now
          }
      ]
  case mEntry of
    [entry] -> pure $ CreatePeriodEntryResponse $ toCommonId (primaryKey entry)
    _       -> error "Insert failed to return exactly one entry"

patchEntry :: UserId -> Common.Period.PeriodEntryId -> PeriodEntryRequest -> App NoContent
patchEntry uid (Common.Period.PeriodEntryId eid) req = do
  runBeamApp $ runUpdate $ update (_periodEntries lucianaDb)
    (\e ->
      [ periodEntryStartDate e <-. val_ (peqStartDate req)
      , periodEntryEndDate e   <-. val_ (peqEndDate req)
      , periodEntryNotes e     <-. val_ (peqNotes req)
      ]
    )
    (\e -> periodEntryId e ==. val_ (SqlSerial eid) &&. periodEntryUserId e ==. val_ uid)
  pure NoContent

deleteEntry :: UserId -> Common.Period.PeriodEntryId -> App NoContent
deleteEntry uid (Common.Period.PeriodEntryId eid) = do
  runBeamApp $ runDelete $ delete (_periodEntries lucianaDb)
    (\e -> periodEntryId e ==. val_ (SqlSerial eid) &&. periodEntryUserId e ==. val_ uid)
  pure NoContent

toResponse :: PeriodEntryT Identity -> PeriodEntryResponse
toResponse e = PeriodEntryResponse
  { perId        = toCommonId (primaryKey e)
  , perStartDate = periodEntryStartDate e
  , perEndDate   = periodEntryEndDate e
  , perNotes     = periodEntryNotes e
  }

toCommonId :: Backend.Schema.PeriodEntry.PeriodEntryId -> Common.Period.PeriodEntryId
toCommonId (PeriodEntryId (SqlSerial i)) = Common.Period.PeriodEntryId i

-- Required for ServerT RoutesPeriod AppContext App
import Common.Api (RoutesPeriod)
import Servant.Server (ServerT)
import Backend.Api (AppContext)
