
module Data.Repa.Query.Source.Compounds
        ( xVar, xLam, xOp

        , makeScalarOp0
        , makeScalarOp1
        , makeScalarOp2
        , makeScalarOp3
        , makeScalarOp4
        , makeScalarOp5)
where
import Data.Repa.Query.Source.Builder
import qualified Data.Repa.Query.Graph          as G


xVar i          = G.XVar () i
xLam x          = G.XVal () (G.VLam () () x)
xOp s args      = G.XOp  () s args


makeScalarOp0
        :: G.ScalarOp 
        -> Value a
makeScalarOp0 sop
        = Value $ xOp sop []


makeScalarOp1 
        :: G.ScalarOp 
        -> Value a 
        -> Value b
makeScalarOp1 sop (Value x)
        = Value $ xOp sop [x]


makeScalarOp2 
        :: G.ScalarOp 
        -> Value a -> Value b 
        -> Value c
makeScalarOp2 sop (Value x1) (Value x2)
        = Value $ xOp sop [x1, x2]


makeScalarOp3
        :: G.ScalarOp
        -> Value a -> Value b -> Value c
        -> Value d
makeScalarOp3 sop (Value x1) (Value x2) (Value x3)
        = Value $ xOp sop [x1, x2, x3]


makeScalarOp4
        :: G.ScalarOp
        -> Value a -> Value b -> Value c -> Value d
        -> Value e
makeScalarOp4 sop (Value x1) (Value x2) (Value x3) (Value x4)
        = Value $ xOp sop [x1, x2, x3, x4]


makeScalarOp5
        :: G.ScalarOp
        -> Value a -> Value b -> Value c -> Value d -> Value e
        -> Value f
makeScalarOp5 sop (Value x1) (Value x2) (Value x3) (Value x4) (Value x5)
        = Value $ xOp sop [x1, x2, x3, x4, x5]
