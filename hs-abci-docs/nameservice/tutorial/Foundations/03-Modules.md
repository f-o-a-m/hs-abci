---
title: Foundations - Module
---

# Modules and Components

First a note. There is a small technical distinction between a `Module` and a `Component`, but we often use these words interchangeably. A `Component` is simply a type synonym for a partially applied `Module`, which leaves the `r` parameter free. It's basically the type level description of a `Module` that hasn't yet been put in the context of a larger application, which is where the `r` comes in.

## Definition

A `Module` has a very specific meaning in the context of this SDK. A `Module` is something between a library and a small state machine. Here is the type:

~~~ haskell ignore
data Module (name :: Symbol) (check :: *) (deliver :: *) (query :: *) (es :: EffectRow) (deps :: [Component]) (r :: EffectRow) = Module
  { moduleTxChecker :: T.RouteTx check r
  , moduleTxDeliverer :: T.RouteTx deliver r
  , moduleQuerier :: Q.RouteQ query r
  , moduleEval :: forall s. (Members T.TxEffs s, Members (DependencyEffs deps) s) => forall a. Sem (es :& s) a -> Sem s a
  }

~~~

where `DependencyEffs` is a type level function that gathers effect dependencies from a list of `Component`s that the module depends on:

~~~ haskell ignore

type family DependencyEffs (ms :: [Component]) :: EffectRow where
  DependencyEffs '[] = '[]
  DependencyEffs (Module _ _ _ _ es deps ': rest) = es :& DependencyEffs rest
  DependencyEffs _ = TypeError ('Text "DependencyEffs is a partial function defined only on partially applied Modules")

~~~

Let's take a look at the type parameters

- `name` is the name of the module, e.g. `"bank"`.
- `check` is the transaction router api type for `checkTx` messages.
- `deliver` is the transaction router api type for `deliverTx` messages.
- `query` is the query router api type for `query` messages
- `es` is the set of effects introduced by this module.
- `deps` is the list of `Components` (i.e. Modules) that this module depends on, in the sense that the `eval` function for this module will interpret into those effects. (For example, the `BankEffs` for the `Bank` module are interpreted into `AuthEffs`)
- `r` is the global set of effects that this module will run in when part of a larger application (more on this later).

Below that line we see the fields for the `Module` data type, where

  - `moduleTxDeliverer` specifies how the module processes transactions in order to update the application state during `deliverTx` messages.
  - `moduleTxChecker` is used during `checkTx` messages to check if a transaction in the mempool is a valid transaction.
  - `moduleQuerier` is responsible for handling queries for application state from the `query` message.
  - `moduleEval` is the natural transformation that specifies how to interpret the `Module` in terms of `BaseApp`.

If you have ever used the `servant` library for specifying rest apis, then the type families `T.RouteTx` and `Q.RouteQ` may look familiar to you, they play a similar role as `ServerT`.

Note that in the event that a `Module` is _abstract_, meaning it doesn't have any messages to respond to, then we have `msg ~ Void`.

## Composition

`Module`s are meant to be composed to create larger applications. We will see examples of this with the `Nameservice` application. The way to do this is easy, as the `ModuleList` data type allows you to simply combine them in a heterogeneous list:

~~~ haskell ignore
data ModuleList (ms :: [Component]) r where
    NilModules :: Modules '[] r
    (:+) :: Module name check deliver query es r
         -> Modules ms r
         -> Modules (Module name check deliver query es ': ms) r
~~~

When you are ready to create your application, you simply specify a value of type `ModuleList` and some other configuration data, and the SDK will create an `App` for you.
