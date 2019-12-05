{-# LANGUAGE TemplateHaskell #-}

module Nameservice.Modules.Nameservice.Keeper where

import           Data.Proxy
import           Data.String.Conversions                  (cs)
import           GHC.TypeLits                             (symbolVal)
import           Nameservice.Modules.Nameservice.Messages
import           Nameservice.Modules.Nameservice.Types
import           Nameservice.Modules.Token                (Token, TokenEffs,
                                                           burn, mint, transfer)
import           Polysemy                                 (Member, Members, Sem,
                                                           interpret, makeSem)
import           Polysemy.Error                           (Error, mapError,
                                                           throw)
import           Polysemy.Output                          (Output)
import           Tendermint.SDK.Errors                    (AppError,
                                                           IsAppError (..))
import           Tendermint.SDK.Events                    (Event, emit)
import qualified Tendermint.SDK.Store                     as Store

data Nameservice m a where
  PutWhois :: Name -> Whois -> Nameservice m ()
  GetWhois :: Name -> Nameservice m (Maybe Whois)
  DeleteWhois :: Name -> Nameservice m ()

makeSem ''Nameservice

type NameserviceEffs = '[Nameservice, Error NameserviceError]

storeKey :: Store.StoreKey NameserviceModule
storeKey = Store.StoreKey . cs . symbolVal $ (Proxy :: Proxy NameserviceModule)

eval
  :: Members [Store.RawStore, Error AppError] r
  => forall a. Sem (Nameservice ': Error NameserviceError ': r) a
  -> Sem r a
eval = mapError makeAppError . evalNameservice
  where
    evalNameservice
      :: Members [Store.RawStore, Error AppError] r
      => Sem (Nameservice ': r) a -> Sem r a
    evalNameservice =
      interpret (\case
          GetWhois name ->
            Store.get storeKey name
          PutWhois name whois ->
            Store.put storeKey name whois
          DeleteWhois name ->
            Store.delete storeKey name
        )

--------------------------------------------------------------------------------

setName
  :: Member (Output Event) r
  => Members NameserviceEffs r
  => SetName
  -> Sem r ()
setName SetName{..} = do
  mwhois <- getWhois setNameName
  case mwhois of
    Nothing -> throw $ UnauthorizedSet "Cannot claim name with SetMessage tx."
    Just currentWhois@Whois{..} ->
      if whoisOwner /= setNameOwner
        then throw $ UnauthorizedSet "Setter must be the owner of the Name."
        else do
          putWhois setNameName currentWhois {whoisValue = setNameValue}
          emit NameRemapped
             { nameRemappedName = setNameName
             , nameRemappedNewValue = setNameValue
             , nameRemappedOldValue = whoisValue
             }

deleteName
  :: Members [Token, Output Event] r
  => Members NameserviceEffs r
  => DeleteName
  -> Sem r ()
deleteName DeleteName{..} = do
  mWhois <- getWhois deleteNameName
  case mWhois of
    Nothing -> throw $ InvalidDelete "Can't remove unassigned name."
    Just Whois{..} ->
      if whoisOwner /= deleteNameOwner
        then throw $ InvalidDelete "Deleter must be the owner."
        else do
          mint deleteNameOwner whoisPrice
          deleteWhois deleteNameName
          emit NameDeleted
            { nameDeletedName = deleteNameName
            }


buyName
  :: Member (Output Event) r
  => Members TokenEffs r
  => Members NameserviceEffs r
  => BuyName
  -> Sem r ()
-- ^ did it succeed
buyName msg = do
  let name = buyNameName msg
  mWhois <- getWhois name
  case mWhois of
    -- The name is unclaimed, go ahead and debit the account
    -- and create it.
    Nothing    -> buyUnclaimedName msg
    -- The name is currently claimed, we will transfer the
    -- funds and ownership
    Just whois -> buyClaimedName msg whois
    where
      buyUnclaimedName
        :: Member (Output Event) r
        => Members TokenEffs r
        => Members NameserviceEffs r
        => BuyName
        -> Sem r ()
      buyUnclaimedName BuyName{..} = do
        burn buyNameBuyer buyNameBid
        let whois = Whois
              { whoisOwner = buyNameBuyer
              , whoisValue = buyNameValue
              , whoisPrice = buyNameBid
              }
        putWhois buyNameName whois
        emit NameClaimed
          { nameClaimedOwner = buyNameBuyer
          , nameClaimedName = buyNameName
          , nameClaimedValue = buyNameValue
          , nameClaimedBid = buyNameBid
          }

      buyClaimedName
        :: Members NameserviceEffs r
        => Members TokenEffs r
        => Member (Output Event) r
        => BuyName
        -> Whois
        -> Sem r ()
      buyClaimedName BuyName{..} currentWhois =
        let Whois{ whoisPrice = forsalePrice, whoisOwner = previousOwner } = currentWhois
        in if buyNameBid > forsalePrice
             then do
               transfer buyNameBuyer buyNameBid previousOwner
               -- update new owner, price and value based on BuyName
               putWhois buyNameName currentWhois { whoisOwner = buyNameBuyer
                                                 , whoisPrice = buyNameBid
                                                 , whoisValue = buyNameValue
                                                 }
               emit NameClaimed
                 { nameClaimedOwner = buyNameBuyer
                 , nameClaimedName = buyNameName
                 , nameClaimedValue = buyNameValue
                 , nameClaimedBid = buyNameBid
                 }
             else throw (InsufficientBid "Bid must exceed the price.")

