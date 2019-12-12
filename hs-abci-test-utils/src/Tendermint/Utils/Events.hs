module Tendermint.Utils.Events
  ( Event(..)
  , ToEvent(..)
  , FromEvent(..)
  , emit
  , makeEvent
  , EventBuffer
  , newEventBuffer
  , withEventBuffer
  , evalWithBuffer
  ) where

import qualified Control.Concurrent.MVar                as MVar
import           Control.Error                          (fmapL)
import           Control.Monad                          (void)
import           Control.Monad.IO.Class
import qualified Data.Aeson                             as A
import           Data.Bifunctor                         (bimap)
import qualified Data.ByteArray.Base64String            as Base64
import qualified Data.ByteString                        as BS
import qualified Data.List                              as L
import           Data.Proxy
import           Data.String.Conversions                (cs)
import           Data.Text                              (Text)
import           GHC.Exts                               (fromList, toList)
import           Network.ABCI.Types.Messages.FieldTypes (Event (..),
                                                         KVPair (..))
import           Polysemy                               (Embed, Member, Sem,
                                                         interpret)
import           Polysemy.Output                        (Output (..), output)
import           Polysemy.Reader                        (Reader (..), ask)
import           Polysemy.Resource                      (Resource, onException)

{-
TODO : These JSON instances are fragile but convenient. We
should come up with a custom solution.
-}

-- | A class representing a type that can be emitted as an event in the
-- | event logs for the deliverTx response.
class ToEvent e where
  makeEventType :: Proxy e -> String
  makeEventData :: e -> [(BS.ByteString, BS.ByteString)]

  default makeEventData :: A.ToJSON e => e -> [(BS.ByteString, BS.ByteString)]
  makeEventData e = case A.toJSON e of
    A.Object obj -> bimap cs (cs . A.encode) <$> toList obj
    _            -> mempty

-- | A class that can parse event log items in the deliverTx response. Primarily
-- | useful for client applications and testing.
class ToEvent e => FromEvent e where
  fromEvent :: Event -> Either Text e

  default fromEvent :: A.FromJSON e => Event -> Either Text e
  fromEvent Event{eventType, eventAttributes} =
    let expectedType = makeEventType (Proxy @e)
    in if cs eventType /= expectedType
         then fail ("Couldn't match expected event type " <> expectedType <>
                " with found type " <> cs eventType)
         else
           let fromKVPair :: KVPair -> Either String (Text, A.Value)
               fromKVPair (KVPair k v) = do
                 value <- A.eitherDecode . cs @BS.ByteString . Base64.toBytes $ v
                 return (cs @BS.ByteString . Base64.toBytes $ k, value)
           in fmapL cs $ do
             kvPairs <- traverse fromKVPair eventAttributes
             A.eitherDecode . A.encode . A.Object . fromList $ kvPairs

-- This is the internal implementation of the interpreter for event
-- logging. We allocate a buffer that can queue events as they are thrown,
-- then flush the buffer at the end of transaction execution. It will
-- also flush in the event that exceptions are thrown.

data EventBuffer = EventBuffer (MVar.MVar [Event])

newEventBuffer :: IO EventBuffer
newEventBuffer = EventBuffer <$> MVar.newMVar []

appendEvent
  :: MonadIO (Sem r)
  => Event
  -> EventBuffer
  -> Sem r ()
appendEvent e (EventBuffer b) = do
  liftIO (MVar.modifyMVar_ b (pure . (e :)))

flushEventBuffer
  :: MonadIO (Sem r)
  => EventBuffer
  -> Sem r [Event]
flushEventBuffer (EventBuffer b) = do
  liftIO (L.reverse <$> MVar.swapMVar b [])

withEventBuffer
  :: Member Resource r
  => Member (Reader EventBuffer) r
  => MonadIO (Sem r)
  => Sem r ()
  -> Sem r [Event]
withEventBuffer action = do
  buffer <- ask
  onException (action *> flushEventBuffer buffer) (void $ flushEventBuffer buffer)

makeEvent
  :: ToEvent e
  => e
  -> Event
makeEvent (e :: e) = Event
  { eventType = cs $ makeEventType (Proxy :: Proxy e)
  , eventAttributes = (\(k, v) -> KVPair (Base64.fromBytes k) (Base64.fromBytes v)) <$> makeEventData e
  }

emit
  :: ToEvent e
  => Member (Output Event) r
  => e
  -> Sem r ()
emit e = output $ makeEvent e

evalWithBuffer
  :: Member (Embed IO) r
  => Member (Reader EventBuffer) r
  => (forall a. Sem (Output Event ': r) a -> Sem r a)
evalWithBuffer action = interpret (\case
  Output e -> ask >>= appendEvent e
  ) action
