{-# LANGUAGE OverloadedStrings #-}
module Text.Haiji.Parse where

import Control.Applicative
import Control.Monad
import Data.Attoparsec.Text
import qualified Data.Text as T

-- $setup
-- >>> :set -XOverloadedStrings

data Variable = Simple T.Text
              | Attribute Variable T.Text
              | At Variable Int
                deriving Eq

instance Show Variable where
    show (Simple v) = T.unpack v
    show (Attribute v f) = shows v "." ++ T.unpack f
    show (At v ix) = shows v "[" ++ show ix ++ "]"

data AST = Literal T.Text
         | Deref Variable
         | Condition Variable [AST] (Maybe [AST])
         | Foreach T.Text Variable [AST]
         | Include FilePath
           deriving Eq

instance Show AST where
    show (Literal l) = T.unpack l
    show (Deref v) = "{{ " ++ shows v " }}"
    show (Condition p ts mfs) = "{% if " ++ show p ++ "%}" ++
                                concatMap show ts ++
                                maybe "" (\fs -> "{% else %}" ++ concatMap show fs) mfs ++
                                "{% endif %}"
    show (Foreach x xs asts) = "{% for " ++ show x ++ " in " ++ show xs ++ "%}" ++
                               concatMap show asts ++
                               "{% endfor %}"
    show (Include file) = "{% include \"" ++ file ++ "\" %}"

parser :: Parser [AST]
parser = many $ choice [ literalParser
                       , derefParser
                       , conditionParser
                       , foreachParser
                       , includeParser
                       ]
-- |
--
-- >>> parseOnly literalParser "テスト{test"
-- Right テスト
--
literalParser :: Parser AST
literalParser = Literal <$> takeWhile1 (/= '{')

-- |
--
-- >>> parseOnly derefParser "{{ foo }}"
-- Right {{ foo }}
-- >>> parseOnly derefParser "{{bar}}"
-- Right {{ bar }}
-- >>> parseOnly derefParser "{{   baz}}"
-- Right {{ baz }}
-- >>> parseOnly derefParser " {{ foo }}"
-- Left "Failed reading: takeWith"
-- >>> parseOnly derefParser "{ { foo }}"
-- Left "Failed reading: takeWith"
-- >>> parseOnly derefParser "{{ foo } }"
-- Left "Failed reading: takeWith"
-- >>> parseOnly derefParser "{{ foo }} "
-- Right {{ foo }}
--
derefParser :: Parser AST
derefParser = Deref <$> ((string "{{" >> skipSpace) *> variableParser <* (skipSpace >> string "}}"))

-- | python identifier
--
-- https://docs.python.org/2.7/reference/lexical_analysis.html#identifiers
--
-- >>> parseOnly identifier "a"
-- Right "a"
-- >>> parseOnly identifier "_"
-- Right "_"
-- >>> parseOnly identifier "_a"
-- Right "_a"
-- >>> parseOnly identifier "_1"
-- Right "_1"
-- >>> parseOnly identifier "__"
-- Right "__"
-- >>> parseOnly identifier "_ "
-- Right "_"
-- >>> parseOnly identifier " _"
-- Left "Failed reading: satisfy"
-- >>> parseOnly identifier "and"
-- Left "Failed reading: identifier"
--
identifier :: Parser T.Text
identifier = do
  h <- letter <|> char '_'
  ts <- many (letter <|> digit <|> char '_')
  let candidate = h : ts
  when (candidate `elem` keywords) $ fail "identifier"
  return $ T.pack candidate

-- | python keywords
--
-- https://docs.python.org/2.7/reference/lexical_analysis.html#keywords
--
keywords :: [String]
keywords = words
           $  "and       del       from      not       while "
           ++ "as        elif      global    or        with "
           ++ "assert    else      if        pass      yield "
           ++ "break     except    import    print "
           ++ "class     exec      in        raise "
           ++ "continue  finally   is        return "
           ++ "def       for       lambda    try "

-- |
--
-- >>> parseOnly variableParser "foo"
-- Right foo
-- >>> parseOnly variableParser "foo.bar"
-- Right foo.bar
-- >>> parseOnly variableParser "foo[0]"
-- Right foo[0]
-- >>> parseOnly variableParser "foo.bar[0]"
-- Right foo.bar[0]
-- >>> parseOnly variableParser "foo[0].bar"
-- Right foo[0].bar
-- >>> parseOnly variableParser "foo.b}}ar"
-- Right foo.b
-- >>> parseOnly variableParser "foo.b ar"
-- Left "Failed reading: variableParser"
-- >>> parseOnly variableParser "foo.b }ar"
-- Right foo.b
-- >>> parseOnly variableParser " foo.bar"
-- Left "Failed reading: satisfy"
-- >>> parseOnly variableParser "foo.  bar"
-- Right foo.bar
-- >>> parseOnly variableParser "foo  .bar"
-- Right foo.bar
-- >>> parseOnly variableParser "foo.bar  "
-- Right foo.bar
-- >>> parseOnly variableParser "foo.bar  "
-- Right foo.bar
-- >>> parseOnly variableParser "foo  [0]"
-- Right foo[0]
-- >>> parseOnly variableParser "foo  [  0  ]"
-- Right foo[0]
--
variableParser :: Parser Variable
variableParser = identifier >>= variableParser' . Simple where
    variableParser' v = do
      skipSpace
      peek <- peekChar
      case peek of
        Nothing  -> return v
        Just '}' -> return v
        Just ' ' -> return v
        Just '.' -> char '.' >> skipSpace >> identifier >>= variableParser' . Attribute v
        Just '[' -> (char '[' >> skipSpace) *> decimal <* (skipSpace >> char ']') >>= variableParser' . At v
        _        -> fail "variableParser"

statement :: Parser a -> Parser a
statement f = (string "{%" >> skipSpace) *> f <* (skipSpace >> string "%}")

conditionParser :: Parser AST
conditionParser = do
  cond <- statement $ string "if" >> skipSpace >> variableParser
  ifbody <- parser
  _ <- statement $ string "endif" <|> string "else" -- このあたり間違ってる
  elsebody <- option Nothing (Just <$> parser)      --
  _ <- statement $ string "endif"
  return $ Condition cond ifbody elsebody

foreachParser :: Parser AST
foreachParser = do
  foreachBlock <- statement $ Foreach
                  <$> (string "for" >> skipSpace >> takeTill (inClass " .[}"))
                  <*> (skipSpace >> string "in" >> skipSpace >> variableParser)
  foreachBlock <$> parser <* statement (string "endfor")

includeParser :: Parser AST
includeParser = statement $ string "include" >> skipSpace >> Include . T.unpack <$> (quotedBy '"' <|> quotedBy '\'') where
    quotedBy c = char c *> takeTill (== c) <* char c
