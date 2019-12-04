module Tendermint.SDK.Test.EventSpec where

import qualified Data.Aeson            as A
import           GHC.Generics          (Generic)
import           Tendermint.SDK.Events (FromEvent (..), ToEvent (..), makeEvent)
import           Test.Hspec

spec :: Spec
spec = describe "Event Tests" $ do
    it "Can serialize and deserialize and event" $ do
      let transferEv =  Transfer
            { to = "me"
            , from = "you"
            , amount = 1
            }
      fromEvent (makeEvent transferEv) `shouldBe` Right transferEv

data Transfer = Transfer
  { to     :: String
  , from   :: String
  , amount :: Int
  } deriving (Eq, Show, Generic)

instance A.ToJSON Transfer

instance ToEvent Transfer where
    makeEventType _ = "transfer"

instance A.FromJSON Transfer
instance FromEvent Transfer
