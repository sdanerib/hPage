
module HPage.Utils.Log where

import Control.Monad.Trans
import Data.Time()
import Data.Time.Clock

data LogLevel = Trace | Debug | Info | Warning | Error | Fatal
    deriving (Show, Eq)

logIO :: Show a => LogLevel -> a -> IO ()
logIO lvl msg = getCurrentTime >>= \ts -> putStrLn $ (show ts) ++ " (" ++ (show lvl) ++ "): " ++ (show msg)

liftLogIO :: (MonadIO m, Show a) => LogLevel -> a -> m ()
liftLogIO _ _ = return () -- lvl = liftIO . (logIO lvl) 

traceIO, debugIO, infoIO, warnIO, errorIO, fatalIO :: Show a => a -> IO ()
liftTraceIO, liftDebugIO, liftInfoIO, liftWarnIO, liftErrorIO, liftFatalIO :: (MonadIO m, Show a) => a -> m ()

{- with(out) log...
traceIO = logIO Trace
debugIO _ = return ()
-}
traceIO _ = return ()
debugIO = logIO Debug
infoIO = logIO Info
warnIO = logIO Warning
errorIO = logIO Error
fatalIO = logIO Fatal

{- without log...
liftTraceIO _ = return () 
liftDebugIO _ = return ()
-}
liftTraceIO = liftLogIO Trace
liftDebugIO = liftLogIO Debug
liftInfoIO = liftLogIO Info
liftWarnIO = liftLogIO Warning
liftErrorIO = liftLogIO Error
liftFatalIO = liftLogIO Fatal