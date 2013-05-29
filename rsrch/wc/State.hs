
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module State(
    State, runState, evalState, execState, mapState, withState,
    StateT, runStateT, evalStateT, execStateT, mapStateT, withStateT,
    module Control.Monad.State.Class,
    )  where

import Control.Monad.State.Class

data State s a = State {
    runState :: (s -> (a, s))
}

evalState :: State s a -> s -> a
evalState m s = fst (runState m s)

execState :: State s a -> s -> s
execState m s = snd (runState m s)

mapState :: ((a, s) -> (b, s)) -> State s a -> State s b
mapState f m = State $ f . runState m

withState :: (s -> s) -> State s a -> State s a
withState f m = State $ runState m . f

instance Monad (State s) where
    fail = error
    return x = State $ \s -> (x, s)
    (>>=) x f = State $ \s ->   
        case runState x s of
            (a, s') -> runState (f a) s'
    (>>) x y = x >>= (\_ -> y)

instance MonadState s (State s) where
    get = State $ \s -> (s, s)
    put s = State $ \_ -> ((), s)


data StateT s m a = StateT {
    runStateT :: s -> m (a, s)
}

evalStateT :: (Monad m) => StateT s m a -> s -> m a
evalStateT m s = do
    (a, _) <- runStateT m s
    return a

execStateT :: (Monad m) => StateT s m a -> s -> m s
execStateT m s = do
    (_, s') <- runStateT m s
    return s'

mapStateT :: (m (a, s) -> n (b, s)) -> StateT s m a -> StateT s n b
mapStateT f m = StateT $ f . runStateT m

withStateT :: (s -> s) -> StateT s m a -> StateT s m a
withStateT f m = StateT $ runStateT m . f

instance (Monad m) => Monad (StateT s m) where
    return a = StateT $ \s -> return (a, s)
    (>>=) m k = StateT $ \s -> do
        (a, s') <- runStateT m s
        runStateT (k a) s'
    (>>) a b = a >>= (\_ -> b)
    fail str = StateT $ \_ -> fail str

instance (Monad m) => MonadState s (StateT s m) where
    get = StateT $ \s -> return (s, s)
    put s = StateT $ \_ -> return ((), s)


