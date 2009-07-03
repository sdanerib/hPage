
module Language.Haskell.Interpreter.Server (
    start, runIn, asyncRunIn, ServerHandle
    ) where

import Control.Concurrent.MVar
import Control.Monad.Error
import Control.Concurrent.Process
import Language.Haskell.Interpreter

newtype ServerHandle = SH {handle :: Handle (InterpreterT IO ())}

start :: IO ServerHandle
start = (spawn $ makeProcess runInterpreter interpreter) >>= return . SH
    where interpreter =
            do
                setImports ["Prelude"]
                forever $ recv >>= lift

asyncRunIn :: ServerHandle -> InterpreterT IO a -> IO (MVar (Either InterpreterError a))
asyncRunIn server action = do
                                resVar <- liftIO newEmptyMVar
                                sendTo (handle server) (try action >>= liftIO . putMVar resVar)
                                return resVar

runIn :: ServerHandle -> InterpreterT IO a -> IO (Either InterpreterError a)
runIn server action = runHere $ do
                                    me <- self
                                    sendTo (handle server) $ try action >>= sendTo me
                                    recv

try :: InterpreterT IO b -> InterpreterT IO (Either InterpreterError b)
try a = (a >>= return . Right) `catchError` (return . Left)