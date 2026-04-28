module Common.Auth
  ( Email
  , unEmail
  , mkEmail
  , Password
  , unPassword
  , mkPassword
  , AuthError (..)
  , RegisterRequest (..)
  , LoginRequest (..)
  , UserResponse (..)
  ) where

import Common.I18n (Locale)
import Data.Aeson
  ( FromJSON (parseJSON)
  , ToJSON (toJSON)
  , object
  , withObject
  , withText
  , (.:)
  , (.=)
  )
import qualified Data.Text as T
import Relude

-- | Validated email. Smart constructor in 'mkEmail'.
newtype Email = Email { unEmail :: Text }
  deriving stock (Eq, Show)

mkEmail :: Text -> Either AuthError Email
mkEmail raw =
  let trimmed = T.strip raw
      n       = T.length trimmed
  in if | n == 0           -> Left InvalidEmail
        | n > 254          -> Left InvalidEmail
        | not (T.any (== '@') trimmed) -> Left InvalidEmail
        | otherwise        -> Right (Email trimmed)

-- | Validated plaintext password. Constructed only from a request body;
-- never serialised. No 'Show' or 'ToJSON' instance — keeps the secret out of
-- logs and trace dumps.
newtype Password = Password { unPassword :: Text }
  deriving stock (Eq)

mkPassword :: Text -> Either AuthError Password
mkPassword raw =
  let n = T.length raw
  in if | n < 8   -> Left InvalidPassword
        | n > 200 -> Left InvalidPassword
        | otherwise -> Right (Password raw)

data AuthError
  = InvalidEmail
  | InvalidPassword
  | EmailTaken
  | BadCredentials
  | RateLimited
  deriving stock (Eq, Show)

data RegisterRequest = RegisterRequest
  { rrEmail    :: Email
  , rrPassword :: Password
  , rrLocale   :: Locale
  , rrTimezone :: Text
  }

data LoginRequest = LoginRequest
  { lrEmail    :: Email
  , lrPassword :: Password
  }

data UserResponse = UserResponse
  { urId       :: Int64
  , urEmail    :: Text
  , urLocale   :: Locale
  , urTimezone :: Text
  }
  deriving stock (Eq, Show)

instance FromJSON Email where
  parseJSON = withText "Email" $ \t -> case mkEmail t of
    Right e -> pure e
    Left _  -> fail "invalid email"

instance ToJSON Email where
  toJSON = toJSON . unEmail

instance FromJSON Password where
  parseJSON = withText "Password" $ \t -> case mkPassword t of
    Right p -> pure p
    Left _  -> fail "invalid password"

instance FromJSON RegisterRequest where
  parseJSON = withObject "RegisterRequest" $ \o ->
    RegisterRequest
      <$> o .: "email"
      <*> o .: "password"
      <*> o .: "locale"
      <*> o .: "timezone"

instance ToJSON RegisterRequest where
  toJSON r = object
    [ "email"    .= rrEmail r
    , "password" .= unPassword (rrPassword r)
    , "locale"   .= rrLocale r
    , "timezone" .= rrTimezone r
    ]

instance FromJSON LoginRequest where
  parseJSON = withObject "LoginRequest" $ \o ->
    LoginRequest
      <$> o .: "email"
      <*> o .: "password"

instance ToJSON LoginRequest where
  toJSON r = object
    [ "email"    .= lrEmail r
    , "password" .= unPassword (lrPassword r)
    ]

instance ToJSON UserResponse where
  toJSON ur = object
    [ "id"       .= urId ur
    , "email"    .= urEmail ur
    , "locale"   .= urLocale ur
    , "timezone" .= urTimezone ur
    ]

instance FromJSON UserResponse where
  parseJSON = withObject "UserResponse" $ \o ->
    UserResponse
      <$> o .: "id"
      <*> o .: "email"
      <*> o .: "locale"
      <*> o .: "timezone"
