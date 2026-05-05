import Relude

import Frontend (frontend)
import Common.Route (fullRouteEncoder)
import Obelisk.Frontend (runFrontend)
import Obelisk.Route.Frontend (checkEncoder)
import Reflex.Dom (run)

main :: IO ()
main = case checkEncoder fullRouteEncoder of
  Left e -> error $ "Invalid encoder: " <> e
  Right validFullEncoder ->
    run $ runFrontend validFullEncoder frontend
