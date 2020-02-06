{-# LANGUAGE UndecidableInstances #-}
module Tendermint.SDK.BaseApp.Transaction.Router
  ( HasTxRouter(..)
  , emptyTxServer
  ) where

import           Data.ByteString                             (ByteString)
import           Data.Proxy
import           Data.String.Conversions                     (cs)
import           GHC.TypeLits                                (KnownSymbol,
                                                              symbolVal)
import           Polysemy                                    (Sem)
import           Servant.API
import qualified Tendermint.SDK.BaseApp.Router               as R
import           Tendermint.SDK.BaseApp.Transaction.Modifier
import           Tendermint.SDK.BaseApp.Transaction.Types
import           Tendermint.SDK.Codec                        (HasCodec (..))
import           Tendermint.SDK.Types.Message                (HasMessageType (..),
                                                              Msg (..))

--------------------------------------------------------------------------------

class HasTxRouter layout r (c :: RouteContext) where
  type RouteTx layout r c :: *
  routeTx
        :: Proxy layout
        -> Proxy r
        -> Proxy c
        -> R.Delayed (Sem r) env (RoutingTx ByteString) (RouteTx layout r c)
        -> R.Router env r (RoutingTx ByteString) ByteString

  hoistTxRouter :: Proxy layout -> Proxy c -> (forall a. Sem r a -> Sem r' a) -> RouteTx layout r c -> RouteTx layout r' c

instance (HasTxRouter a r c, HasTxRouter b r c) => HasTxRouter (a :<|> b) r c where
  type RouteTx (a :<|> b) r c = RouteTx a r c :<|> RouteTx b r c

  routeTx _ pr pc server =
    R.choice (routeTx (Proxy @a) pr pc ((\ (a :<|> _) -> a) <$> server))
             (routeTx (Proxy @b) pr pc ((\ (_ :<|> b) -> b) <$> server))

  hoistTxRouter _ pc nat (a :<|> b) =
    hoistTxRouter (Proxy @a) pc nat a :<|> hoistTxRouter (Proxy @b) pc nat b

instance (HasTxRouter sublayout r c, KnownSymbol path) => HasTxRouter (path :> sublayout) r c where

  type RouteTx (path :> sublayout) r c = RouteTx sublayout r c

  routeTx _ pr pc subserver =
    R.pathRouter (cs (symbolVal proxyPath)) (routeTx (Proxy @sublayout) pr pc subserver)
    where proxyPath = Proxy @path

  hoistTxRouter _ pc nat = hoistTxRouter (Proxy @sublayout) pc nat

methodRouter
  :: HasCodec a
  => R.Delayed (Sem r) env (RoutingTx msg) (Sem r a)
  -> R.Router env r (RoutingTx msg) ByteString
methodRouter action =
  let route' env tx = R.runAction (fmap encode <$> action) env tx R.Route
  in R.leafRouter route'

instance ( HasMessageType msg, HasCodec msg
         , HasCodec (OnCheckReturn c oc a)
         ) => HasTxRouter (TypedMessage msg :~> Return' oc a) r c where

  type RouteTx (TypedMessage msg :~> Return' oc a) r c = RoutingTx msg -> Sem r (OnCheckReturn c oc a)

  routeTx _ _ _ subserver =
    let f (RoutingTx tx@Tx{txMsg}) =
          if msgType txMsg == mt
            then case decode $ msgData txMsg of
              Left e -> R.delayedFail $
                R.InvalidRequest ("Failed to parse message of type " <> mt <> ": " <> e <> ".")
              Right a -> pure . RoutingTx $ tx {txMsg = txMsg {msgData = a}}
            else R.delayedFail R.PathNotFound
    in methodRouter $ R.addBody subserver $ R.withRequest f
      where mt = messageType (Proxy :: Proxy msg)

  hoistTxRouter _ _ nat = (.) nat

emptyTxServer :: RouteTx EmptyTxServer r c
emptyTxServer = EmptyTxServer

instance HasTxRouter EmptyTxServer r c where
  type RouteTx EmptyTxServer r c = EmptyTxServer
  routeTx _ _ _ _ = R.StaticRouter mempty mempty

  hoistTxRouter _ _ _ = id