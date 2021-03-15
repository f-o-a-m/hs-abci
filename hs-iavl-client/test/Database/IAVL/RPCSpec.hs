module Database.IAVL.RPCSpec (spec) where

import           Control.Lens            ((&), (.~), (^.), (^?), _Left, _Right)
import           Control.Monad           (void)
import           Data.ProtoLens.Message  (defMessage)
import           Database.IAVL.RPC
import           Database.IAVL.RPC.Types
import           Network.GRPC.Client     (RawReply)
import           Network.HTTP2.Client    (ClientIO, TooMuchConcurrency,
                                          runClientIO)
import qualified Proto.Iavl.Api_Fields   as Api
import           Test.Hspec

spec :: Spec
spec = beforeAll (initGrpcClient $ GrpcConfig "0.0.0.0" 8090) $ do
  let testKey = "test-key"
      testValue = "test-value"
      testKey2 = "test-key-2"
      testValue2 = "test-value-2"
      emptyHash = "\227\176\196B\152\252\FS\DC4\154\251\244\200\153o\185$'\174A\228d\155\147L\164\149\153\ESCxR\184U"
      rootWithTestKey = "`\241\167\226\242u\194\221L!\200\202\159\232\131\\\ESC\ESC\158wZ\164yw\248\194jW\145:\206\209"
  describe "IAVL RPC calls" $ do

    it "should call `hash` RPC method on empty Iavl store and get empty root hash" $ \gc -> do
      res <- runGrpc $ hash gc
      res ^? _Right . Api.rootHash `shouldBe` Just emptyHash

    it "should call `set` RPC method and get false as result since it does not already exist" $ \gc -> do
      let setReq = defMessage & Api.key .~ testKey
                              & Api.value .~ testValue
      res <- runGrpc $ set gc setReq
      res ^? _Right . Api.result `shouldBe` Just False

    it "should call `get` RPC method and get the expected value" $ \gc -> do
      let getReq = defMessage & Api.key .~ testKey
      res <- runGrpc $ get gc getReq
      res ^? _Right . Api.value `shouldBe` Just testValue
      res ^? _Right . Api.index `shouldBe` Just 0

    it "should call `get` RPC method on a newly set key and get the expected value and index" $ \gc -> do
      let setReq = defMessage & Api.key .~ testKey2
                              & Api.value .~ testValue2
      sres <- runGrpc $ set gc setReq
      sres ^? _Right . Api.result `shouldBe` Just False

      let getReq = defMessage & Api.key .~ testKey2
      gres <- runGrpc $ get gc getReq
      gres ^? _Right . Api.value `shouldBe` Just testValue2
      gres ^? _Right . Api.index `shouldBe` Just 1

    it "should call `get` RPC method and fail to get the expected value" $ \gc -> do
      let getReq = defMessage & Api.key .~ "non-existing-key"
      res <- runGrpc $ get gc getReq
      res ^? _Left `shouldBe` Just "the key requested does not exist"

    it "should call `saveVersion` RPC method and get the latest hash" $ \gc -> do
      _ <- runGrpc $ saveVersion gc
      res <- runGrpc $ hash gc
      res ^? _Right .  Api.rootHash `shouldBe` Just rootWithTestKey

    it "should call `getWithProof` RPC method and get value from earlier version" $ \gc -> do
      let getReq = defMessage & Api.key .~ testKey
      getRes <- runGrpc $ getWithProof gc getReq
      getRes ^? _Right . Api.value `shouldBe` Just testValue

    it "should call `getVersioned` RPC method and get value from earlier version" $ \gc -> do
      let newVal = "new-value"
          setReq = defMessage & Api.key .~ testKey
                              & Api.value .~ newVal
      res <- runGrpc $ set gc setReq
      res ^? _Right . Api.result `shouldBe` Just True
      _ <- runGrpc $ saveVersion gc

      let getReq = defMessage & Api.key .~ testKey
                              & Api.version .~ 1
      getRes <- runGrpc $ getVersioned gc getReq
      getRes ^? _Right . Api.value `shouldBe` Just testValue

    it "should call `getVersionedWithProof` RPC method and get value from earlier version" $ \gc -> do
      let newVal = "new-value-2"
          setReq = defMessage & Api.key .~ testKey
                              & Api.value .~ newVal
      res <- runGrpc $ set gc setReq
      res ^? _Right . Api.result `shouldBe` Just True
      _ <- runGrpc $ saveVersion gc

      let getReq = defMessage & Api.key .~ testKey
                              & Api.version .~ 1
      getRes <- runGrpc $ getVersionedWithProof gc getReq
      getRes ^? _Right . Api.value `shouldBe` Just testValue

    it "should call `remove` RPC method" $ \gc -> do
      let key = "key-to-remove"
          value = "value-to-remove"
          setReq = defMessage & Api.key .~ key
                              & Api.value .~ value
      res <- runGrpc $ set gc setReq
      res ^? _Right . Api.result `shouldBe` Just False
      _ <- runGrpc $ saveVersion gc

      let removeReq = defMessage & Api.key .~ key
      removeRes <- runGrpc $ remove gc removeReq
      removeRes ^? _Right . Api.value `shouldBe` Just value

      let getReq = defMessage & Api.key .~ key
      getRes <- runGrpc $ get gc getReq
      getRes ^? _Left `shouldBe` Just "the key requested does not exist"

    it "should call `verify` RPC method" $ \gc -> do
      let getReq = defMessage & Api.key .~ testKey
                              & Api.version .~ 1
      egetRes <- runGrpc $ getVersionedWithProof gc getReq

      getRes <- case egetRes of
        Right a -> pure a
        Left err -> fail err


      let verifyReq = defMessage & Api.rootHash .~ rootWithTestKey
                                 & Api.proof .~ (getRes ^. Api.proof)
      void . runGrpc $ verify gc verifyReq


    it "should call `verifyItem` RPC method" $ \gc -> do
      let getReq = defMessage & Api.key .~ testKey
                              & Api.version .~ 1
      egetRes <- runGrpc $ getVersionedWithProof gc getReq

      getRes <- case egetRes of
        Right a -> pure a
        Left err -> fail err

      let verifyReq = defMessage & Api.rootHash .~ rootWithTestKey
                                 & Api.proof .~ (getRes ^. Api.proof)
                                 & Api.key .~ testKey
                                 & Api.value .~ testValue
      void . runGrpc $ verifyItem gc verifyReq


    it "should call `verifyAbsence` RPC method" $ \gc -> do
      let getReq = defMessage & Api.key .~ testKey
                              & Api.version .~ 1
      egetRes <- runGrpc $ getVersionedWithProof gc getReq

      getRes <- case egetRes of
        Right a -> pure a
        Left err -> fail err


      let verifyAbReq = defMessage & Api.rootHash .~ rootWithTestKey
                                   & Api.proof .~ (getRes ^. Api.proof)
                                   & Api.key .~ "non-existing key"
      void . runGrpc $ verifyAbsence gc verifyAbReq

    it "should call `versionExists` RPC method on existing version" $ \gc -> do
      let verExistsReq = defMessage & Api.version .~ 1
      verExistsRes <- runGrpc $ versionExists gc verExistsReq
      verExistsRes ^? _Right . Api.result `shouldBe` Just True

    it "should call `version` RPC method and get latest version number" $ \gc -> do
      verRes <- runGrpc $ version gc
      verRes ^? _Right . Api.version `shouldBe` Just 4

    it "should call `versionExists` RPC method on non-existing version" $ \gc -> do
      let verExistsReq = defMessage & Api.version .~ 25
      verExistsRes <- runGrpc $ versionExists gc verExistsReq
      verExistsRes ^? _Right . Api.result `shouldBe` Just False

    it "should call `has` RPC method" $ \gc -> do
      let hasReq = defMessage & Api.key .~ testKey
                              & Api.version .~ 1
      hasRes <- runGrpc $ hasVersioned gc hasReq
      hasRes ^? _Right . Api.result `shouldBe` Just True

    it "should call `has` RPC method and fail" $ \gc -> do
      let hasReq = defMessage & Api.key .~ "non-existing-key"
                              & Api.version .~ 1
      hasRes <- runGrpc $ hasVersioned gc hasReq
      hasRes ^? _Right . Api.result `shouldBe` Just False

    it "should call `deleteVersion` RPC method and get False for non-existing version" $ \gc -> do
      let delVerReq = defMessage & Api.version .~ 1
      let verExistsReq = defMessage & Api.version .~ 1
      delVerRes <- runGrpc $ deleteVersion gc delVerReq
      verExistsRes <- runGrpc $ versionExists gc verExistsReq
      delVerRes ^? _Right . Api.rootHash `shouldBe` Just rootWithTestKey
      verExistsRes ^? _Right . Api.result `shouldBe` Just False

    it "should call `rollback` RPC method without changing the version" $ \gc -> do
      verRes <- runGrpc $ version gc
      let oldVersion = verRes ^? _Right . Api.version

      _ <- runGrpc $ rollback gc

      verRes' <- runGrpc $ version gc
      let newVersion = verRes' ^? _Right . Api.version

      oldVersion `shouldBe` newVersion

    it "should call `rollback` RPC method" $ \gc -> do
      let key = "key-with-rollback"
          value = "value-with-rollback"
          setReq = defMessage & Api.key .~ key
                              & Api.value .~ value
      res <- runGrpc $ set gc setReq
      res ^? _Right . Api.result `shouldBe` Just False

      let getReq = defMessage & Api.key .~ key
      getRes <- runGrpc $ get gc getReq
      getRes ^? _Right . Api.value `shouldBe` Just value
      getRes ^? _Right . Api.index `shouldBe` Just 1

      _ <- runGrpc $ rollback gc

      getRes' <- runGrpc $ get gc getReq
      getRes' ^? _Left `shouldBe` Just "the key requested does not exist"

    it "should call `has` RPC method on current working tree" $ \gc -> do
      let key = "key-has"
          value = "value-has"
          setReq = defMessage & Api.key .~ key
                              & Api.value .~ value
      res <- runGrpc $ set gc setReq
      res ^? _Right . Api.result `shouldBe` Just False
      everRes <- runGrpc $ version gc
      verRes <- case everRes of
        Right a -> pure a
        Left e -> fail e

      let currentVersion = verRes ^. Api.version
          hasReq = defMessage & Api.key .~ key
                              & Api.version .~ currentVersion
      print $ "The current version is " <> show currentVersion
      hasRes <- runGrpc $ hasVersioned gc hasReq
      hasRes ^? _Right . Api.result `shouldBe` Just False


runGrpc :: ClientIO (Either TooMuchConcurrency (RawReply a)) -> IO (Either String a)
runGrpc f = runClientIO f >>= \case
  Right (Right (Right (_, _, Right res))) -> pure $ Right res
  Right (Right (Right (_, _, Left err))) -> pure $ Left err
  Right (Right (Left err)) -> error ("Error running grpc call (2): " <> show err)
  Right (Left err) -> error ("Error running grpc call (3): " <> show err)
  Left err -> error ("Error running grpc call (4): " <> show err)
