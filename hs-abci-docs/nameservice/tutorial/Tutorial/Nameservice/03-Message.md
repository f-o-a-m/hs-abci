---
title: Nameservice - Message
---

# Message

## Message Types

Each module is ultimately a small state machine used for processing messages. Each module must define what messages it accepts, if any. Like many other types found in the SDK, this message class must implement the `HasCodec` class. We recommend using a protobuf serialization format for messages using either the `proto3-suite` or `proto-lens` libraries, though in theory you could use anything (e.g. `JSON`).

### `proto3-suite`
The advantages of using the `proto3-suite` library is that it has support for generics and that you can generate a `.proto` file from your haskell code for export to other applications. This is particularly useful when prototyping or when you have control over the message specification.
The disadvantage is that `proto3-suite` doesn't act as a `protoc` plugin, and instead uses it's own protobuf parser. This means that you do not have access to the full protobuf specs when parsing `.proto` files.

### `proto-lens`
The advantages of using `proto-lens` is that it can parse and generate types for pretty much any `.proto` file.
The disadvantage is that the generated code is a bit strange, and may require you to create wrapper types to avoid depending directly on the generated code. An additional disadvantage is that you cannot generate `.proto` files from haskell code.

All in all, neither is really difficult to work with, and depending on what stage you're at in development you might chose one over the other.

## Tutorial.Nameservice.Message

~~~ haskell
module Tutorial.Nameservice.Message where

import Data.Bifunctor (bimap, first)
import Data.Foldable (sequenceA_)
import Data.String.Conversions (cs)
import Data.Text (Text)
import Data.Word (Word64)
import GHC.Generics (Generic)
import Proto3.Suite (Named, Message, fromByteString, toLazyByteString)
import Tendermint.SDK.Types.Address (Address)
import Tendermint.SDK.Types.Message (Msg(..), ValidateMessage(..), HasMessageType(..),
                                     isAuthorCheck, nonEmptyCheck,
                                     coerceProto3Error, formatMessageParseError)
import Tendermint.SDK.Modules.Auth (Amount (..))
import Tendermint.SDK.Modules.Bank ()
import Tendermint.SDK.Codec (HasCodec(..))
~~~

### Message Definitions

For the purposes of the tutorial, we will use the `proto3-suite` for the message codecs. For `BuyName`, an intermediary datatype, `BuyNameMessage` is used to support encoding for `Amount`:


~~~ haskell
data SetNameMsg = SetNameMsg
  { setNameName  :: Text
  , setNameOwner :: Address
  , setNameValue :: Text
  } deriving (Eq, Show, Generic)

instance Message SetNameMsg
instance Named SetNameMsg

instance HasCodec SetNameMsg where
  encode = cs . toLazyByteString
  decode = first (formatMessageParseError . coerceProto3Error) . fromByteString

data DeleteNameMsg = DeleteNameMsg
  { deleteNameOwner :: Address
  , deleteNameName  :: Text
  } deriving (Eq, Show, Generic)

instance Message DeleteNameMsg
instance Named DeleteNameMsg

instance HasCodec DeleteNameMsg where
  encode = cs . toLazyByteString
  decode = first (formatMessageParseError . coerceProto3Error) . fromByteString

data BuyNameMsg = BuyNameMsg
  { buyNameBid   :: Amount
  , buyNameName  :: Text
  , buyNameValue :: Text
  , buyNameBuyer :: Address
  } deriving (Eq, Show)

data BuyNameMessage = BuyNameMessage
  { buyNameMessageBid   :: Word64
  , buyNameMessageName  :: Text
  , buyNameMessageValue :: Text
  , buyNameMessageBuyer :: Address
  } deriving (Eq, Show, Generic)
instance Message BuyNameMessage
instance Named BuyNameMessage

