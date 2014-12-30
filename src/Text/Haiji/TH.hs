{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
module Text.Haiji.TH ( haiji, haijiFile ) where

import Language.Haskell.TH
import Language.Haskell.TH.Quote
import Data.Attoparsec.Text
import qualified Data.Text as T
import qualified Data.Text.Lazy as LT
import qualified Data.Text.Lazy.IO as LT
import Text.Haiji.Parse
import Text.Haiji.Types

haiji :: QuasiQuoter
haiji = QuasiQuoter { quoteExp = haijiExp
                    , quotePat = undefined
                    , quoteType = haijiType
                    , quoteDec = undefined
                    }

haijiFile :: FilePath -> ExpQ
haijiFile file = runIO (LT.readFile file) >>= haijiExp . LT.unpack

haijiExp :: String -> ExpQ
haijiExp = either error haijiASTs . parseOnly parser . T.pack

haijiASTs :: [AST] -> ExpQ
haijiASTs asts = do
  esc <- newName "esc"
  dict <- newName "dict"
  [e| \ $(varP esc) $(varP dict) -> LT.concat $(listE $ map (haijiAST esc dict) asts) |]

add :: x -> Key k -> TLDict s -> TLDict ((k :-> x) ': s)
add x _ d = Ext (Value x) d

haijiAST :: Name -> Name -> AST -> ExpQ
haijiAST _esc _dict (Literal l) = [e| s |] where s = T.unpack l
haijiAST  esc  dict (Deref x) = [e| $(varE esc) $ $(deref dict x) |]
haijiAST  esc  dict (Condition p ts (Just fs)) =
    [e| (if $(deref dict p) then $(haijiASTs ts) else $(haijiASTs fs)) $(varE esc) $(varE dict) |]
haijiAST  esc  dict (Condition p ts Nothing) =
    [e| (if $(deref dict p) then $(haijiASTs ts) else (\_ _ -> "")) $(varE esc) $(varE dict) |]
haijiAST  esc  dict (Foreach k xs body) =
    [e| LT.concat $ map (\x -> $(haijiASTs body) $(varE esc) (add x (Key :: Key $(litT . strTyLit $ T.unpack k)) $(varE dict))) $(deref dict xs)|]

deref :: Name -> Variable -> ExpQ
deref dict (SimpleVariable v) = [e| retrieve $(varE dict) (Key :: Key $(litT . strTyLit $ T.unpack v)) |]
deref dict (ObjectDotVariable v f) = [e| retrieve $(deref dict v) (Key :: Key $(litT . strTyLit $ T.unpack f)) |]
deref dict (ArrayIndexVariable v ix) = [e| $(deref dict v) !! ix |]

haijiType :: String -> Q Type
haijiType = undefined
