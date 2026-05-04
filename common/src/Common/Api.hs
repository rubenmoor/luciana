{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TypeOperators #-}

-- | The JSON API description.
--
-- Single source of truth for @/api/*@ URL paths, HTTP methods, request
-- bodies, and response shapes. The backend implements 'RoutesApi' via
-- @servant-snap@; the frontend's 'Frontend.Api.apiUrl' renders paths
-- using the constants in this module so paths can't drift between
-- sides.
--
-- The 'AuthRequired' and 'RateLimit' combinators are phantom types;
-- their server-side @HasServer@ instances live in
-- 'Backend.Auth.Combinator' and 'Backend.RateLimit.Combinator'.
module Common.Api
  ( AuthRequired
  , RateLimit
  , RoutesApi
  , RoutesAuth
  , apiBase
  , authPath
  , registerPath
  , loginPath
  , logoutPath
  , mePath
  ) where

import Common.Auth
  ( LoginRequest
  , LoginResult
  , RegisterRequest
  , RegisterResult
  , UserResponse
  )
import GHC.TypeLits (Symbol)
import Relude
import Servant.API
  ( (:<|>)
  , (:>)
  , Get
  , Header
  , Headers
  , JSON
  , NoContent
  , Post
  , ReqBody
  , StdMethod (POST)
  , Verb
  )

-- | Phantom combinator for routes that require a valid session cookie.
-- The 'HasServer' instance lives in @Backend.Auth.Combinator@; it
-- resolves the cookie to a 'UserId' (passed to the handler) or short-
-- circuits with @401@.
data AuthRequired (tag :: k)

-- | Phantom combinator for routes that consume one rate-limit token,
-- keyed on @(client IP, bucket symbol)@. The 'HasServer' instance lives
-- in @Backend.RateLimit.Combinator@; it injects a 'RateBucket' into the
-- handler so handlers that want to clear the bucket on success (login)
-- can do so.
data RateLimit (bucket :: Symbol)

type RoutesApi = "api" :> RoutesAuth

type RoutesAuth = "auth" :>
  (    RateLimit "register"
         :> "register"
         :> ReqBody '[JSON] RegisterRequest
         :> Post '[JSON] (Headers '[Header "Set-Cookie" Text] RegisterResult)
  :<|> RateLimit "login"
         :> "login"
         :> ReqBody '[JSON] LoginRequest
         :> Post '[JSON] (Headers '[Header "Set-Cookie" Text] LoginResult)
  :<|> AuthRequired "session"
         :> "logout"
         :> Verb 'POST 204 '[JSON] (Headers '[Header "Set-Cookie" Text] NoContent)
  :<|> AuthRequired "session"
         :> "me"
         :> Get '[JSON] UserResponse
  )

-- | URL path constants. Must match the path-segment literals used in
-- 'RoutesApi' above; the backend's servant routing parses one half,
-- the frontend's 'Frontend.Api' builds requests against the other.
--
-- Composing them as @apiBase <> authPath <> loginPath@ — rather than
-- writing @"/api/auth/login"@ once — keeps every segment named, so a
-- future rename touches one constant.
apiBase, authPath, registerPath, loginPath, logoutPath, mePath :: Text
apiBase      = "/api"
authPath     = "/auth"
registerPath = "/register"
loginPath    = "/login"
logoutPath   = "/logout"
mePath       = "/me"