instance HasCodec BuyNameMsg where
  encode BuyNameMsg {..} =
    let buyNameMessage = BuyNameMessage
          { buyNameMessageBid = unAmount buyNameBid
          , buyNameMessageName = buyNameName
          , buyNameMessageValue = buyNameValue
          , buyNameMessageBuyer = buyNameBuyer
          }
    in cs . toLazyByteString $ buyNameMessage
  decode =
    let toBuyName BuyNameMessage {..} = BuyNameMsg
          { buyNameBid = Amount buyNameMessageBid
          , buyNameName = buyNameMessageName
          , buyNameValue = buyNameMessageValue
          , buyNameBuyer = buyNameMessageBuyer
          }
    in bimap (formatMessageParseError . coerceProto3Error) toBuyName
       . fromByteString @BuyNameMessage
~~~

As `protobuf` is a schemaless format, parsing is sometimes ambiguous if two types are the same up to field names, or one is a subset of the other. For this reason we use the type class `HasMessageType`

~~~ haskell ignore
class HasMessageType msg where
  messageType :: Proxy msg -> Text
~~~

to associate each message to a tag to assist in parsing. So for example, we can implement this class for our message types as

~~~ haskell

instance HasMessageType SetNameMsg where
  messageType _ = "SetName"

instance HasMessageType DeleteNameMsg where
  messageType _ = "DeleteName"

instance HasMessageType BuyNameMsg where
  messageType _ = "BuyName"
~~~


## Message Validation

Message validation is an important part of the transaction life cycle. When a `checkTx` message comes in, Tendermint is asking whether a transaction bytestring from the mempool is potentially runnable. At the very least this means that

1. The transaction parses to a known message
2. The message passes basic signature authentication, if any is required.
3. The message author has enough funds for the gas costs, if any.
4. The message can be successfully routed to a module without handling.

On top of this you might wish to ensure other static properties of the message, such as, that the author of the message is the owner of the funds being transferred. For this we have a `ValidateMessage` class:

~~~ haskell ignore
data MessageSemanticError =
    PermissionError Text
  | InvalidFieldError Text
  | OtherSemanticError Text

class ValidateMessage msg where
  validateMessage :: Msg msg -> Validation [MessageSemanticError] ()
~~~

We're using the applicative functor [`Data.Validation.Validation`](https://hackage.haskell.org/package/validation-1.1/docs/Data-Validation.html#t:Validation) to perform validation because it is capable of reporting all errors at once, rather than the first that occurs as in the case with something like `Either`.

Here's what the `isAuthor` check looks like, that was described above:

~~~ haskell ignore
isAuthorCheck
  :: Text
  -> Msg msg
  -> (msg -> Address)
  -> V.Validation [MessageSemanticError] ()
isAuthorCheck fieldName Msg{msgAuthor, msgData} getAuthor
  | getAuthor msgData /= msgAuthor =
      _Failure # [PermissionError $ fieldName <> " must be message author."]
  | otherwise = Success ()
~~~

It is also possible to run dynamic checks on the transaction, i.e. checks that need to query state in order to succeed or fail. We will say more on this later.

Here are the validation instances for our message types, which use some of the combinators defined in the SDK

~~~ haskell
instance ValidateMessage SetNameMsg where
  validateMessage msg@Msg{..} =
    let SetNameMsg{setNameName, setNameValue} = msgData
    in sequenceA_
        [ nonEmptyCheck "Name" setNameName
        , nonEmptyCheck "Value" setNameValue
        , isAuthorCheck "Owner" msg setNameOwner
        ]

instance ValidateMessage DeleteNameMsg where
  validateMessage msg@Msg{..} =
    let DeleteNameMsg{deleteNameName} = msgData
    in sequenceA_
       [ nonEmptyCheck "Name" deleteNameName
       , isAuthorCheck "Owner" msg deleteNameOwner
       ]

instance ValidateMessage BuyNameMsg where
  validateMessage msg@Msg{..} =
    let BuyNameMsg{buyNameName, buyNameValue} = msgData
    in sequenceA_
        [ nonEmptyCheck "Name" buyNameName
        , nonEmptyCheck "Value" buyNameValue
        , isAuthorCheck "Owner" msg buyNameBuyer
        ]
~~~
