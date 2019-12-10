module Tendermint.SDK.AuthTreeStore
  ( AuthTree
  , initAuthTree
  , eval
  ) where

import           Control.Concurrent.STM           (atomically)
import           Control.Concurrent.STM.TVar
import           Control.Monad.IO.Class
import qualified Crypto.Data.Auth.Tree            as AT
import qualified Crypto.Data.Auth.Tree.Class      as AT
import qualified Crypto.Data.Auth.Tree.Cryptonite as Cryptonite
import qualified Crypto.Hash                      as Cryptonite
import           Data.ByteString                  (ByteString)
import qualified Data.List.NonEmpty               as NE
import           Polysemy                         (Embed, Member, Sem,
                                                   interpret)
import           Tendermint.SDK.Store             (RawStore (..), StoreKey (..))

-- At the moment, the 'AuthTreeStore' is our only interpreter for the 'RawStore' effect.
-- It is an in memory merklized key value store. You can find the repository here
-- https://github.com/oscoin/avl-auth

newtype AuthTreeHash =  AuthTreeHash (Cryptonite.Digest Cryptonite.SHA256)

instance AT.MerkleHash AuthTreeHash where
    emptyHash = AuthTreeHash Cryptonite.emptyHash
    hashLeaf k v = AuthTreeHash $ Cryptonite.hashLeaf k v
    concatHashes (AuthTreeHash a) (AuthTreeHash b) = AuthTreeHash $ Cryptonite.concatHashes a b

data AuthTree = AuthTree
  { treeVar :: TVar (NE.NonEmpty (AT.Tree ByteString ByteString))
  }

initAuthTree :: IO AuthTree
initAuthTree = AuthTree <$> newTVarIO (pure AT.empty)

eval
  :: Member (Embed IO) r
  => AuthTree
  -> Sem (RawStore ': r) a
  -> Sem r a
eval AuthTree{treeVar} =
  interpret
    (\case
      RawStorePut (StoreKey sk) k v -> liftIO . atomically $ do
        tree NE.:| ts <- readTVar treeVar
        writeTVar treeVar $ AT.insert (sk <> k) v tree NE.:| ts
      RawStoreGet (StoreKey sk) k -> liftIO . atomically $ do
        tree NE.:| _ <- readTVar treeVar
        pure $ AT.lookup (sk <> k) tree
      RawStoreProve _ _ -> pure Nothing
      RawStoreDelete (StoreKey sk) k -> liftIO . atomically $ do
        tree NE.:| ts <- readTVar treeVar
        writeTVar treeVar $ AT.delete (sk <> k) tree NE.:| ts
      RawStoreBeginTransaction -> liftIO . atomically $ do
        tree NE.:| ts <- readTVar treeVar
        writeTVar treeVar $ tree NE.:| tree : ts
      RawStoreRollback -> liftIO . atomically $ do
        trees <- readTVar treeVar
        writeTVar treeVar $ case trees of
          t NE.:| []      -> t NE.:| []
          _ NE.:| t' : ts ->  t' NE.:| ts
      RawStoreCommit -> liftIO . atomically $ do
        trees <- readTVar treeVar
        writeTVar treeVar $ case trees of
          t NE.:| []     -> t NE.:| []
          t NE.:| _ : ts ->  t NE.:| ts
    )