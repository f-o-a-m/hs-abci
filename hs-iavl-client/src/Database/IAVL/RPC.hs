module Database.IAVL.RPC where

import           Data.ProtoLens.Message       (defMessage)
import           Network.GRPC.Client          (RawReply)
import           Network.GRPC.Client.Helpers  (GrpcClient, rawUnary)
import           Network.GRPC.HTTP2.ProtoLens (RPC (..))
import           Network.HTTP2.Client         (ClientIO, TooMuchConcurrency)

import qualified Proto.Google.Protobuf.Empty  as PT (Empty)
import qualified Proto.Iavl.Api               as Api


--------------------------------------------------------------------------------
-- | get
--------------------------------------------------------------------------------
get
  :: GrpcClient
  -> Api.GetRequest
  -> ClientIO (Either TooMuchConcurrency (RawReply Api.GetResponse))
get = rawUnary (RPC :: RPC Api.IAVLService "get")

--------------------------------------------------------------------------------
-- | getVersioned
--------------------------------------------------------------------------------
getVersioned
  :: GrpcClient
  -> Api.GetVersionedRequest
  -> ClientIO (Either TooMuchConcurrency (RawReply Api.GetResponse))
getVersioned = rawUnary (RPC :: RPC Api.IAVLService "getVersioned")

--------------------------------------------------------------------------------
-- | getVersionededWithProof
--------------------------------------------------------------------------------
getVersionedWithProof
  :: GrpcClient
  -> Api.GetVersionedRequest
  -> ClientIO (Either TooMuchConcurrency (RawReply Api.GetWithProofResponse))
getVersionedWithProof = rawUnary (RPC :: RPC Api.IAVLService "getVersionedWithProof")

--------------------------------------------------------------------------------
-- | getWithProof
--------------------------------------------------------------------------------
getWithProof
  :: GrpcClient
  -> Api.GetRequest
  -> ClientIO (Either TooMuchConcurrency (RawReply Api.GetWithProofResponse))
getWithProof = rawUnary (RPC :: RPC Api.IAVLService "getWithProof")

--------------------------------------------------------------------------------
-- | set
--------------------------------------------------------------------------------
set
  :: GrpcClient
  -> Api.SetRequest
  -> ClientIO (Either TooMuchConcurrency (RawReply Api.SetResponse))
set = rawUnary (RPC :: RPC Api.IAVLService "set")

--------------------------------------------------------------------------------
-- | remove
--------------------------------------------------------------------------------
remove
  :: GrpcClient
  -> Api.RemoveRequest
  -> ClientIO (Either TooMuchConcurrency (RawReply Api.RemoveResponse))
remove = rawUnary (RPC :: RPC Api.IAVLService "remove")

--------------------------------------------------------------------------------
-- | saveVersion
--------------------------------------------------------------------------------
saveVersion
  :: GrpcClient
  -> ClientIO (Either TooMuchConcurrency (RawReply Api.SaveVersionResponse))
saveVersion gc = rawUnary (RPC :: RPC Api.IAVLService "saveVersion") gc defMessage

--------------------------------------------------------------------------------
-- | deleteVersion
--------------------------------------------------------------------------------
deleteVersion
  :: GrpcClient
  -> Api.DeleteVersionRequest
  -> ClientIO (Either TooMuchConcurrency (RawReply Api.DeleteVersionResponse))
deleteVersion = rawUnary (RPC :: RPC Api.IAVLService "deleteVersion")

--------------------------------------------------------------------------------
-- | version
--------------------------------------------------------------------------------
version
  :: GrpcClient
  -> ClientIO (Either TooMuchConcurrency (RawReply Api.VersionResponse))
version gc = rawUnary (RPC :: RPC Api.IAVLService "version") gc defMessage

--------------------------------------------------------------------------------
-- | hash
--------------------------------------------------------------------------------
hash
  :: GrpcClient
  -> ClientIO (Either TooMuchConcurrency (RawReply Api.HashResponse))
hash gc = rawUnary (RPC :: RPC Api.IAVLService "hash") gc defMessage

--------------------------------------------------------------------------------
-- | versionExists
--------------------------------------------------------------------------------
versionExists
  :: GrpcClient
  -> Api.VersionExistsRequest
  -> ClientIO (Either TooMuchConcurrency (RawReply Api.VersionExistsResponse))
versionExists = rawUnary (RPC :: RPC Api.IAVLService "versionExists")

--------------------------------------------------------------------------------
-- | verify
--------------------------------------------------------------------------------
verify
  :: GrpcClient
  -> Api.VerifyRequest
  -> ClientIO (Either TooMuchConcurrency (RawReply PT.Empty))
verify = rawUnary (RPC :: RPC Api.IAVLService "verify")

--------------------------------------------------------------------------------
-- | verifyItem
--------------------------------------------------------------------------------
verifyItem
  :: GrpcClient
  -> Api.VerifyItemRequest
  -> ClientIO (Either TooMuchConcurrency (RawReply PT.Empty))
verifyItem = rawUnary (RPC :: RPC Api.IAVLService "verifyItem")

--------------------------------------------------------------------------------
-- | verifyAbsence
--------------------------------------------------------------------------------
verifyAbsence
  :: GrpcClient
  -> Api.VerifyAbsenceRequest
  -> ClientIO (Either TooMuchConcurrency (RawReply PT.Empty))
verifyAbsence = rawUnary (RPC :: RPC Api.IAVLService "verifyAbsence")

--------------------------------------------------------------------------------
-- | rollback
--------------------------------------------------------------------------------
rollback
  :: GrpcClient
  -> ClientIO (Either TooMuchConcurrency (RawReply PT.Empty))
rollback gc = rawUnary (RPC :: RPC Api.IAVLService "rollback") gc defMessage

--------------------------------------------------------------------------------
-- | has
--------------------------------------------------------------------------------
has
  :: GrpcClient
  -> Api.HasRequest
  -> ClientIO (Either TooMuchConcurrency (RawReply Api.HasResponse))
has = rawUnary (RPC :: RPC Api.IAVLService "has")

--------------------------------------------------------------------------------
-- | has_versioned
--------------------------------------------------------------------------------
hasVersioned
  :: GrpcClient
  -> Api.HasVersionedRequest
  -> ClientIO (Either TooMuchConcurrency (RawReply Api.HasResponse))
hasVersioned = rawUnary (RPC :: RPC Api.IAVLService "hasVersioned")
