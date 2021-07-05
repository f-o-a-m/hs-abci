---
title: Nameservice - Module
---

# Module

## Tutorial.Nameservice.Module

At this point we can collect the relevant pieces to form the Nameservice module:

~~~ haskell
module Tutorial.Nameservice.Module where

import Nameservice.Modules.Nameservice.Keeper (NameserviceEffs, eval)
import Nameservice.Modules.Nameservice.Query (QueryApi, querier)
import Nameservice.Modules.Nameservice.Router (MessageApi, messageHandlers)
import Nameservice.Modules.Nameservice.Types (NameserviceName)
import Tendermint.SDK.Application (Module (..), ModuleEffs)
import Tendermint.SDK.BaseApp (DefaultCheckTx (..))
import Tendermint.SDK.Modules.Bank (Bank)
import Data.Proxy
import Polysemy (Members)

-- a convenient type alias
type Nameservice =
  Module NameserviceName MessageApi MessageApi QueryApi NameserviceEffs '[Bank]

nameserviceModule
  :: Members (ModuleEffs Nameservice) r
  => Nameservice r
nameserviceModule = Module
  { moduleTxDeliverer = messageHandlers
  , moduleTxChecker = defaultCheckTx (Proxy :: Proxy MessageApi) (Proxy :: Proxy r)
  , moduleQuerier = querier
  , moduleEval = eval
  }

~~~

Here we are using `defaultCheckTx` as our transaction checker, which is a static, message validating handler defined as:

~~~ haskell ignore
defaultCheckTxHandler
  :: Member (Error AppError) r
  => ValidateMessage msg
  => RoutingTx msg
  -> Sem r ()
defaultCheckTxHandler(RoutingTx Tx{txMsg}) =
  case validateMessage txMsg of
    V.Failure err ->
      throwSDKError . MessageValidation . map formatMessageSemanticError $ err
    V.Success _ -> pure ()
~~~

Note that this checker can be used to implement any transaction for which
1. The message accepted by the router has a `ValidateMessage` instance
2. The return type in the serve type is `Return ()`

To generate a server for which every transaction has these properties, we used the `defaultCheckTx` type class method on the `MessageApi` type. This will generate a server of type `VoidReturn MessageApi`, which has the exact same shape as `MessageApi` just with all the return values changed to `Return ()`. In this particular case all handlers for `MessageApi` already return `()`, so we have `MessageApi ~ VoidReturn MessageApi` and there's no need to use the `VoidReturn` family in the module type.

Note the constraint on `r` in the Module's type using the constraint-valued type family `ModuleEffs`. In this case it evaluates to the following equivalent set of constraints:

~~~ haskell ignore
...
  ModuleEffs Nameservice r
    ~ ( Members NameserviceEffs r
      , Members (DependencyEffs '[Bank] r)
      , Members TxEffs r
      , Members BaseEffs r
      )
    ~ ( Members NameserviceEffs r
      , Members BankEffs r
      , Members TxEffs r
      , Members BaseEffs r
      )
...
~~~

This is saying that we can run this module in any context for which `r` has the effects from  `NameserviceEffs`, `BankEffs`, `TxEffs`, and `BaseEffs`. This is how we explicitly declare global effect dependencies for a module, by using the constraint system.

Other than that, there is nothing really to note. We are just collecting the pieces we have already defined in one place.
