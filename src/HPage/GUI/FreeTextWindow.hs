{-# LANGUAGE GeneralizedNewtypeDeriving,
             MultiParamTypeClasses,
             FlexibleInstances,
             FlexibleContexts,
             FunctionalDependencies,
             UndecidableInstances #-}
             
module HPage.GUI.FreeTextWindow ( gui ) where

-- import Control.Concurrent.Process
import System.FilePath
import System.Directory
import System.IO.Error hiding (try)
import Data.List
import Data.Bits
import Data.Char (toLower)
import Data.Version
import Distribution.Package
import Control.Monad.Error
import Control.Monad.Loops
import Graphics.UI.WX
import Graphics.UI.WXCore
import Graphics.UI.WXCore.Types
import Graphics.UI.WXCore.Dialogs
import Graphics.UI.WXCore.Events
import Graphics.UI.WXCore.WxcClasses
import qualified HPage.Control as HP
import qualified HPage.Server as HPS
import HPage.GUI.Dialogs
import HPage.GUI.IDs
import HPage.Utils.Log

import Paths_hpage -- cabal locations of data files

imageFile :: FilePath -> IO FilePath
imageFile fp = do
                path <- getDataFileName $ "res/images/" ++ fp
                real <- doesFileExist path
                if real then return path
                        else do
                                errorIO ("file not found", path)
                                fail (path ++ " does not exist")

helpFile :: IO FilePath
helpFile = getDataFileName "res/help/helpPage.hs"

data GUIResults = GUIRes { resPanel :: Panel (),
                           resButton :: Button (),
                           resLabel :: StaticText (),
                           resValue :: TextCtrl (),
                           res4Dots :: StaticText (),
                           resType  :: TextCtrl (),
                           resKind  :: TextCtrl () }

data GUIContext  = GUICtx { guiWin :: Frame (),
                            guiPages :: SingleListBox (),
                            guiPkgModules :: SingleListBox (),
                            guiLoadedModules :: ListCtrl (),
                            guiCode :: TextCtrl (),
                            guiResults :: GUIResults,
                            guiStatus :: StatusField,
                            guiTimer :: Var (TimerEx ()),
                            guiSearch :: FindReplaceData ()} 

gui :: IO ()
gui =
    do
        -- Server context
        model <- HPS.start
        
        win <- frame [text := "λPage"]
        imageFile "icon/hpage.tif" >>= topLevelWindowSetIconFromFile win 
        
        set win [on closing := HPS.stop model >> propagateEvent]

        -- Containers
        ntbkL <- notebook win []
        pnlPs <- panel ntbkL []
        pnlPMs <- panel ntbkL []
        pnlLMs <- panel ntbkL []
        
        -- Text page...
    --  txtCode <- styledTextCtrl win []
        txtCode <- textCtrl win [font := fontFixed, text := ""]
        
        -- Document Selector
        lstPages <- singleListBox pnlPs [style := wxLB_NEEDED_SB, outerSize := sz 400 600]
        
        -- Modules Lists
        imageFiles <- mapM imageFile ["m_imported.ico", "m_interpreted.ico", "m_compiled.ico"]
        imagePaths <- mapM getAbsoluteFilePath imageFiles
        images     <- imageListFromFiles (sz 16 16) imagePaths
        lstLoadedModules <- listCtrlEx pnlLMs (wxLC_NO_HEADER + wxLC_SINGLE_SEL)
                                       [columns := [("Module", AlignLeft, 200)]]
        listCtrlSetImageList lstLoadedModules images wxIMAGE_LIST_SMALL

        lstPkgModules <- singleListBox pnlPMs [style := wxLB_NEEDED_SB]
        
        -- Results panel
        pnlRes <- panel win []
        txtValue <- textEntry pnlRes [style := wxTE_READONLY]
        txtType <- textEntry pnlRes [style := wxTE_READONLY]
        txtKind <- textEntry pnlRes [style := wxTE_READONLY, visible := False]
        btnInterpret <- button pnlRes [text := "Interpret"]
        lblInterpret <- staticText pnlRes [text := "Value:"]
        lbl4Dots <- staticText pnlRes [text := " :: "]
        set pnlRes [layout := fill $ 
                                row 5 [widget btnInterpret,
                                       centre $ widget lblInterpret,
                                       fill $ widget txtValue,
                                       centre $ widget lbl4Dots,
                                       fill $ widget txtType]]

        -- Status bar...
        status <- statusField [text := "hello... this is λPage! type in your instructions :)"]
        set win [statusBar := [status]]

        -- Timer ...
        refreshTimer <- timer win [interval := 1000000, on command := debugIO "Inactivity detected"]
        varTimer <- varCreate refreshTimer
        
        -- Search ...
        search <- findReplaceDataCreate wxFR_DOWN
        
        let guiRes = GUIRes pnlRes btnInterpret lblInterpret txtValue lbl4Dots txtType txtKind
        let guiCtx = GUICtx win lstPages lstPkgModules lstLoadedModules txtCode guiRes status varTimer search 
        let onCmd name acc = traceIO ("onCmd", name) >> acc model guiCtx

        set btnInterpret [on command := onCmd "interpret" interpret]
        
        -- Events
        set lstPages [on select := onCmd "pageChange" pageChange]
        set txtCode [on keyboard := \_ -> onCmd "restartTimer" restartTimer >> propagateEvent,
                     on mouse :=  \e -> case e of
                                            MouseLeftUp _ _ -> onCmd "mouseEvent" restartTimer >> propagateEvent
                                            MouseLeftDClick _ _ -> onCmd "mouseEvent" restartTimer >> propagateEvent
                                            MouseRightDown _ _ -> onCmd "textContextMenu" textContextMenu
                                            _ -> propagateEvent]
        set lstLoadedModules [on listEvent := \e -> case e of
                                                        ListItemSelected idx -> onCmd "browseModule" (browseModule idx)
                                                        _ -> propagateEvent]
        set lstPkgModules [on mouse := \e -> case e of
                                                MouseRightUp _ _ -> onCmd "pkgModuleContextMenu" pkgModuleContextMenu >> propagateEvent
                                                MouseLeftDClick _ _ -> onCmd "loadModulesByNameFast" loadModulesByNameFast
                                                _ -> propagateEvent]
        
        -- Menu bar...
        mnuPage <- menuPane [text := "Page"]
        menuAppend mnuPage wxId_NEW "&New\tCtrl-n" "New Page" False
        menuAppend mnuPage wxId_CLOSE "&Close\tCtrl-w" "Close Page" False
        menuAppend mnuPage wxId_CLOSE_ALL "&Close All\tCtrl-Shift-w" "Close All Pages" False
        menuAppendSeparator mnuPage
        menuAppend mnuPage wxId_OPEN "&Open...\tCtrl-o" "Open Page" False
        menuAppend mnuPage wxId_SAVE "&Save\tCtrl-s" "Save Page" False
        menuAppend mnuPage wxId_SAVEAS "&Save as...\tCtrl-Shift-s" "Save Page as" False
        menuAppendSeparator mnuPage
        menuQuit mnuPage [on command := close win]
        
        mnuEdit <- menuPane [text := "Edit"]
        menuAppend mnuEdit wxId_UNDO "&Undo\tCtrl-z" "Undo" False
        menuAppend mnuEdit wxId_REDO "&Redo\tCtrl-Shift-z" "Redo" False
        menuAppendSeparator mnuEdit
        menuAppend mnuEdit wxId_CUT "C&ut\tCtrl-x" "Cut" False
        menuAppend mnuEdit wxId_COPY "&Copy\tCtrl-c" "Copy" False
        menuAppend mnuEdit wxId_PASTE "&Paste\tCtrl-v" "Paste" False
        menuAppendSeparator mnuEdit
        menuAppend mnuEdit wxId_FIND "&Find...\tCtrl-f" "Find" False
        menuAppend mnuEdit wxId_FORWARD "Find &Next\tCtrl-g" "Find Next" False
        menuAppend mnuEdit wxId_BACKWARD "Find &Previous\tCtrl-Shift-g" "Find Previous" False
        menuAppend mnuEdit wxId_REPLACE "&Replace...\tCtrl-Shift-r" "Replace" False
        menuAppendSeparator mnuEdit
        menuAppend mnuEdit wxId_PREFERENCES "&Preferences...\tCtrl-," "Preferences" False

        mnuHask <- menuPane [text := "Haskell"]
        menuAppend mnuHask wxId_HASK_LOAD_PKG "Load &package...\tCtrl-Shift-l" "Load Cabal Package" False
        menuAppendSeparator mnuHask
        menuAppend mnuHask wxId_HASK_LOAD "&Load modules...\tCtrl-l" "Load Modules" False
        menuAppend mnuHask wxId_HASK_LOADNAME "Load modules by &name...\tCtrl-Shift-l" "Load Modules by Name" False
        menuAppend mnuHask wxId_HASK_ADD "Import modules...\tCtrl-Shift-i" "Import Packaged Modules by Name" False
        menuAppend mnuHask wxId_HASK_RELOAD "&Reload\tCtrl-r" "Reload Modules" False
        menuAppendSeparator mnuHask
        menuAppend mnuHask wxId_HASK_INTERPRET "&Interpret\tCtrl-i" "Interpret the Current Expression" False
        
        mnuHelp <- menuHelp []
        menuAppend mnuHelp wxId_HELP "&Help page\tCtrl-h" "Open the Help Page" False
        menuAbout mnuHelp [on command := infoDialog win "About λPage" "Author: Fernando Brujo Benavides"]
        
        set win [menuBar := [mnuPage, mnuEdit, mnuHask, mnuHelp]]
        evtHandlerOnMenuCommand win wxId_NEW $ onCmd "runHP' addPage" $ runHP' HP.addPage
        evtHandlerOnMenuCommand win wxId_CLOSE $ onCmd "runHP' closePage" $ runHP' HP.closePage
        evtHandlerOnMenuCommand win wxId_CLOSE_ALL $ onCmd "runHP' closeAllPages" $ runHP' HP.closeAllPages
        evtHandlerOnMenuCommand win wxId_OPEN $ onCmd "openPage" openPage
        evtHandlerOnMenuCommand win wxId_SAVE $ onCmd "savePage" savePage
        evtHandlerOnMenuCommand win wxId_SAVEAS $ onCmd "savePageAs" savePageAs
        evtHandlerOnMenuCommand win wxId_UNDO $ onCmd "runHP' undo" $ runHP' HP.undo
        evtHandlerOnMenuCommand win wxId_REDO $ onCmd "runHP' redo" $ runHP' HP.redo
        evtHandlerOnMenuCommand win wxId_CUT $ onCmd "cut" cut
        evtHandlerOnMenuCommand win wxId_COPY $ onCmd "copy" copy
        evtHandlerOnMenuCommand win wxId_PASTE $ onCmd "paste" paste
        evtHandlerOnMenuCommand win wxId_FIND $ onCmd "justFind" justFind
        evtHandlerOnMenuCommand win wxId_FORWARD $ onCmd "findNext" justFindNext
        evtHandlerOnMenuCommand win wxId_BACKWARD $ onCmd "findPrev" justFindPrev
        evtHandlerOnMenuCommand win wxId_REPLACE $ onCmd "findReplace" findReplace
        evtHandlerOnMenuCommand win wxId_HASK_LOAD_PKG $ onCmd "loadPackage" loadPackage
        evtHandlerOnMenuCommand win wxId_HASK_LOAD $ onCmd "loadModules" loadModules
        evtHandlerOnMenuCommand win wxId_HASK_ADD $ onCmd "importModules" importModules
        evtHandlerOnMenuCommand win wxId_HASK_LOADNAME $ onCmd "loadModulesByName" loadModulesByName
        evtHandlerOnMenuCommand win wxId_HASK_LOAD_FAST $ onCmd "loadModulesByNameFast" loadModulesByNameFast
        evtHandlerOnMenuCommand win wxId_HASK_RELOAD $ onCmd "reloadModules" reloadModules
        evtHandlerOnMenuCommand win wxId_PREFERENCES $ onCmd "preferences" configure
        evtHandlerOnMenuCommand win wxId_HASK_INTERPRET $ onCmd "interpret" interpret
        evtHandlerOnMenuCommand win wxId_HELP $ onCmd "help" openHelpPage
        
        -- Tool bar...
        tbMain <- toolBarEx win True True []
        mitLoadPkg <- menuFindItem mnuHask wxId_HASK_LOAD_PKG
        mitNew <- menuFindItem mnuPage wxId_NEW
        mitOpen <- menuFindItem mnuPage wxId_OPEN
        mitSave <- menuFindItem mnuPage wxId_SAVE
        mitCut <- menuFindItem mnuEdit wxId_CUT
        mitCopy <- menuFindItem mnuEdit wxId_COPY
        mitPaste <- menuFindItem mnuEdit wxId_PASTE
        mitReload <- menuFindItem mnuHask wxId_HASK_RELOAD
        loadPath <- imageFile "load.png"
        newPath <- imageFile "new.png"
        openPath <- imageFile "open.png"
        savePath <- imageFile "save.png"
        cutPath <- imageFile "cut.png"
        copyPath <- imageFile "copy.png"
        pastePath <- imageFile "paste.png"
        reloadPath <- imageFile "reload.png"
        toolMenu tbMain mitLoadPkg "Load Package" loadPath [tooltip := "Load Cabal Package"]
        toolBarAddSeparator tbMain
        toolMenu tbMain mitNew "New" newPath [tooltip := "New Page"]
        toolMenu tbMain mitOpen "Open" openPath [tooltip := "Open Page"]
        toolMenu tbMain mitSave "Save" savePath [tooltip := "Save Page"]
        toolBarAddSeparator tbMain
        toolMenu tbMain mitCut "Cut" cutPath [tooltip := "Cut"]
        toolMenu tbMain mitCopy "Copy" copyPath [tooltip := "Copy"]
        toolMenu tbMain mitPaste "Paste" pastePath [tooltip := "Paste"]
        toolBarAddSeparator tbMain
        toolMenu tbMain mitReload "Reload" reloadPath [tooltip := "Reload Modules"]
        toolBarSetToolBitmapSize tbMain $ sz 32 32

        -- Layout settings
        let txtCodeL    = fill $ widget txtCode
            pagesTabL   = tab "Pages" $ container pnlPs $ fill $ margin 5 $ widget lstPages
            pkgModsTabL = tab "Package" $ container pnlPMs $ fill $ margin 5 $ widget lstPkgModules
            lddModsTabL = tab "Modules" $ container pnlLMs $ fill $ margin 5 $ widget lstLoadedModules
            leftL       = tabs ntbkL [lddModsTabL, pkgModsTabL, pagesTabL]
            resultsL    = hfill $ boxed "Expression" $ fill $ widget pnlRes
            rightL      = minsize (sz 485 100) $ column 5 [txtCodeL, resultsL]
        set win [layout := fill $ row 10 [leftL, rightL],
                 clientSize := sz 800 600]

        -- ...and RUN!
        refreshPage model guiCtx
        onCmd "start" openHelpPage
        focusOn txtCode

-- EVENT HANDLERS --------------------------------------------------------------
refreshPage, savePageAs, savePage, openPage,
    pageChange, copy, cut, paste,
    justFind, justFindNext, justFindPrev, findReplace,
    textContextMenu, pkgModuleContextMenu,
    restartTimer, killTimer,
    loadPackage, loadModules, importModules, loadModulesByName, loadModulesByNameFast, reloadModules,
    configure, openHelpPage :: HPS.ServerHandle -> GUIContext -> IO ()

browseModule :: Int -> HPS.ServerHandle -> GUIContext -> IO ()

browseModule i model guiCtx@GUICtx{guiWin = win, guiLoadedModules = lstLoadedModules, guiCode = txtCode} =
    do
        contextMenu <- menuPane []
        mn <- listCtrlGetItemText lstLoadedModules i
        hpsRes <- tryIn model $ HP.getModuleExports mn
        case hpsRes of
            Left err ->
                propagateEvent >> warningDialog win "Error" err
            Right mes ->
                do
                    flip mapM_ mes $ createMenuItem contextMenu
                    propagateEvent
                    pointWithinWindow <- windowGetMousePosition win
                    menuPopup contextMenu pointWithinWindow win
                    objectDelete contextMenu
    where createMenuItem m fn@(HP.MEFun _ _) =
            do
                item <- menuItemCreate
                menuItemSetCheckable item False
                menuItemSetText item $ show fn
                menuItemSetId item wxId_HASK_MENUELEM
                menuAppendItem m item 
          createMenuItem m HP.MEClass{HP.clsName = cn, HP.clsFuns = []} =
            do
                item <- menuItemCreate
                menuItemSetCheckable item False
                menuItemSetText item $ "class " ++ cn
                menuItemSetId item wxId_HASK_MENUELEM
                menuAppendItem m item
          createMenuItem m HP.MEClass{HP.clsName = cn, HP.clsFuns = cfs} =
            do
                subMenu <- menuPane []
                flip mapM_ cfs $ createMenuItem subMenu
                menuAppendSub m wxId_HASK_MENUELEM ("class " ++ cn) subMenu ""
          createMenuItem m HP.MEData{HP.datName = dn, HP.datCtors = []} =
            do
                item <- menuItemCreate
                menuItemSetCheckable item False
                menuItemSetText item $ "data " ++ dn
                menuItemSetId item wxId_HASK_MENUELEM
                menuAppendItem m item
          createMenuItem m HP.MEData{HP.datName = dn, HP.datCtors = dcs} =
            do
                subMenu <- menuPane []
                flip mapM_ dcs $ createMenuItem subMenu
                menuAppendSub m wxId_HASK_MENUELEM ("data " ++ dn) subMenu ""

textContextMenu model guiCtx@GUICtx{guiWin = win, guiCode = txtCode} =
    do
        contextMenu <- menuPane []
        sel <- textCtrlGetStringSelection txtCode
        case sel of
                "" ->
                        return ()
                _ ->
                    do
                        menuAppend contextMenu wxId_CUT "C&ut\tCtrl-x" "Cut" False
                        menuAppend contextMenu wxId_COPY "&Copy\tCtrl-c" "Copy" False
                        menuAppend contextMenu wxId_PASTE "&Paste\tCtrl-v" "Paste" False
                        menuAppendSeparator contextMenu
        menuAppend contextMenu wxId_HASK_INTERPRET "&Interpret\tCtrl-i" "Interpret the Current Expression" False
        
        propagateEvent
        pointWithinWindow <- windowGetMousePosition win
        menuPopup contextMenu pointWithinWindow win
        objectDelete contextMenu

pkgModuleContextMenu model guiCtx@GUICtx{guiWin = win, guiPkgModules = lstPkgModules} =
    do
        contextMenu <- menuPane []
        i <- get lstPkgModules selection
        case i of
            (-1) -> return ()
            i ->
                do
                    mnText <- listBoxGetString lstPkgModules i
                    menuAppend contextMenu wxId_HASK_LOAD_FAST "&Load" "Load Module" False
                    propagateEvent
                    pointWithinWindow <- windowGetMousePosition win
                    menuPopup contextMenu pointWithinWindow win
                    objectDelete contextMenu

pageChange model guiCtx@GUICtx{guiPages = lstPages} =
    do
        i <- get lstPages selection
        case i of
            (-1) -> return ()
            _ -> runHP' (HP.setPageIndex i) model guiCtx

openPage model guiCtx@GUICtx{guiWin = win,
                             guiStatus = status} =
    do
        fileNames <- filesOpenDialog win True True "Open file..." [("Haskells",["*.hs"]),
                                                                   ("Any file",["*.*"])] "" ""
        case fileNames of
            [] ->
                return ()
            fs ->
                do
                    set status [text := "opening..."]
                    flip mapM_ fs $ \f -> runHP' (HP.openPage f) model guiCtx

savePageAs model guiCtx@GUICtx{guiWin = win, guiStatus = status} =
    do
        fileName <- fileSaveDialog win True True "Save file..." [("Haskells",["*.hs"]),
                                                                 ("Any file",["*.*"])] "" ""
        case fileName of
            Nothing ->
                return ()
            Just f ->
                do
                    set status [text := "saving..."]
                    runHP' (HP.savePageAs f) model guiCtx

savePage model guiCtx@GUICtx{guiWin = win} =
    do
        maybePath <- tryIn' model HP.getPagePath
        case maybePath of
            Left err ->
                warningDialog win "Error" err
            Right Nothing ->
                savePageAs model guiCtx
            Right _ ->
                do
                    set (guiStatus guiCtx) [text := "saving..."]
                    runHP' HP.savePage model guiCtx

copy _model GUICtx{guiCode = txtCode} = textCtrlCopy txtCode

cut model guiCtx@GUICtx{guiCode = txtCode} = textCtrlCut txtCode >> refreshPage model guiCtx

paste model guiCtx@GUICtx{guiCode = txtCode} = textCtrlPaste txtCode >> refreshPage model guiCtx

justFind model guiCtx = openFindDialog model guiCtx "Find..." dialogDefaultStyle

justFindNext model guiCtx@GUICtx{guiSearch = search} =
    do
        curFlags <- findReplaceDataGetFlags search
        findReplaceDataSetFlags search $ curFlags .|. wxFR_DOWN
        findNextButton model guiCtx

justFindPrev model guiCtx@GUICtx{guiSearch = search} =
    do
        curFlags <- findReplaceDataGetFlags search
        findReplaceDataSetFlags search $ curFlags .&. complement wxFR_DOWN
        findNextButton model guiCtx

findReplace model guiCtx = openFindDialog model guiCtx "Find and Replace..." $ dialogDefaultStyle .|. wxFR_REPLACEDIALOG
        
reloadModules = runHP HP.reloadModules

loadPackage model guiCtx@GUICtx{guiWin = win} =
    do
        distExists <- doesDirectoryExist "dist"
        let startDir = if distExists then "dist" else ""
        res <- fileOpenDialog win True True "Select the setup-config file for your project..."
                              [("setup-config",["setup-config"])] startDir "setup-config"
        case res of
                Nothing ->
                    return ()
                Just setupConfig ->
                    do
                        loadres <- tryIn model $ do
                                                    lr <- HP.loadPackage setupConfig
                                                    HP.addPage
                                                    return lr
                        case loadres of
                            Left err ->
                                warningDialog win "Error" err
                            Right pkg ->
                                do
                                    absPath <- canonicalizePath setupConfig
                                    let dir = joinPath . reverse . drop 2 . reverse $ splitDirectories absPath
                                    setCurrentDirectory dir
                                    frameSetTitle win $ "λPage - " ++ prettyShow pkg
                        refreshPage model guiCtx
  where prettyShow PackageIdentifier{pkgName = PackageName pkgname,
                                     pkgVersion = pkgvsn} = pkgname ++ "-" ++ showVersion pkgvsn


loadModules model guiCtx@GUICtx{guiWin = win, guiStatus = status} =
    do
        fileNames <- filesOpenDialog win True True "Load Module..." [("Haskell Modules",["*.hs"])] "" ""
        case fileNames of
            [] ->
                return ()
            fs ->
                do
                    set status [text := "loading..."]
                    runHP (HP.loadModules fs) model guiCtx

loadModulesByName model guiCtx@GUICtx{guiWin = win, guiStatus = status} =
    do
        moduleNames <- textDialog win "Enter the module names, separated by spaces" "Load Modules..." ""
        case moduleNames of
            "" ->
                return ()
            mns ->
                do
                    set status [text := "loading..."]
                    runHP (HP.loadModules $ words mns) model guiCtx

loadModulesByNameFast model guiCtx@GUICtx{guiWin = win, guiPkgModules = lstPkgModules, guiStatus = status} =
    do
        i <- get lstPkgModules selection
        case i of
            (-1) -> return ()
            i ->
                do
                    mnText <- listBoxGetString lstPkgModules i
                    let mns = [mnText]
                    set status [text := "loading..."]
                    runHP (HP.loadModules mns) model guiCtx

importModules model guiCtx@GUICtx{guiWin = win, guiStatus = status} =
    do
        moduleNames <- textDialog win "Enter the module names, separated by spaces" "Import Packaged Modules..." ""
        case moduleNames of
            "" ->
                return ()
            mns ->
                do
                    set status [text := "loading..."]
                    runHP (HP.importModules $ words mns) model guiCtx

configure model guiCtx@GUICtx{guiWin = win, guiStatus = status} =
    do
        hpsRes <- tryIn model $ do
                                    les <- HP.getLanguageExtensions
                                    sds <- HP.getSourceDirs
                                    gos <- HP.getGhcOpts
                                    case les of
                                        Left e -> return $ Left e
                                        Right l -> return $ Right (l, sds, gos)
        case hpsRes of
            Left err ->
                warningDialog win "Error" err
            Right (les, sds, gos) ->
                do
                    res <- preferencesDialog win "Preferences" $ Prefs les sds gos
                    case res of
                        Nothing ->
                            return ()
                        Just newps ->
                            do
                                set status [text := "setting..."]
                                runHP (do
                                            HP.setLanguageExtensions $ languageExtensions newps
                                            HP.setSourceDirs $ sourceDirs newps
                                            case ghcOptions newps of
                                                "" -> return $ Right ()
                                                newopts -> HP.setGhcOpts newopts
                                            ) model guiCtx

openHelpPage model guiCtx@GUICtx{guiCode = txtCode} =
    do
        f <- helpFile
        txt <- readFile f
        set txtCode [text := txt]
        -- Refresh the current expression box
        refreshExpr model guiCtx True

refreshPage model guiCtx@GUICtx{guiWin = win,
                                guiPages = lstPages,
                                guiPkgModules = lstPkgModules,
                                guiLoadedModules = lstLoadedModules,
                                guiCode = txtCode,
                                guiStatus = status} =
    do
        res <- tryIn' model $ do
                                pc <- HP.getPageCount
                                pages <- mapM HP.getPageNthDesc [0..pc-1]
                                ind <- HP.getPageIndex
                                txt <- HP.getPageText
                                lmsRes <- HP.getLoadedModules
                                ims <- HP.getImportedModules
                                pms <- HP.getPackageModules
                                let lms = case lmsRes of
                                            Left  _ -> []
                                            Right x -> x
                                return (pms, ims, lms, pages, ind, txt)
        case res of
            Left err ->
                warningDialog win "Error" err
            Right (pms, ims, ms, ps, i, t) ->
                do
                    -- Refresh the pages list
                    itemsDelete lstPages
                    (flip mapM) ps $ \pd ->
                                        let prefix = if HP.pIsModified pd
                                                        then "*"
                                                        else ""
                                            name   = case HP.pPath pd of
                                                         Nothing -> "new page"
                                                         Just fn -> takeFileName $ dropExtension fn
                                         in itemAppend lstPages $ prefix ++ name
                    set lstPages [selection := i]
                    
                    -- Refresh the modules lists
                    --NOTE: we know 0 == "imported" / 1 == "interpreted" / 2 == "compiled" images
                    --TODO: move that to some kind of constants or so
                    let ims' = map (\m -> (0, m)) ims
                        ms' = map (\m -> (if HP.modInterpreted m then 1 else 2, HP.modName m)) ms
                        allms = zip [0..] (ims' ++ ms')
                    itemsDelete lstLoadedModules
                    (flip mapM) allms $ \(idx, (img, m)) ->
                                                listCtrlInsertItemWithLabel lstLoadedModules idx m img >>                                                
                                                set lstLoadedModules [item idx := [m]]

                    itemsDelete lstPkgModules
                    (flip mapM) pms $ \pm -> itemAppend lstPkgModules (if any (\xm -> HP.modName xm == pm) ms then ('*':pm) else pm)
                    
                    -- Refresh the current text
                    set txtCode [text := t]
                    
                    -- Clean the status bar
                    set status [text := ""]
                    
                    -- Refresh the current expression box
                    refreshExpr model guiCtx True

runHP' ::  HP.HPage () -> HPS.ServerHandle -> GUIContext -> IO ()
runHP' a = runHP $ a >>= return . Right

runHP ::  HP.HPage (Either HP.InterpreterError ()) -> HPS.ServerHandle -> GUIContext -> IO ()
runHP hpacc model guiCtx@GUICtx{guiWin = win} =
    do
        res <- tryIn model hpacc
        case res of
            Left err ->
                warningDialog win "Error" err
            Right () ->
                refreshPage model guiCtx

interpret model guiCtx@GUICtx{guiResults = GUIRes{resPanel = pnlRes,
                                                  resLabel = lblInterpret,
                                                  resButton = btnInterpret,
                                                  resValue = txtValue,
                                                  res4Dots = lbl4Dots,
                                                  resType = txtType,
                                                  resKind = txtKind},
                              guiCode = txtCode, guiWin = win} =
    do
        sel <- textCtrlGetStringSelection txtCode
        let runner = case sel of
                        "" -> tryIn
                        sl -> runTxtHPSelection sl
        refreshExpr model guiCtx False
        set btnInterpret [enabled := False]
        res <- runner model HP.interpret
        case res of
                Left err ->
                    do
                        warningDialog win "Error" err
                        set btnInterpret [enabled := True]
                Right interp ->
                    if HP.isIntType interp
                        then do
                                set btnInterpret [enabled := True]
                                set txtValue [visible := False]
                                set lbl4Dots [visible := False]
                                set txtType [visible := False]
                                set txtKind [visible := True, text := HP.intKind interp]
                                set lblInterpret [text := "Kind:"]
                                set pnlRes [layout := fill $ centre $
                                                        row 5 [widget btnInterpret,
                                                               centre $ widget lblInterpret,
                                                               hfill $ widget txtKind]]
                                repaint win
                        else do
                                set btnInterpret [enabled := True]
                                set txtValue [visible := True, text := HP.intValue interp]
                                set lbl4Dots [visible := True, text := " :: "]
                                set txtType [visible := True, text := HP.intType interp]
                                set txtKind [visible := False]
                                set lblInterpret [text := "Value:"]
                                set pnlRes [layout := fill $ 
                                                        row 5 [widget btnInterpret,
                                                               centre $ widget lblInterpret,
                                                               hfill $ widget txtValue,
                                                               centre $ widget lbl4Dots,
                                                               hfill $ widget txtType]]
                                repaint win
 
runTxtHPSelection :: String ->  HPS.ServerHandle ->
                     HP.HPage (Either HP.InterpreterError HP.Interpretation) -> IO (Either ErrorString HP.Interpretation)
runTxtHPSelection s model hpacc =
    do
        debugIO ("evaluating selection", s)
        piRes <- tryIn' model HP.getPageIndex
        added <- tryIn' model $ HP.addPage
        case added of
                Left err ->
                    return $ Left err
                Right () ->
                    do
                        let cpi = case piRes of
                                        Left err -> 0
                                        Right cp -> cp
                            newacc = HP.setPageText s (length s) >> hpacc
                        res <- tryIn model newacc
                        tryIn' model $ HP.closePage >> HP.setPageIndex cpi 
                        return res

refreshExpr :: HPS.ServerHandle -> GUIContext -> Bool -> IO ()
refreshExpr model guiCtx@GUICtx{guiResults = GUIRes{resValue = txtValue,
                                                    resType = txtType,
                                                    resKind = txtKind},
                                guiCode = txtCode,
                                guiWin = win} forceClear =
   do
        txt <- get txtCode text
        ip <- textCtrlGetInsertionPoint txtCode
        
        res <- tryIn' model $ HP.setPageText txt ip
        
        case res of
            Left err ->
                warningDialog win "Error" err
            Right changed ->
                if changed || forceClear
                    then mapM_ (flip set [text := ""]) [txtValue, txtType, txtKind]
                    else debugIO "dummy refreshExpr"
        
        killTimer model guiCtx


-- TIMER HANDLERS --------------------------------------------------------------
restartTimer model guiCtx@GUICtx{guiWin = win, guiTimer = varTimer} =
    do
        newRefreshTimer <- timer win [interval := 1000,
                                      on command := refreshExpr model guiCtx False]
        refreshTimer <- varSwap varTimer newRefreshTimer
        timerOnCommand refreshTimer $ return ()

killTimer _model GUICtx{guiWin = win, guiTimer = varTimer} =
    do
        -- kill the timer till there's new notices
        newRefreshTimer <- timer win [interval := 1000000, on command := debugIO "Inactivity detected"]
        refreshTimer <- varSwap varTimer newRefreshTimer
        timerOnCommand refreshTimer $ return ()

-- INTERNAL UTILS --------------------------------------------------------------
type ErrorString = String

tryIn' :: HPS.ServerHandle -> HP.HPage x -> IO (Either ErrorString x)
tryIn' model hpacc = tryIn model $ hpacc >>= return . Right

tryIn :: HPS.ServerHandle -> HP.HPage (Either HP.InterpreterError x) -> IO (Either ErrorString x)
tryIn model hpacc =
    do
        res <- HPS.runIn model $ catchError (hpacc >>= return . Right)
                                            (\ioerr -> return $ Left ioerr)
        case res of
            Left err          -> do
                                    errorIO err
                                    return . Left  $ ioeGetErrorString err
            Right (Left err)  -> return . Left  $ HP.prettyPrintError err
            Right (Right val) -> return . Right $ val

-- FIND/REPLACE UTILS ----------------------------------------------------------
data FRFlags = FRFlags {frfGoingDown :: Bool,
                        frfMatchCase :: Bool,
                        frfWholeWord :: Bool,
                        frfWrapSearch :: Bool}
    deriving (Eq, Show)

buildFRFlags :: Bool -> Int -> IO FRFlags
buildFRFlags w x = return FRFlags {frfGoingDown = (x .&. wxFR_DOWN) /= 0,
                                   frfMatchCase = (x .&. wxFR_MATCHCASE) /= 0,
                                   frfWholeWord = (x .&. wxFR_WHOLEWORD) /= 0,
                                   frfWrapSearch = w}

openFindDialog :: HPS.ServerHandle -> GUIContext -> String -> Int -> IO ()
openFindDialog model guiCtx@GUICtx{guiWin = win,
                                   guiSearch = search} title dlgStyle =
    do
        frdialog <- findReplaceDialogCreate win search title $ dlgStyle + wxFR_NOWHOLEWORD
        let winSet k f = let hnd _ = f model guiCtx >> propagateEvent
                          in windowOnEvent frdialog [k] hnd hnd
        winSet wxEVT_COMMAND_FIND findNextButton
        winSet wxEVT_COMMAND_FIND_NEXT findNextButton
        winSet wxEVT_COMMAND_FIND_REPLACE findReplaceButton
        winSet wxEVT_COMMAND_FIND_REPLACE_ALL findReplaceAllButton
        set frdialog [visible := True]

findNextButton, findReplaceButton, findReplaceAllButton :: HPS.ServerHandle -> GUIContext -> IO ()
findNextButton model guiCtx@GUICtx{guiCode = txtCode,
                                   guiWin = win,
                                   guiSearch = search} =
    do
        s <- findReplaceDataGetFindString search
        fs <- findReplaceDataGetFlags search >>= buildFRFlags True
        mip <- findMatch s fs txtCode
        debugIO ("find/next", s, fs, mip)
        case mip of
            Nothing ->
                infoDialog win "Find Results" $ s ++ " not found."
            Just ip ->
                do
                    textCtrlSetSelection txtCode (length s + ip) ip
                    refreshExpr model guiCtx False 

findReplaceButton model guiCtx@GUICtx{guiCode = txtCode,
                                      guiWin = win,
                                      guiSearch = search} =
    do
        s <- findReplaceDataGetFindString search
        r <- findReplaceDataGetReplaceString search
        fs <- findReplaceDataGetFlags search >>= buildFRFlags True
        mip <- findMatch s fs txtCode
        debugIO ("replace", s, r, fs, mip)
        case mip of
            Nothing ->
                infoDialog win "Find Results" $ s ++ " not found."
            Just ip ->
                do
                    textCtrlReplace txtCode ip (length s + ip) r
                    textCtrlSetSelection txtCode (length r + ip) ip
                    refreshExpr model guiCtx False
        
findReplaceAllButton _model GUICtx{guiCode = txtCode,
                                   guiSearch = search} =
    do
        s <- findReplaceDataGetFindString search
        r <- findReplaceDataGetReplaceString search        
        fs <- findReplaceDataGetFlags search >>= buildFRFlags False
        debugIO ("all", s, r, fs)
        textCtrlSetInsertionPoint txtCode 0
        unfoldM_ $ do
                        mip <- findMatch s fs txtCode
                        case mip of
                            Nothing ->
                                return mip
                            Just ip ->
                                do
                                    textCtrlReplace txtCode ip (length s + ip) r
                                    textCtrlSetInsertionPoint txtCode $ length r + ip
                                    return mip
        
findMatch :: String -> FRFlags -> TextCtrl () -> IO (Maybe Int)
findMatch query flags txtCode =
    do
        txt <- get txtCode text
        ip <- textCtrlGetInsertionPoint txtCode
        let (substring, string) = if frfMatchCase flags
                                    then (query, txt)
                                    else (map toLower query, map toLower txt)
            funct = if frfGoingDown flags
                        then nextMatch (ip + 1)
                        else prevMatch ip
            (mip, wrapped) = funct substring string
        return $ if (not $ frfWrapSearch flags) && wrapped
                    then Nothing
                    else mip
        

prevMatch, nextMatch :: Int -> String -> String -> (Maybe Int, Bool)
prevMatch _ [] _ = (Nothing, True) -- When looking for nothing, that's what you get
prevMatch from substring string | length string < from || from <= 0 = prevMatch (length string) substring string
                                | otherwise =
                                        case nextMatch (fromBack from) (reverse substring) (reverse string) of
                                            (Nothing, wrapped) -> (Nothing, wrapped)
                                            (Just ri, wrapped) -> (Just $ fromBack (ri + length substring), wrapped)
    where fromBack x = length string - x

nextMatch _ [] _ = (Nothing, True) -- When looking for nothing, that's what you get
nextMatch from substring string | length substring > length string = (Nothing, True)
                                | length string <= from = nextMatch 0 substring string
                                | otherwise =
                                        let after = drop from string
                                            before = take (from + length substring) string
                                            aIndex = indexOf substring after
                                            bIndex = indexOf substring before
                                         in case aIndex of
                                                Just ai ->
                                                    (Just $ from + ai,  False)
                                                Nothing ->
                                                    case bIndex of
                                                        Nothing -> (Nothing, True)
                                                        Just bi -> (Just bi, True)
    
indexOf :: String -> String -> Maybe Int
indexOf substring string = findIndex (isPrefixOf substring) $ tails string