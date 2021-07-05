---
title: Nameservice - Router
---

# Router

## Tutorial.Nameservice.Router

The Router is where you specify the handlers for the messages that the module accepts. The router is typed in a [servant](https://hackage.haskell.org/package/servant) style, using combinators and primitives to declare a very precise type for the router.

~~~ haskell
module Tutorial.Nameservice.Router where

import Nameservice.Modules.Nameservice.Keeper (NameserviceEffs, buyName, deleteName, setName)
import Nameservice.Modules.Nameservice.Messages (BuyName, DeleteName, SetName)
import Polysemy (Members, Sem)
import Tendermint.SDK.Modules.Bank (BankEffs)
import Servant.API ((:<|>) (..))
import Tendermint.SDK.BaseApp
  ((:~>)
  , BaseEffs
  , Return
  , RouteContext (..)
  , RouteTx
  , RoutingTx (..)
  , TxEffs
  , TypedMessage
  , incCount
  , withTimer
  )
import Tendermint.SDK.Types.Message (Msg (..))
import Tendermint.SDK.Types.Transaction (Tx (..))

~~~

## Typing the Router

First we declare the type for our router

~~~ haskell
type MessageApi =
       TypedMessage BuyName :~> Return ()
  :<|> TypedMessage SetName :~> Return ()
  :<|> TypedMessage DeleteName :~> Return ()
~~~

Lets break it down:

- `(:<|>)` is the operator which denotes alternative, so our router is composed of 3 handlers in this case.
- `TypedMessage` is a combinator that specifies the message type we want to accept. We require that whatever the message type is, it implements the `HasTypedMessage` class.
- `(:~>)` is a combinator that allows us to connect a message type with a response
- `Return` is used to specify the return type.

Since there are two possible ABCI messages that the router has to accommodate, `checkTx` and `deliverTx`, the router may return different values depending on the ABCI message type. For example, it's possible that the `checkTx` does not fully mimic the transaction and simply returns `()`, while the `deliverTx` message returns a value of type `Whois`. Concretely you would write

~~~ haskell ignore
type BuyNameHandler = TypeMessage BuyName :~> Return' 'OnCheckUnit Whois
~~~

or equivalently using the alias

~~~ haskell ignore
type BuyNameHandler = TypeMessage BuyName :~> Return Whois
~~~

Alternatively, you could write the application so that each `checkTx` ABCI message is handled in the same way as the `deliverTx` message, e.g. the both return a value of type `Whois`.


~~~ haskell ignore
type BuyNameHandler = TypeMessage BuyName :~> Return' 'OnCheckEval Whois
~~~


In the case of our actual application, all the transactions return `()` for both `checkTx` and `deliverTx`

## Implementing the Handlers

Similar to the servant style, the types for the handlers must be computed from the type of the router. This requires that you understand what each of the combinators corresponds to, and again this ultimately depends on which `RouteContext` we're in, either `CheckTx` or `DeliverTx`.

Rather than cover all possible cases, we just note that in the case of the Nameservice app we end up with the following server type for the `DeliverTx` context:

~~~ haskell

messageHandlers
  :: Members BaseEffs r
  => Members BankEffs r
  => Members NameserviceEffs r
  => RouteTx MessageApi r 'DeliverTx
messageHandlers = buyNameH :<|> setNameH :<|> deleteNameH

buyNameH
  :: Members BaseEffs r
  => Members TxEffs r
  => Members BankEffs r
  => Members NameserviceEffs r
  => RoutingTx BuyName
  -> Sem r ()
buyNameH (RoutingTx Tx{txMsg=Msg{msgData}}) = do
  incCount "buy_total"
  withTimer "buy_duration_seconds" $ buyName msgData

setNameH
  :: Members BaseEffs r
  => Members TxEffs r
  => Members NameserviceEffs r
  => RoutingTx SetName
  -> Sem r ()
setNameH (RoutingTx Tx{txMsg=Msg{msgData}}) = do
  incCount "set_total"
  withTimer "set_duration_seconds" $ setName msgData

deleteNameH
  :: Members BaseEffs r
  => Members TxEffs r
  => Members BankEffs r
  => Members NameserviceEffs r
  => RoutingTx DeleteName
  -> Sem r ()
deleteNameH (RoutingTx Tx{txMsg=Msg{msgData}}) = do
  incCount "delete_total"
  withTimer "delete_duration_seconds" $ deleteName msgData

  ~~~


[Next: Module](Module.md)
