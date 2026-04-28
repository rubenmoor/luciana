module Backend.Auth.Cookie
  ( cookieName
  , issueCookieHeader
  , clearCookieHeader
  , readCookieToken
  ) where

import qualified Data.ByteString.Builder as BSB
import qualified Data.ByteString.Lazy as LBS
import Data.Time (DiffTime, secondsToDiffTime)
import Relude
import Snap.Core (MonadSnap)
import qualified Snap.Core as Snap
import Web.Cookie
  ( SetCookie
      ( setCookieHttpOnly
      , setCookieMaxAge
      , setCookieName
      , setCookiePath
      , setCookieSameSite
      , setCookieSecure
      , setCookieValue
      )
  , defaultSetCookie
  , renderSetCookie
  , sameSiteStrict
  )

cookieName :: ByteString
cookieName = "luciana_session"

sessionLifetime :: DiffTime
sessionLifetime = secondsToDiffTime (60 * 60 * 24 * 30)

issueCookieHeader :: Bool -> Text -> ByteString
issueCookieHeader secure tok =
  renderSetCookieToBytes $ defaultSetCookie
    { setCookieName     = cookieName
    , setCookieValue    = encodeUtf8 tok
    , setCookiePath     = Just "/"
    , setCookieMaxAge   = Just sessionLifetime
    , setCookieHttpOnly = True
    , setCookieSecure   = secure
    , setCookieSameSite = Just sameSiteStrict
    }

clearCookieHeader :: Bool -> ByteString
clearCookieHeader secure =
  renderSetCookieToBytes $ defaultSetCookie
    { setCookieName     = cookieName
    , setCookieValue    = ""
    , setCookiePath     = Just "/"
    , setCookieMaxAge   = Just 0
    , setCookieHttpOnly = True
    , setCookieSecure   = secure
    , setCookieSameSite = Just sameSiteStrict
    }

renderSetCookieToBytes :: SetCookie -> ByteString
renderSetCookieToBytes = LBS.toStrict . BSB.toLazyByteString . renderSetCookie

readCookieToken :: MonadSnap m => m (Maybe ByteString)
readCookieToken = fmap Snap.cookieValue <$> Snap.getCookie cookieName
