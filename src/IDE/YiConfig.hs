{-# LANGUAGE CPP #-}
{- Based on example config Yi/Users/Corey.hs that uses the Vim keymap with these additions:
    - Always uses the VTY UI by default.
    - The color style is darkBlueTheme
    - The insert mode of the Vim keymap has been extended with a few additions
      I find useful.
 -}

module IDE.YiConfig (
    defaultYiConfig
,   Config
,   Control
,   ControlM
,   YiM
,   start
,   runControl
,   liftYi
) where

#ifdef LEKSAH_WITH_YI

import Data.List (reverse, isPrefixOf)

import Yi
import Yi.Keymap.Vim

import qualified Yi.UI.Pango
import Yi.UI.Pango.Control

import Control.Monad (replicateM_)
import Control.Applicative (Alternative(..))

start yiConfig f =
    startControl yiConfig $ do
        yiControl <- getControl
        controlIO (f yiControl)

-- Set soft tabs of 4 spaces in width.
prefIndent :: Mode s -> Mode s
prefIndent m = m {
        modeIndentSettings = IndentSettings
            {
                expandTabs = True,
                shiftWidth = 4,
                tabSize = 4
            }}

noHaskellAnnots m
    | modeName m == "haskell" = m { modeGetAnnotations = modeGetAnnotations emptyMode }
    | otherwise = m

defaultYiConfig = defaultConfig
    {
        -- Use VTY as the default UI.
        startFrontEnd = Yi.UI.Pango.start,
        defaultKm = mkKeymap extendedVimKeymap,
        modeTable = fmap (onMode $ noHaskellAnnots . prefIndent) (modeTable defaultConfig),
        configUI = configUI defaultConfig
    }

extendedVimKeymap = defKeymap `override` \super self -> super
    {
        v_top_level =
            (deprioritize >> v_top_level super)
            -- On 'o' in normal mode I always want to use the indent of the previous line.
            -- TODO: If the line where the newline is to be inserted is inside a
            -- block comment then the block comment should be "continued"
            -- TODO: Ends up I'm trying to replicate vim's "autoindent" feature. This
            -- should be made a function in Yi.
            <|> (char 'o' ?>> beginIns self $ do
                    moveToEol
                    insertB '\n'
                    indentAsPreviousB
                )
            -- On HLX (Haskell Language Extension) I want to go into insert mode such
            -- that the cursor position is correctly placed to start entering the name
            -- of an language extension in a LANGUAGE pragma.
            -- A language pragma will take either the form
            -- {-# LANGUAGE Foo #-}
            -- or
            -- >{-# LANGUAGE Foo #-}
            -- The form should be chosen based on the current mode.
            <|> ( pString "HXL" >> startExtesnionNameInsert self ),
        v_ins_char =
            (deprioritize >> v_ins_char super)
            -- On enter I always want to use the indent of previous line
            -- TODO: If the line where the newline is to be inserted is inside a
            -- block comment then the block comment should be "continued"
            -- TODO: Ends up I'm trying to replicate vim's "autoindent" feature. This
            -- should be made a function in Yi.
            <|> ( spec KEnter ?>>! do
                    insertB '\n'
                    indentAsPreviousB
                )
            -- I want softtabs to be deleted as if they are tabs. So if the
            -- current col is a multiple of 4 and the previous 4 characters
            -- are spaces then delete all 4 characters.
            -- TODO: Incorporate into Yi itself.
            <|> ( spec KBS ?>>! do
                    c <- curCol
                    line <- readRegionB =<< regionOfPartB Line Backward
                    sw <- indentSettingsB >>= return . shiftWidth
                    let indentStr = replicate sw ' '
                        toDel = if (c `mod` sw) /= 0
                                    then 1
                                    else if indentStr `isPrefixOf` reverse line
                                        then sw
                                        else 1
                    adjBlock (-toDel)
                    replicateM_ toDel $ deleteB Character Backward
                )
            -- On starting to write a block comment I want the close comment
            -- text inserted automatically.
            <|> choice
                [ pString open_tag >>! do
                    insertN $ open_tag ++ " \n"
                    indentAsPreviousB
                    insertN $ " " ++ close_tag
                    lineUp
                 | (open_tag, close_tag) <-
                    [ ("{-", "-}") -- Haskell block comments
                    , ("/*", "*/") -- C++ block comments
                    ]
                ]
    }


startExtesnionNameInsert :: ModeMap -> I Event Action ()
startExtesnionNameInsert self = beginIns self $ do
    p_current <- pointB
    m_current <- getMarkB (Just "'")
    setMarkPointB m_current p_current
    moveTo $ Point 0
    insertB '\n'
    moveTo $ Point 0
    insertN "{-# LANGUAGE "
    p <- pointB
    insertN " #-}"
    moveTo p

#else

data Config = Config
data Control = Control
data ControlM a = ControlM
data YiM a = YiM

defaultYiConfig :: Config
defaultYiConfig = Config
start :: Config -> (Control -> IO a) -> IO a
start yiConfig f = f Control
runControl :: ControlM a -> Control -> IO a
runControl = undefined
liftYi :: YiM a -> ControlM a
liftYi = undefined

#endif

