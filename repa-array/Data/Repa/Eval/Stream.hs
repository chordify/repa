{-# LANGUAGE CPP #-}

-- | Evaluation of `Stream`s into bulk arrays.
module Data.Repa.Eval.Stream
        (stream)
where
import Data.Repa.Array.Index                            as A
import Data.Repa.Array.Internals.Flat                   as A
import Data.Repa.Array.Internals.Bulk                   as A
import qualified Data.Vector.Fusion.Stream.Monadic      as S
#include "repa-stream.h"


-- | Convert a `Vector` to a `Stream`.
stream  :: (Monad m, Bulk1 r a)
        => A.Vector r a
        -> S.Stream m a
stream vec
        = S.generate (A.length vec)
                     (\i -> A.index vec (Z :. i))
{-# INLINE_STREAM stream #-}
