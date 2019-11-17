{-# LANGUAGE TemplateHaskell #-}

module SimpleStorage.Modules.SimpleStorage
  (
  -- * Component
    SimpleStorage
  , putCount
  , getCount

  , Api
  , server
  , eval
  , initialize

  -- * Store
  , CountStoreContents

  -- * Types
  , Count(..)
  , CountKey(..)

  -- * Events
  , CountSet

  ) where

import           Control.Lens                (iso)
import           Crypto.Hash                 (SHA256 (..), hashWith)
import qualified Data.Aeson                  as A
import           Data.Bifunctor              (first)
import           Data.ByteArray              (convert)
import           Data.ByteString             (ByteString)
import           Data.Int                    (Int32)
import           Data.Maybe                  (fromJust)
import           Data.Proxy
import qualified Data.Serialize              as Serialize
import           Data.String.Conversions     (cs)
import           GHC.Generics                (Generic)
import           Polysemy                    (Member, Sem, interpret, makeSem)
import           Polysemy.Output             (Output)
import           Servant.API                 ((:>))
import           Tendermint.SDK.BaseApp      (HasBaseAppEff)
import           Tendermint.SDK.Codec        (HasCodec (..))
import qualified Tendermint.SDK.Events       as Events
import           Tendermint.SDK.Router       (EncodeQueryResult, FromQueryData,
                                              Queryable (..), RouteT)
import           Tendermint.SDK.Store        (IsKey (..), RawKey (..), RawStore,
                                              StoreKey (..), get, put)
import           Tendermint.SDK.StoreQueries (QueryApi, storeQueryHandlers)

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

newtype Count = Count Int32 deriving (Eq, Show, A.ToJSON, A.FromJSON, Serialize.Serialize)

data CountKey = CountKey

instance HasCodec Count where
    encode = Serialize.encode
    decode = first cs . Serialize.decode

instance RawKey CountKey where
    rawKey = iso (\_ -> cs countKey) (const CountKey)
      where
        countKey :: ByteString
        countKey = convert . hashWith SHA256 . cs @_ @ByteString $ ("count" :: String)

instance IsKey CountKey "simple_storage" where
    type Value CountKey "simple_storage" = Count

instance FromQueryData CountKey

instance EncodeQueryResult Count

instance Queryable Count where
  type Name Count = "count"

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

data CountSet = CountSet { newCount :: Count } deriving Generic

countSetOptions :: A.Options
countSetOptions = A.defaultOptions

instance A.ToJSON CountSet where
  toJSON = A.genericToJSON countSetOptions

instance A.FromJSON CountSet where
  parseJSON = A.genericParseJSON countSetOptions

instance Events.ToEvent CountSet where
  makeEventType _ = "count_set"

--------------------------------------------------------------------------------
-- SimpleStorage Module
--------------------------------------------------------------------------------

storeKey :: StoreKey "simple_storage"
storeKey = StoreKey "simple_storage"

data SimpleStorage m a where
    PutCount :: Count -> SimpleStorage m ()
    GetCount :: SimpleStorage m Count

makeSem ''SimpleStorage

eval
  :: forall r.
     HasBaseAppEff r
  => forall a. (Sem (SimpleStorage ': r) a -> Sem r a)
eval = interpret (\case
  PutCount count -> do
    put storeKey CountKey count
    Events.emit $ CountSet count

  GetCount -> fromJust <$> get storeKey CountKey
  )

initialize
  :: HasBaseAppEff r
  => Member (Output Events.Event) r
  => Sem r ()
initialize = eval $ do
  putCount (Count 0)

--------------------------------------------------------------------------------
-- Query Api
--------------------------------------------------------------------------------

type CountStoreContents = '[(CountKey, Count)]

type Api = "simple_storage" :> QueryApi CountStoreContents

server :: Member RawStore r => RouteT Api (Sem r)
server =
  storeQueryHandlers (Proxy :: Proxy CountStoreContents) storeKey (Proxy :: Proxy (Sem r))
