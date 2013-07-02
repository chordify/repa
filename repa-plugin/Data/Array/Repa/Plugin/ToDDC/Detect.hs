
module Data.Array.Repa.Plugin.ToDDC.Detect
        (detectModule)
where
import Data.Array.Repa.Plugin.FatName
import Data.Array.Repa.Plugin.ToDDC.Detect.Base
import Data.Array.Repa.Plugin.ToDDC.Detect.Type  ()

import DDC.Core.Module
import DDC.Core.Collect
import DDC.Type.Env
import DDC.Core.Flow
import DDC.Core.Flow.Exp
import DDC.Core.Flow.Prim
import DDC.Core.Flow.Compounds
import DDC.Core.Transform.Annotate
import DDC.Core.Transform.Deannotate

import Control.Monad.State.Strict

import qualified Data.Map       as Map
import Data.Map                 (Map)
import qualified Data.Set       as Set
import Data.List


detectModule 
        :: Module  () FatName 
        -> (Module () Name, Map Name GhcName)

detectModule mm
 = let  (mm', state')    = runState (detect mm) $ zeroState
   in   (mm', stateNames state')



-- Module ---------------------------------------------------------------------
instance Detect (Module ()) where
 detect mm
  = do  body'   <- liftM (annotate ()) 
                $  detect     (deannotate (const Nothing) $ moduleBody mm)
        importK <- detectMap  (moduleImportKinds mm)
        importT <- detectMap  (moduleImportTypes mm)

        -- Limit the import types to free vars in body:
        -- This cleans up the dump a little, but I'm actually doing it because I was getting 
        -- "$fUnbox(,) :: ... Vector# Vector# (Tuple2# a_aPj b_aPk) -> ..."
        -- which is a kind error.
        let free     = freeX empty body'
            importT' = Map.filterWithKey (\k _ -> Set.member (UName k) free) importT

        return  $ ModuleCore
                { moduleName            = moduleName mm
                , moduleExportKinds     = Map.empty
                , moduleExportTypes     = Map.empty
                , moduleImportKinds     = importK
                , moduleImportTypes     = importT'
                , moduleBody            = body' }

-- Convert the FatNames of an import map
detectMap  :: Map FatName (QualName FatName, Type FatName)
           -> State DetectS (Map Name (QualName Name, Type Name))
detectMap  m
 = do   let ms = Map.toList   m
        ms'   <- mapM detect' ms
        return $ Map.fromList ms'
 where
  detect' (FatName _ k,(QualName mn (FatName _ n), t))
   = do t' <- detect t
        return (k, (QualName mn n, t'))


-- DaCon ----------------------------------------------------------------------
instance Detect DaCon where
 detect (DaCon dcn t isAlg)
  = do  dcn'    <- detect dcn
        t'      <- detect t
        return  $  DaCon dcn' t' isAlg


instance Detect DaConName where
 detect dcn
  = case dcn of
        DaConUnit       
         -> return DaConUnit

        -- Booleans
        DaConNamed (FatName g d@(NameCon v))
         | isPrefixOf "True_" v
         -> do  collect d g
                return $ DaConNamed (NameLitBool True)
        DaConNamed (FatName g d@(NameCon v))
         | isPrefixOf "False_" v
         -> do  collect d g
                return $ DaConNamed (NameLitBool False)

        -- HACK Why is this NameVar, and the booleans above NameCon?
        -- I really don't know.
        DaConNamed (FatName g d@(NameVar v))
         | isPrefixOf "(,)_" v
         -> do  collect d g
                return $ DaConNamed (NameDaConFlow (DaConFlowTuple 2))

        DaConNamed (FatName g d)
         -> do  collect d g
                return $ DaConNamed d


-- Exp ------------------------------------------------------------------------
instance Detect (Exp a) where
 detect xx
  | XAnnot a x          <- xx
  = liftM (XAnnot a) $ detect x

  -- Set kind of detected rate variables to Rate.
  | XLam b x          <- xx
  = do  b'      <- detect b
        x'      <- detect x
        case b' of
         BName n _
          -> do rateVar <- isRateVar n
                if rateVar 
                 then return $ XLAM (BName n kRate) x'
                 else return $ XLam b' x'

         _ -> error "repa-plugin.detect[Exp] no match"

  -- Detect vectorOfSeries
  | XApp{}                              <- xx
  , Just  (XVar u,     [xTK, xTA, _xD, xS]) 
                                        <- takeXApps xx
  , UName (FatName _ (NameVar v))       <- u
  , isPrefixOf "toVector_" v
  = do  args'   <- mapM detect [xTK, xTA, xS]
        return  $ xApps (XVar (UPrim (NameOpFlow OpFlowVectorOfSeries)
                                     (typeOpFlow OpFlowVectorOfSeries)))
                          args'

  -- Detect folds.
  | XApp{}                              <- xx
  , Just  (XVar uFold, [xTK, xTA, xTB, _xD, xF, xZ, xS])    
                                        <- takeXApps xx
  , UName (FatName _ (NameVar vFold))   <- uFold
  , isPrefixOf "fold_" vFold
  = do  args'   <- mapM detect [xTK, xTA, xTB, xF, xZ, xS]
        return  $  xApps (XVar (UPrim (NameOpFlow OpFlowFold) 
                                      (typeOpFlow OpFlowFold)))
                         args'

  -- foldIndex
  | XApp{}                              <- xx
  , Just  (XVar uFold, [xTK, xTA, xTB, _xD, xF, xZ, xS])    
                                        <- takeXApps xx
  , UName (FatName _ (NameVar vFold))   <- uFold
  , isPrefixOf "foldIndex_" vFold
  = do  args'   <- mapM detect [xTK, xTA, xTB, xF, xZ, xS]
        return  $  xApps (XVar (UPrim (NameOpFlow OpFlowFoldIndex) 
                                      (typeOpFlow OpFlowFoldIndex)))
                         args'


  -- Detect maps
  | XApp{}                              <- xx
  , Just  (XVar uMap,  [xTK, xTA, xTB, _xD1, _xD2, xF, xS ])
                                        <- takeXApps xx
  , UName (FatName _ (NameVar vMap))    <- uMap
  , isPrefixOf "map_" vMap
  = do  args'   <- mapM detect [xTK, xTA, xTB, xF, xS]
        return  $ xApps (XVar (UPrim (NameOpFlow (OpFlowMap 1))
                                     (typeOpFlow (OpFlowMap 1))))
                        args'

  -- TODO mapN
  | XApp{}                              <- xx
  , Just  (XVar uMap,  [xTK, xTA, xTB, xTC, _xD1, _xD2, _xD3, xF, xS1, xS2 ])
                                        <- takeXApps xx
  , UName (FatName _ (NameVar vMap))    <- uMap
  , isPrefixOf "map2_" vMap
  = do  args'   <- mapM detect [xTK, xTA, xTB, xTC, xF, xS1, xS2]
        return  $ xApps (XVar (UPrim (NameOpFlow (OpFlowMap 2))
                                     (typeOpFlow (OpFlowMap 2))))
                        args'

  -- Detect packs
  | XApp{}                              <- xx
  , Just  (XVar uPack,  [xTK1, xTK2, xTA, _xD1, xSel, xF])
                                        <- takeXApps xx
  , UName (FatName _ (NameVar vPack))   <- uPack
  , isPrefixOf "pack_" vPack
  = do  args'   <- mapM detect [xTK1, xTK2, xTA, xSel, xF]
        return  $ xApps (XVar (UPrim (NameOpFlow OpFlowPack)
                                     (typeOpFlow OpFlowPack)))
                        args'

  -- Detect mkSels
  | XApp{}                              <- xx
  , Just  (XVar u,    [xTK, xTA, xFlags, xWorker])
                                        <- takeXApps xx
  , UName (FatName _ (NameVar v))       <- u
  , isPrefixOf "mkSel1_" v
  = do  args'   <- mapM detect [xTK, xTA, xFlags, xWorker]
        return  $ xApps (XVar (UPrim (NameOpFlow (OpFlowMkSel 1))
                                     (typeOpFlow (OpFlowMkSel 1))))
                        args'

  -- Detect n-tuples
  | XApp{}                              <- xx
  , Just  (XVar uTuple,  args)          <- takeXApps xx
  , UName (FatName _ (NameVar vTuple))  <- uTuple

  , size                                <- length args `div` 2
  , commas                              <- replicate (size-1) ','
  , prefix                              <- "(" ++ commas ++ ")_"

  , size > 1
  , isPrefixOf prefix vTuple
  = do  args'   <- mapM detect args
        let tuple = DaConFlowTuple size
            ty    = typeDaConFlow tuple
        return  $ xApps (XCon $ mkDaConAlg (NameDaConFlow tuple) ty)
                        args'



  -- Inject type arguments for arithmetic ops.
  --   In the Core code, arithmetic operations are expressed as monomorphic
  --   dictionary methods, which we convert to polytypic DDC primops.
  | XVar (UName (FatName nG (NameVar str)))    <- xx
  , Just (nD', tArg, tPrim)  <- matchPrimArith str
  = do  collect nD' nG
        return  $ xApps (XVar (UPrim nD' tPrim)) [XType tArg]


  -- Strip boxing constructors from literal values.
  | XApp (XVar (UName (FatName _ (NameCon str1)))) x2 <- xx
  , isPrefixOf "I#_" str1
  = detect x2

  
  -- Boilerplate traversal.
  | otherwise
  = case xx of
        XAnnot a x      -> liftM (XAnnot a) (detect x)
        XVar  u         -> liftM  XVar  (detect u)
        XCon  u         -> liftM  XCon  (detect u)
        XLAM  b x       -> liftM2 XLAM  (detect b)   (detect x)
        XLam  b x       -> liftM2 XLam  (detect b)   (detect x)
        XApp  x1 x2     -> liftM2 XApp  (detect x1)  (detect x2)
        XLet  lts x     -> liftM2 XLet  (detect lts) (detect x)
        XType t         -> liftM  XType (detect t)

        XCase x alts    -> liftM2 XCase (detect x)   (mapM detect alts)
        XCast{}         -> error "repa-plugin.detect: XCast not handled"
        XWitness{}      -> error "repa-plugin.detect: XWitness not handled"


-- Match arithmetic operators.
matchPrimArith :: String -> Maybe (Name, Type Name, Type Name)
matchPrimArith str
 -- Num
 | isPrefixOf "$fNumInt_$c+_" str       
 = Just (NamePrimArith PrimArithAdd, tInt, typePrimArith PrimArithAdd)

 | isPrefixOf "$fNumInt_$c-_" str       
 = Just (NamePrimArith PrimArithSub, tInt, typePrimArith PrimArithSub)

 | isPrefixOf "$fNumInt_$c*_" str
 = Just (NamePrimArith PrimArithMul, tInt, typePrimArith PrimArithMul)

 -- Integral
 | isPrefixOf "$fIntegralInt_$cdiv_" str
 = Just (NamePrimArith PrimArithDiv, tInt, typePrimArith PrimArithDiv)

 | isPrefixOf "$fIntegralInt_$crem_" str
 = Just (NamePrimArith PrimArithRem, tInt, typePrimArith PrimArithRem)

 | isPrefixOf "$fIntegralInt_$cmod_" str
 = Just (NamePrimArith PrimArithMod, tInt, typePrimArith PrimArithMod)

 -- Eq
 | isPrefixOf "eqInt_" str
 = Just (NamePrimArith PrimArithEq,  tInt, typePrimArith PrimArithEq)

 | isPrefixOf "gtInt_" str
 = Just (NamePrimArith PrimArithGt,  tInt, typePrimArith PrimArithGt)

 | isPrefixOf "ltInt_" str
 = Just (NamePrimArith PrimArithLt,  tInt, typePrimArith PrimArithLt)

 | otherwise
 = Nothing


--- Lets ----------------------------------------------------------------------
instance Detect (Lets a) where
 detect ll
  = case ll of
        LLet b x      
         -> do  b'      <- detect b
                x'      <- detect x
                return  $ LLet b' x'

        LRec bxs        
         -> do  let (bs, xs) = unzip bxs
                bs'     <- mapM detect bs
                xs'     <- mapM detect xs
                return  $ LRec $ zip bs' xs'

        LLetRegions{}   -> error "repa-plugin.detect: LLetRegions not handled"
        LWithRegion{}   -> error "repa-plugin.detect: LWithRegions not handled"


--- Alt  ----------------------------------------------------------------------
instance Detect (Alt a) where
 detect (AAlt p x)
  = liftM2 AAlt (detect p) (detect x)

instance Detect Pat where
 detect p
  = case p of
        PDefault
         -> return PDefault

        PData dc bs
         -> liftM2 PData (detect dc) (mapM detect bs)

