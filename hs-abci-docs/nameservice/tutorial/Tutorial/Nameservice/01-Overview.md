---
title: Nameservice - Overview
---

# Overview

This section is where we sketch the definition of the Nameservice module and application. It's to everyone's benefit if module structures follow a similar file hierarchy as the Nameservice module, or any module found in the SDK. In the case of Nameservice this roughly translates to

```
├── Nameservice
  │   ├── Keeper.hs
  │   ├── Messages.hs
  │   ├── Query.hs
  │   ├── Router.hs
  │   └── Types.hs
  ├── Nameservice.hs

```

The contents of these modules are roughly as follows:

- `Nameservice.Types` - Core types and instances for the module, including events, custom errors, database types.
- `Nameservice.Keeper` - Defines the module's effect system, it's database operations (if  any), core utility.
- `Nameservice.Message` - Defines the message types that the module must process (if any) and their validation instances.
- `Nameservice.Query` - Defines the query server for handling state queries from clients.
- `Nameservice.Router` - Defines the transaction router for the module.
- `Nameservice` Defines the module itself and re-exports any types or utils necessary for using this module as a dependency.

The reason why we suggest this is that each of these haskell modules is building up one of the core components of our definition of a module, and it provides a nice logical split between these pieces.
