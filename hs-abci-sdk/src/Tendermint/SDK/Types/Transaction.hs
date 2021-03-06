module Tendermint.SDK.Types.Transaction where

import           Control.Error                  (note)
import           Control.Lens                   (Wrapped (..), from, iso, view,
                                                 (&), (.~), (^.), _Unwrapped')
import           Crypto.Hash                    (Digest, hashWith)
import           Crypto.Hash.Algorithms         (SHA256 (..))
import           Data.Bifunctor                 (bimap)
import           Data.ByteString                (ByteString)
import           Data.Int                       (Int64)
import qualified Data.ProtoLens                 as P
import           Data.Proxy
import           Data.String.Conversions        (cs)
import           Data.Text                      (Text)
import           Data.Word                      (Word64)
import           GHC.Generics                   (Generic)
import qualified Proto.Types.Transaction        as T
import qualified Proto.Types.Transaction_Fields as T
import           Tendermint.SDK.Codec           (HasCodec (..))
import           Tendermint.SDK.Crypto          (MakeDigest (..),
                                                 RecoverableSignatureSchema (..),
                                                 SignatureSchema (..))
import           Tendermint.SDK.Types.Message   (Msg (..), TypedMessage (..))

-- Our standard transaction type parameterized by the signature schema 'alg'
-- and an underlying message type 'msg'.
data Tx alg msg = Tx
  { txMsg       :: Msg msg
  , txRoute     :: Text
  , txGas       :: Int64
  , txSignature :: RecoverableSignature alg
  , txSignBytes :: Message alg
  , txSigner    :: PubKey alg
  , txNonce     :: Word64
  }

instance Functor (Tx alg) where
  fmap f tx@Tx{txMsg} = tx {txMsg = fmap f txMsg}

--------------------------------------------------------------------------------

-- TODO: figure out what the actual standards are for these things, if there
-- even are any.

-- | Raw transaction type coming in over the wire
data RawTransaction = RawTransaction
  { rawTransactionData      :: TypedMessage
  -- ^ the encoded message via protobuf encoding
  , rawTransactionGas       :: Int64
  , rawTransactionRoute     :: Text
  -- ^ module name
  , rawTransactionSignature :: ByteString
  , rawTransactionNonce     :: Word64
  } deriving Generic

instance Wrapped RawTransaction where
  type Unwrapped RawTransaction = T.RawTransaction

  _Wrapped' = iso t f
   where
    t RawTransaction {..} =
      P.defMessage
        & T.data' .~ (rawTransactionData ^. _Wrapped')
        & T.gas .~ rawTransactionGas
        & T.route .~ rawTransactionRoute
        & T.signature .~ rawTransactionSignature
        & T.nonce .~ rawTransactionNonce
    f message = RawTransaction
      { rawTransactionData      = message ^. T.data' . _Unwrapped'
      , rawTransactionGas = message ^. T.gas
      , rawTransactionRoute = message ^. T.route
      , rawTransactionSignature = message ^. T.signature
      , rawTransactionNonce = message ^. T.nonce
      }

instance HasCodec RawTransaction where
  encode = P.encodeMessage . view _Wrapped'
  decode = bimap cs (view $ from _Wrapped') . P.decodeMessage

instance MakeDigest RawTransaction where
  makeDigest tx = hashWith SHA256 . encode $ tx {rawTransactionSignature = ""}

signRawTransaction
  :: forall alg.
     RecoverableSignatureSchema alg
  => Message alg ~ Digest SHA256
  => Proxy alg
  -> PrivateKey alg --
  -> RawTransaction
  -> RecoverableSignature alg
signRawTransaction p priv tx = signRecoverableMessage p priv (makeDigest tx)

-- | Attempt to parse a Bytestring into a 'RawTransaction' then as a 'Tx' without
-- | attempting to parse the underlying message. This is done as a preprocessing
-- | step to the router, allowing for failure before the router is ever
-- | reached.
parseTx
  :: forall alg.
     RecoverableSignatureSchema alg
  => Message alg ~ Digest SHA256
  => Proxy alg
  -> ByteString
  -> Either Text (Tx alg ByteString)
parseTx p bs = do
  rawTx@RawTransaction{..} <- decode bs
  recSig <- note "Unable to parse transaction signature as a recovery signature." $
    makeRecoverableSignature p rawTransactionSignature
  let txForSigning = rawTx {rawTransactionSignature = ""}
      signBytes = makeDigest txForSigning
  signerPubKey <- note "Signature recovery failed." $ recover p recSig signBytes
  return $ Tx
    { txMsg = Msg
              { msgData = typedMsgData rawTransactionData
              , msgAuthor = addressFromPubKey p signerPubKey
              , msgType = typedMsgType rawTransactionData
              }
    , txRoute = cs rawTransactionRoute
    , txGas = rawTransactionGas
    , txSignature = recSig
    , txSignBytes = signBytes
    , txSigner = signerPubKey
    , txNonce = rawTransactionNonce
    }
