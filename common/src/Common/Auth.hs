module Common.Auth
  ( Username
  , unUsername
  , mkUsername
  , Password
  , unPassword
  , mkPassword
  , AuthError (..)
  , RegisterRequest (..)
  , LoginRequest (..)
  , UserResponse (..)
  , LoginResult (..)
  , RegisterResult (..)
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

-- | Validated username. Smart constructor in 'mkUsername'.
newtype Username = Username { unUsername :: Text }
  deriving stock (Eq, Show)

mkUsername :: Text -> Either AuthError Username
mkUsername raw =
  let trimmed = T.strip raw
      n       = T.length trimmed
  in if | n == 0  -> Left InvalidUsername
        | n > 64  -> Left InvalidUsername
        | otherwise -> Right (Username trimmed)

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
  = InvalidUsername
  | InvalidPassword
  deriving stock (Eq, Show)

data RegisterRequest = RegisterRequest
  { rrUsername :: Username
  , rrPassword :: Password
  , rrLocale   :: Locale
  , rrTimezone :: Text
  }

data LoginRequest = LoginRequest
  { lrUsername :: Username
  , lrPassword :: Password
  }

data UserResponse = UserResponse
  { urId       :: Int64
  , urUsername :: Text
  , urLocale   :: Locale
  , urTimezone :: Text
  }
  deriving stock (Eq, Show)

instance FromJSON Username where
  parseJSON = withText "Username" $ \t -> case mkUsername t of
    Right u -> pure u
    Left _  -> fail "invalid username"

instance ToJSON Username where
  toJSON = toJSON . unUsername

instance FromJSON Password where
  parseJSON = withText "Password" $ \t -> case mkPassword t of
    Right p -> pure p
    Left _  -> fail "invalid password"

instance FromJSON RegisterRequest where
  parseJSON = withObject "RegisterRequest" $ \o ->
    RegisterRequest
      <$> o .: "username"
      <*> o .: "password"
      <*> o .: "locale"
      <*> o .: "timezone"

instance ToJSON RegisterRequest where
  toJSON r = object
    [ "username" .= rrUsername r
    , "password" .= unPassword (rrPassword r)
    , "locale"   .= rrLocale r
    , "timezone" .= rrTimezone r
    ]

instance FromJSON LoginRequest where
  parseJSON = withObject "LoginRequest" $ \o ->
    LoginRequest
      <$> o .: "username"
      <*> o .: "password"

instance ToJSON LoginRequest where
  toJSON r = object
    [ "username" .= lrUsername r
    , "password" .= unPassword (lrPassword r)
    ]

instance ToJSON UserResponse where
  toJSON ur = object
    [ "id"       .= urId ur
    , "username" .= urUsername ur
    , "locale"   .= urLocale ur
    , "timezone" .= urTimezone ur
    ]

instance FromJSON UserResponse where
  parseJSON = withObject "UserResponse" $ \o ->
    UserResponse
      <$> o .: "id"
      <*> o .: "username"
      <*> o .: "locale"
      <*> o .: "timezone"

-- | Outcome of @POST /api/auth/login@. Application-level outcomes ride
-- inside the JSON body; rate limiting is signalled at the HTTP layer
-- with @429@. See @plans/authentication.md@ § Routes.
data LoginResult
  = LoginOk UserResponse
  | InvalidCredentials
  deriving stock (Eq, Show)

instance ToJSON LoginResult where
  toJSON = \case
    LoginOk u          -> object ["result" .= ("ok" :: Text), "user" .= u]
    InvalidCredentials -> object ["result" .= ("invalid_credentials" :: Text)]

instance FromJSON LoginResult where
  parseJSON = withObject "LoginResult" $ \o -> do
    r <- o .: "result"
    case (r :: Text) of
      "ok"                  -> LoginOk <$> o .: "user"
      "invalid_credentials" -> pure InvalidCredentials
      other                 -> fail ("unknown LoginResult: " <> toString other)

-- | Outcome of @POST /api/auth/register@.
data RegisterResult
  = RegisterOk UserResponse
  | UsernameTaken
  deriving stock (Eq, Show)

instance ToJSON RegisterResult where
  toJSON = \case
    RegisterOk u  -> object ["result" .= ("ok" :: Text), "user" .= u]
    UsernameTaken -> object ["result" .= ("username_taken" :: Text)]

instance FromJSON RegisterResult where
  parseJSON = withObject "RegisterResult" $ \o -> do
    r <- o .: "result"
    case (r :: Text) of
      "ok"             -> RegisterOk <$> o .: "user"
      "username_taken" -> pure UsernameTaken
      other            -> fail ("unknown RegisterResult: " <> toString other)
