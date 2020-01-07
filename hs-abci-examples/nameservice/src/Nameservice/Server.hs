module Nameservice.Server (makeAndServeApplication) where

import           Data.Foldable                                (fold)
import           Data.IORef                                   (writeIORef)
import           Data.Monoid                                  (Endo (..))
import           Nameservice.Application                      (handlersContext)
import           Nameservice.Config                           (AppConfig (..))
import           Network.ABCI.Server                          (serveApp)
import           Network.ABCI.Server.App                      (Middleware)
import qualified Network.ABCI.Server.Middleware.Logger        as Logger
import qualified Network.ABCI.Server.Middleware.MetricsLogger as Met
import           Polysemy                                     (Sem)
import           Tendermint.SDK.Application                   (createIOApp,
                                                               makeApp)
import           Tendermint.SDK.BaseApp                       (Context (..),
                                                               CoreEffs,
                                                               runCoreEffs)
import           Tendermint.SDK.BaseApp.Metrics.Prometheus    (forkMetricsServer)

makeAndServeApplication :: AppConfig -> IO ()
makeAndServeApplication AppConfig{..} = do
  putStrLn "Starting ABCI application..."
  case _contextPrometheusEnv _baseAppContext of
    Nothing            -> pure ()
    Just prometheusEnv -> do
      prometheusThreadId <- forkMetricsServer prometheusEnv
      writeIORef _prometheusServerThreadId (Just prometheusThreadId)
  let nat :: forall a. Sem CoreEffs a -> IO a
      nat = runCoreEffs _baseAppContext
      application = makeApp handlersContext
      middleware :: Middleware (Sem CoreEffs)
      middleware = appEndo . fold $
          [ Endo Logger.mkLoggerM
          , Endo $ Met.mkMetricsLoggerM _serverMetricsMap
          ]
  serveApp $ createIOApp nat (middleware application)
