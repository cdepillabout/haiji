module Text.Haiji.Syntax.Variable
       ( Variable(..)
       , variable
       ) where

import Data.Attoparsec.Text
import Text.Haiji.Syntax.Identifier

data Variable = VariableBase Identifier
              | VariableAttribute Variable Identifier
              deriving Eq

instance Show Variable where
  show (VariableBase var) = show var
  show (VariableAttribute var attr) = shows var "." ++ show attr

-- |
--
-- >>> let eval = either (error "parse error") id . parseOnly variable
-- >>> eval "foo"
-- foo
-- >>> eval "foo.bar"
-- foo.bar
-- >>> eval "foo.b}}ar"
-- foo.b
-- >>> eval "foo.b ar"
-- foo.b
-- >>> eval "foo.b }ar"
-- foo.b
-- >>> eval " foo.bar"
-- *** Exception: parse error
-- >>> eval "foo.  bar"
-- foo.bar
-- >>> eval "foo  .bar"
-- foo.bar
-- >>> eval "foo.bar  "
-- foo.bar
-- >>> eval "foo.bar  "
-- foo.bar
-- >>> eval "foo.bar.baz"
-- foo.bar.baz
--
variable :: Parser Variable
variable = identifier >>= go . VariableBase where
  go var = do
    skipSpace
    peek <- peekChar
    case peek of
      Nothing  -> return var
      Just '}' -> return var
      Just ' ' -> return var
      Just '.' -> char '.' >> skipSpace >> identifier >>= go . VariableAttribute var
      _        -> return var
