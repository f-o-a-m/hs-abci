---
title: Nameservice - Testing
---

# Testing and Client Generation

It's time to see the real benefits of including as much information as possible in the types, which goes beyond a simple guarantee that certain things won't fail at runtime. Since the `api`s for querying state and delivering transactions were specified in the type of each module, hence in the type of the application via the `ModulesList`, we are able to generate client libraries for these actions for free. This is especially useful in testing to eliminate as much boilerplate as possible, and to get compile time failures whenever an api change would break your tests.


Let's take a look at how this works in the `E2E` test suite:


~~~ haskell

module Tutorial.Nameservice.Testing where

import Control.Monad.Reader (ReaderT, runReaderT)
import Data.Default.Class (def)
import Data.Proxy
import Nameservice.Application
import qualified Nameservice.Modules.Nameservice as N
import qualified Network.Tendermint.Client as RPC
import Servant.API ((:<|>) (..))
import qualified Tendermint.SDK.Application.Module as M
import Tendermint.SDK.BaseApp.Errors (AppError (..))
import Tendermint.SDK.BaseApp.Query (QueryArgs (..), QueryResult (..))
import qualified Tendermint.SDK.Modules.Auth as Auth
import qualified Tendermint.SDK.Modules.Bank as B
import Tendermint.SDK.Types.Address (Address)
import Tendermint.Utils.Client
  (ClientConfig (..)
  , EmptyTxClient (..)
  , QueryClientResponse (..)
  , TxClientResponse (..)
  , TxOpts (..)
  , HasTxClient(..)
  , HasQueryClient(..)
  , defaultClientTxOpts
  )
import Tendermint.Utils.ClientUtils (rpcConfig)
~~~

First let's look at how to generate a client for querying state. If you've ever used servant client, this should look familiar since the design was heavily influenced (i.e. shamelessly stolen) from there:


~~~ haskell

getAccount
  :: QueryArgs Address
  -> RPC.TendermintM (QueryClientResponse Auth.Account)

getWhois
  :: QueryArgs N.Name
  -> RPC.TendermintM (QueryClientResponse N.Whois)

getBalance
  :: QueryArgs Address
  -> Auth.CoinId
  -> RPC.TendermintM (QueryClientResponse Auth.Coin)

getWhois :<|> getBalance :<|> getAccount =
  genClientQ (Proxy :: Proxy m) queryApiP def
  where
    queryApiP :: Proxy (M.ApplicationQ NameserviceModules)
    queryApiP = Proxy
~~~

We can then use these generated functions by simply providing an `RPCConfig` object as defined in the Tendermint client library:

~~~ haskell
getWhois' :: QueryArgs N.Name -> IO (QueryClientResponse N.Whois)
getWhois' = RPC.runTendermintM rpcConfig . getWhois
~~~

Similarly we can generate a client for sending transactions as well. This is slightly tricker because of the `nonce` problem, explained in the following chain of reasoning:

1. In order to submit a valid transaction, we need to provide the correct nonce value for the transaction author, which is an ever increasing sequence of natural numbers.
2. In order to get the current nonce value for a transaction author, we need to query the accounts module for their current nonce value.
3. Therefore in order to generate a client for submitting transactions, we should make use of our query client for the auth module, using the returned nonce value to template the transaction.

Therefore the `ClientConfig` object for the transaction client includes the method for querying nonces:


~~~ haskell
type TxClientM = ReaderT ClientConfig IO

runTxClientM :: TxClientM a -> IO a
runTxClientM m = runReaderT m txClientConfig

txClientConfig :: ClientConfig
txClientConfig =
  let getNonce addr = do
        resp <- RPC.runTendermintM rpcConfig $ getAccount $
          QueryArgs
            { queryArgsHeight = -1
            , queryArgsProve = False
            , queryArgsData = addr
            }
        -- @NOTE: TxNonce should be +1 of accountNonce
        case resp of
          QueryError e ->
            if appErrorCode e == 2
              then pure 1
              else error $ "Unknown nonce error: " <> show (appErrorMessage e)
          QueryResponse QueryResult {queryResultData} ->
            pure $ 1 + Auth.accountNonce queryResultData

  in ClientConfig
       { clientGetNonce = getNonce
       , clientRPC = rpcConfig
       }
~~~


Once we have defined our monad capable of querying nonces, we can then generate the transaction client using this monad as our context.

~~~ haskell

-- Nameservice Client
buyName
  :: TxOpts
  -> N.BuyNameMsg
  -> TxClientM (TxClientResponse () ())

setName
  :: TxOpts
  -> N.SetNameMsg
  -> TxClientM (TxClientResponse () ())

deleteName
  :: TxOpts
  -> N.DeleteNameMsg
  -> TxClientM (TxClientResponse () ())

-- Bank Client
transfer
  :: TxOpts
  -> B.TransferMsg
  -> TxClientM (TxClientResponse () ())

faucet
  :: TxOpts
  -> N.FaucetAccountMsg
  -> TxClientM (TxClientResponse () ())

(buyName :<|> setName :<|> deleteName :<|> faucet) :<|>
  (_ :<|> transfer) :<|>
  EmptyTxClient =
    genClientT (Proxy @TxClientM) txApiCP txApiDP defaultClientTxOpts
    where
      txApiCP :: Proxy (M.ApplicationC NameserviceModules)
      txApiCP = Proxy
      txApiDP :: Proxy (M.ApplicationD NameserviceModules)
      txApiDP = Proxy
~~~

Here you'll see that the `TxClientResponse` has two type variables, which in this case are always both `()`. This is because it is possible to return separate values depending on whether we are in the `checkTx` versus `deliverTx` context.


To see how these clients are used together with other test combinators for the `hs-abci-test-utils` package, you can view the `E2E` test files in the nameservice test suite.
