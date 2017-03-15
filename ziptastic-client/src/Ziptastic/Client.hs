{-# LANGUAGE
    DataKinds
  , TypeOperators
  , OverloadedStrings
#-}

-- | This module provides a simple interface to Ziptastic's forward and reverse geocoding API
-- (<https://www.getziptastic.com/>).
--
-- > {-# LANGUAGE OverloadedStrings #-}
-- > import Data.ISO3166_CountryCodes (CountryCode(US))
-- > import Network.HTTP.Client (newManager)
-- > import Network.HTTP.Client.TLS (tlsManagerSettings)
-- > import Ziptastic.Client
-- >
-- > apiKey :: ApiKey
-- > apiKey = "abcdefghijklmnopqrstuvwxyz"
-- >
-- > main :: IO ()
-- > main = do
-- >   manager <- newManager tlsManagerSettings
-- >   print =<< forwardGeocode apiKey manager US "48867"
-- >   print =<< reverseGeocode apiKey manager 42.9934 (-84.1595)
module Ziptastic.Client
  ( ApiKey(..)
  , LocaleInfo(..)
  , Core.LocaleCoords(..)
  , forwardGeocode
  , reverseGeocode
  , reverseGeocodeWithRadius
  ) where

import           Data.ISO3166_CountryCodes (CountryCode)
import           Data.Proxy (Proxy(..))
import           Data.Text (Text)
import           Network.HTTP.Client (Manager)
import           Servant.API ((:<|>)(..))
import           Servant.Client
  ( BaseUrl(..), ClientEnv(..), ClientM, Scheme(..), ServantError
  , client, runClientM
  )

import           Ziptastic.Core (ApiKey, ForApi(..), LocaleInfo)
import qualified Ziptastic.Core as Core

-- | Performs a forward geocode lookup at the given country and postal code.
--
-- The success result is a list because in rare cases you may receive multiple records.
-- If the request fails the result will be 'Left' with an error.
forwardGeocode :: ApiKey
               -> Manager      -- ^ HTTP connection manager
               -> CountryCode  -- ^ country
               -> Text         -- ^ postal code
               -> IO (Either ServantError [LocaleInfo])
forwardGeocode apiKey manager countryCode postalCode = runClientM func (ClientEnv manager baseUrl)
  where func = forwardGeocode' (apiClient apiKey) (ForApi countryCode) postalCode

-- | Performs a reverse geocode lookup at the given coordinates using a default radius of 5000 meters.
--
-- The success result is a list because in rare cases you may receive multiple records.
-- If the request fails the result will be 'Left' with an error.
reverseGeocode :: ApiKey
               -> Manager -- ^ HTTP connection manager
               -> Double  -- ^ latitude
               -> Double  -- ^ longitude
               -> IO (Either ServantError [LocaleInfo])
reverseGeocode apiKey manager lat long = reverseGeocodeWithRadius apiKey manager lat long 5000

-- | Performs a reverse geocode lookup at the given coordinates using a specified radius in meters.
--
-- The success result is a list because in rare cases you may receive multiple records.
-- If the request fails the result will be 'Left' with an error.
reverseGeocodeWithRadius :: ApiKey
                         -> Manager -- ^ HTTP connection manager
                         -> Double  -- ^ latitude
                         -> Double  -- ^ longitude
                         -> Int     -- ^ radius (in meters)
                         -> IO (Either ServantError [LocaleInfo])
reverseGeocodeWithRadius apiKey manager lat long radius = runClientM func (ClientEnv manager baseUrl)
  where func = reverseGeocodeWithRadius' (mkReverseGeocode (apiClient apiKey) lat long) radius


data ApiClient = ApiClient
  { forwardGeocode'  :: ForApi CountryCode -> Text -> ClientM [LocaleInfo]
  , mkReverseGeocode :: Double -> Double -> ReverseGeocodeApiClient
  }
data ReverseGeocodeApiClient = ReverseGeocodeApiClient
  { reverseGeocodeWithRadius' :: Int -> ClientM [LocaleInfo]
  , reverseGeocode'           :: ClientM [LocaleInfo]
  }

-- TODO: This boilerplate can be removed with servant-client 0.10 with Servant.Client.Generic.
apiClient :: ApiKey -> ApiClient
apiClient apiKey = ApiClient
  { forwardGeocode'  = forwardGeocodeApi
  , mkReverseGeocode = mkReversGeocodeEndpoints
  }
  where
    forwardGeocodeApi :<|> reverseGeocodeApi = client (Proxy :: Proxy Core.Api) (Just apiKey)
    mkReversGeocodeEndpoints lat long = ReverseGeocodeApiClient
      { reverseGeocodeWithRadius' = withRadius
      , reverseGeocode'           = withDefaultRadius
      }
      where
        withRadius :<|> withDefaultRadius = reverseGeocodeApi lat long

baseUrl :: BaseUrl
baseUrl = BaseUrl
  { baseUrlScheme = if Core.baseUrlIsHttps then Https else Http
  , baseUrlHost   = Core.baseUrlHost
  , baseUrlPort   = Core.baseUrlPort
  , baseUrlPath   = Core.baseUrlPath
  }

