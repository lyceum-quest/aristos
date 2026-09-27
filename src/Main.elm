port module Main exposing (main)

import Browser
import Browser.Dom as Dom
import Browser.Events
import Browser.Navigation as Nav
import Conllu
import Dict exposing (Dict)
import Html exposing (Html, a, article, aside, button, div, footer, h1, h2, h3, header, input, label, main_, nav, option, p, section, select, span, text, textarea)
import Html.Attributes exposing (attribute, checked, class, classList, disabled, href, id, placeholder, rel, rows, selected, target, type_, value)
import Html.Events exposing (on, onClick, onInput)
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Process
import Route exposing (Route)
import Set exposing (Set)
import Task
import Time
import Url exposing (Url)


type Screen
    = LibraryScreen
    | WorkspaceScreen
    | SettingsScreen
    | HistoryScreen
    | AttemptComparisonScreen
    | ReaderScreen


type Preset
    = ReadPreset
    | AssistedPreset
    | IntensivePreset
    | CustomPreset


type SettingScope
    = GlobalScope
    | WorkScope
    | SessionScope


type Theme
    = DarkTheme
    | LightTheme


type ModuleId
    = GlossModule
    | MorphologyModule
    | DependencyModule
    | LiteralModule
    | ProseModule


type ModuleMode
    = ModuleOff
    | OnDemand
    | Suggested
    | EverySentence


type WorkspacePhase
    = Drafting
    | Compared
    | Rereading


type alias ModuleSettings =
    { gloss : ModuleMode
    , morphology : ModuleMode
    , dependency : ModuleMode
    , literal : ModuleMode
    , prose : ModuleMode
    }


type alias Draft =
    { glosses : Dict Int String
    , morphCase : String
    , morphNumber : String
    , morphGender : String
    , dependencyRoot : String
    , dependencyHead : String
    , dependencyRelation : String
    , literal : String
    , prose : String
    }


type alias Corpus =
    Conllu.Corpus


type alias CorpusSource =
    Conllu.CorpusSource


type alias Sentence =
    Conllu.Sentence


type alias CorpusToken =
    Conllu.CorpusToken


type alias Morphology =
    Conllu.Morphology


type alias Manifest =
    { version : Int
    , corpora : List ManifestEntry
    }


type alias ManifestEntry =
    { id : String
    , title : String
    , path : String
    , sentenceCount : Int
    , tokenCount : Int
    , source : CorpusSource
    }


type alias Coverage =
    { tokens : Int
    , glossed : Int
    , morphology : Int
    , sentences : Int
    , dependencies : Int
    , literal : Int
    , prose : Int
    }


type alias StorageResponse =
    { id : String
    , ok : Bool
    , value : Decode.Value
    }


type alias Model =
    { screen : Screen
    , corpus : Corpus
    , sentenceIndex : Int
    , selectedTokenId : Maybe Int
    , preset : Preset
    , scope : SettingScope
    , settings : ModuleSettings
    , activeModule : Maybe ModuleId
    , phase : WorkspacePhase
    , draft : Draft
    , previousDraft : Maybe Draft
    , skippedModules : List ModuleId
    , referenceRevealed : Bool
    , revisionParent : Maybe Int
    , attemptCount : Int
    , elapsedSeconds : Int
    , notice : Maybe String
    , theme : Theme
    , corpusReady : Bool
    , corpusLoadedFromNetwork : Bool
    , legacyManifestEntry : Maybe ManifestEntry
    , legacyCorpusRaw : Maybe String
    , library : List ManifestEntry
    , activeEntry : Maybe ManifestEntry
    , requestedWork : Maybe String
    , pendingRoute : Maybe Route
    , key : Nav.Key
    , currentPath : String
    , drafts : Dict Int Draft
    , positions : Dict String Int
    , readerGloss : Maybe ( Int, Int )
    , readerRevealed : Set Int
    , scrollGeneration : Int
    }


type Msg
    = ShowLibrary
    | ShowWorkspace
    | ShowSettings
    | ShowHistory
    | ShowAttemptComparison
    | PreviousSentence
    | NextSentence
    | JumpToChapter String
    | JumpToPassage String
    | Navigate Route
    | UrlRequested Browser.UrlRequest
    | UrlChanged Url
    | KeyPressed String String
    | ReaderTokenTapped Int Int
    | ReaderToggleTranslation Int
    | ReaderStep Int
    | ReaderScrolled
    | ReaderSettled Int
    | ReaderMeasured (Result Dom.Error ( Dom.Element, List Dom.Element ))
    | NoOp
    | SelectToken Int
    | SelectPreset Preset
    | SelectScope SettingScope
    | ToggleModule ModuleId
    | CycleModuleMode ModuleId
    | OpenModule ModuleId
    | CloseWorkbench
    | UpdateGloss Int String
    | UpdateMorphCase String
    | UpdateMorphNumber String
    | UpdateMorphGender String
    | UpdateDependencyRoot String
    | UpdateDependencyHead String
    | UpdateDependencyRelation String
    | UpdateLiteral String
    | UpdateProse String
    | SkipCurrentModule
    | RevealAnyway
    | SubmitCheckpoint
    | ReviseAttempt
    | BeginReread
    | FinishPassage
    | ShowNotice String
    | DismissNotice
    | ToggleTheme
    | Tick Time.Posix
    | GotManifest (Result Http.Error Manifest)
    | GotCorpus ManifestEntry (Result Http.Error String)
    | GotStorage Decode.Value


port storageRequest : Encode.Value -> Cmd msg


port storageResponse : (Decode.Value -> msg) -> Sub msg


main : Program Decode.Value Model Msg
main =
    Browser.application
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = \model -> { title = documentTitle model, body = [ view model ] }
        , onUrlRequest = UrlRequested
        , onUrlChange = UrlChanged
        }


init : Decode.Value -> Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    let
        ( model, routeCmd ) =
            applyRoute (Route.fromUrl url |> Maybe.withDefault Route.Library)
                { screen = LibraryScreen
                , corpus = fallbackCorpus
                , sentenceIndex = 0
                , selectedTokenId = Nothing
                , preset = AssistedPreset
                , scope = SessionScope
                , settings = assistedSettings
                , activeModule = Nothing
                , phase = Drafting
                , draft = emptyDraft
                , previousDraft = Nothing
                , skippedModules = []
                , referenceRevealed = False
                , revisionParent = Nothing
                , attemptCount = 0
                , elapsedSeconds = 0
                , notice = Nothing
                , theme = DarkTheme
                , corpusReady = False
                , corpusLoadedFromNetwork = False
                , legacyManifestEntry = Nothing
                , legacyCorpusRaw = Nothing
                , library = []
                , activeEntry = Nothing
                , requestedWork = Nothing
                , pendingRoute = Nothing
                , key = key
                , currentPath = urlPath url
                , drafts = Dict.empty
                , positions = Dict.empty
                , readerGloss = Nothing
                , readerRevealed = Set.empty
                , scrollGeneration = 0
                }
    in
    ( model
    , Cmd.batch
        [ fetchManifest
        , routeCmd
        , storageGet "theme" "metadata" "theme"
        , storageGet "positions" "metadata" "positions"
        , storageGet "cached-corpus" "metadata" "cached-corpus"
        , storageGet "legacy-manifest" "metadata" "preload-manifest"
        , storageGet "legacy-corpus" "corpora" "anabasis"
        ]
    )


documentTitle : Model -> String
documentTitle model =
    case ( model.screen, model.activeEntry ) of
        ( LibraryScreen, _ ) ->
            "Aristos · Greek reading workspace"

        ( SettingsScreen, _ ) ->
            "Modules · Aristos"

        ( _, Just entry ) ->
            entry.title ++ " " ++ String.fromInt (model.sentenceIndex + 1) ++ " · Aristos"

        ( _, Nothing ) ->
            "Aristos"


{-| The route part of a URL in the same form `Route.toPath` produces.
-}
urlPath : Url -> String
urlPath url =
    case url.fragment of
        Just fragment ->
            if String.isEmpty fragment then
                "#/"

            else
                "#" ++ fragment

        Nothing ->
            "#/"


emptyDraft : Draft
emptyDraft =
    { glosses = Dict.empty
    , morphCase = "—"
    , morphNumber = "—"
    , morphGender = "—"
    , dependencyRoot = "—"
    , dependencyHead = "—"
    , dependencyRelation = "—"
    , literal = ""
    , prose = ""
    }


corpusSourceDecoder : Decode.Decoder CorpusSource
corpusSourceDecoder =
    Decode.map5
        (\name url commit license edition ->
            { name = name
            , url = url
            , commit = commit
            , license = license
            , edition = edition
            }
        )
        (Decode.field "name" Decode.string)
        (Decode.field "url" Decode.string)
        (Decode.field "commit" Decode.string)
        (Decode.field "license" Decode.string)
        (Decode.field "edition" Decode.string)


manifestDecoder : Decode.Decoder Manifest
manifestDecoder =
    Decode.map2 Manifest
        (Decode.field "version" Decode.int)
        (Decode.field "corpora" (Decode.list manifestEntryDecoder))


manifestEntryDecoder : Decode.Decoder ManifestEntry
manifestEntryDecoder =
    -- Title and counts default so entries cached by earlier builds still decode.
    Decode.map6 ManifestEntry
        (Decode.field "id" Decode.string)
        (Decode.oneOf [ Decode.field "title" Decode.string, Decode.field "id" Decode.string ])
        (Decode.field "path" Decode.string)
        (Decode.oneOf [ Decode.field "sentenceCount" Decode.int, Decode.succeed 0 ])
        (Decode.oneOf [ Decode.field "tokenCount" Decode.int, Decode.succeed 0 ])
        (Decode.field "source" corpusSourceDecoder)


storageResponseDecoder : Decode.Decoder StorageResponse
storageResponseDecoder =
    Decode.map3 StorageResponse
        (Decode.field "id" Decode.string)
        (Decode.field "ok" Decode.bool)
        (Decode.field "value" Decode.value)


cachedCorpusDecoder : Decode.Decoder ( ManifestEntry, String )
cachedCorpusDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "entry" manifestEntryDecoder)
        (Decode.field "raw" Decode.string)


fallbackCorpus : Corpus
fallbackCorpus =
    { source =
        { name = ""
        , url = ""
        , commit = ""
        , license = ""
        , edition = ""
        }
    , sentences =
        [ { id = "missing"
          , chapter = 1
          , verse = "1"
          , text = "No corpus loaded."
          , literalTranslation = ""
          , proseTranslation = ""
          , tokens = []
          }
        ]
    }


fallbackToken : Int -> String -> String -> String -> String -> String -> String -> String -> Int -> String -> String -> Bool -> CorpusToken
fallbackToken tokenId form lemma upos summary case_ number gender head relation gloss spaceAfter =
    { id = tokenId
    , form = form
    , lemma = lemma
    , upos = upos
    , morphology =
        { summary = summary
        , case_ = case_
        , number = number
        , gender = gender
        }
    , head = head
    , relation = relation
    , gloss = gloss
    , spaceAfter = spaceAfter
    }


readSettings : ModuleSettings
readSettings =
    { gloss = OnDemand
    , morphology = ModuleOff
    , dependency = ModuleOff
    , literal = ModuleOff
    , prose = ModuleOff
    }


assistedSettings : ModuleSettings
assistedSettings =
    { gloss = Suggested
    , morphology = OnDemand
    , dependency = ModuleOff
    , literal = ModuleOff
    , prose = Suggested
    }


intensiveSettings : ModuleSettings
intensiveSettings =
    { gloss = Suggested
    , morphology = Suggested
    , dependency = ModuleOff
    , literal = Suggested
    , prose = Suggested
    }


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ storageResponse GotStorage
        , if model.screen == WorkspaceScreen then
            Time.every 1000 Tick

          else
            Sub.none
        , if model.screen == WorkspaceScreen || model.screen == ReaderScreen then
            Browser.Events.onKeyDown keyDecoder

          else
            Sub.none
        ]


{-| Shortcuts ignore modified keys; the handler also ignores keys typed into form fields.
-}
keyDecoder : Decode.Decoder Msg
keyDecoder =
    Decode.map4
        (\key tag ctrl meta -> ( key, tag, ctrl || meta ))
        (Decode.field "key" Decode.string)
        (Decode.oneOf [ Decode.at [ "target", "tagName" ] Decode.string, Decode.succeed "" ])
        (Decode.field "ctrlKey" Decode.bool)
        (Decode.field "metaKey" Decode.bool)
        |> Decode.andThen
            (\( key, tag, modified ) ->
                if modified then
                    Decode.fail "modified key"

                else
                    Decode.succeed (KeyPressed key tag)
            )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        ( next, cmd ) =
            updateModel msg model
    in
    syncUrl (isUrlChange msg || (model.screen == ReaderScreen && next.screen == ReaderScreen)) next cmd


isUrlChange : Msg -> Bool
isUrlChange msg =
    case msg of
        UrlChanged _ ->
            True

        _ ->
            False


updateModel : Msg -> Model -> ( Model, Cmd Msg )
updateModel msg model =
    case msg of
        GotManifest result ->
            handleManifest result model

        GotCorpus entry result ->
            handleFetchedCorpus entry result model

        GotStorage value ->
            showPending (handleStorageResponse value model)

        Navigate route ->
            ( model, Nav.pushUrl model.key (Route.toPath route) )

        UrlRequested (Browser.Internal url) ->
            ( model, Nav.pushUrl model.key (Url.toString url) )

        UrlRequested (Browser.External href) ->
            ( model, Nav.load href )

        UrlChanged url ->
            if urlPath url == model.currentPath then
                ( model, Cmd.none )

            else
                applyRoute (Route.fromUrl url |> Maybe.withDefault Route.Library) { model | currentPath = urlPath url }

        JumpToPassage passage ->
            case String.toInt passage of
                Just number ->
                    ( moveToSentence (number - 1) model, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        KeyPressed key tag ->
            if List.member tag [ "INPUT", "TEXTAREA", "SELECT" ] then
                ( model, Cmd.none )

            else
                handleShortcut key model

        ReaderTokenTapped sentenceIndex tokenId ->
            ( { model
                | readerGloss =
                    if model.readerGloss == Just ( sentenceIndex, tokenId ) then
                        Nothing

                    else
                        Just ( sentenceIndex, tokenId )
                , sentenceIndex = sentenceIndex
              }
            , Cmd.none
            )

        ReaderToggleTranslation sentenceIndex ->
            ( { model
                | readerRevealed =
                    if Set.member sentenceIndex model.readerRevealed then
                        Set.remove sentenceIndex model.readerRevealed

                    else
                        Set.insert sentenceIndex model.readerRevealed
                , sentenceIndex = sentenceIndex
              }
            , Cmd.none
            )

        ReaderStep delta ->
            let
                target =
                    clamp 0 (List.length model.corpus.sentences - 1) (model.sentenceIndex + delta)
            in
            ( { model | sentenceIndex = target, readerGloss = Nothing }, scrollToSentence target )

        ReaderScrolled ->
            let
                generation =
                    model.scrollGeneration + 1
            in
            ( { model | scrollGeneration = generation }
            , Process.sleep 200 |> Task.perform (\_ -> ReaderSettled generation)
            )

        ReaderSettled generation ->
            if generation /= model.scrollGeneration then
                ( model, Cmd.none )

            else
                ( model, measureReader model )

        ReaderMeasured (Ok ( container, sentences )) ->
            let
                top =
                    container.element.y + 72

                current =
                    sentences
                        |> List.indexedMap Tuple.pair
                        |> List.filter (\( _, element ) -> element.element.y + element.element.height > top)
                        |> List.head
                        |> Maybe.map Tuple.first
            in
            ( { model | sentenceIndex = Maybe.withDefault model.sentenceIndex current }, Cmd.none )

        ReaderMeasured (Err _) ->
            ( model, Cmd.none )

        NoOp ->
            ( model, Cmd.none )

        _ ->
            updateInteraction msg model


handleShortcut : String -> Model -> ( Model, Cmd Msg )
handleShortcut key model =
    case ( model.screen, key ) of
        ( WorkspaceScreen, "ArrowLeft" ) ->
            ( moveToSentence (model.sentenceIndex - 1) model, Cmd.none )

        ( WorkspaceScreen, "k" ) ->
            ( moveToSentence (model.sentenceIndex - 1) model, Cmd.none )

        ( WorkspaceScreen, "ArrowRight" ) ->
            ( moveToSentence (model.sentenceIndex + 1) model, Cmd.none )

        ( WorkspaceScreen, "j" ) ->
            ( moveToSentence (model.sentenceIndex + 1) model, Cmd.none )

        ( ReaderScreen, "j" ) ->
            updateModel (ReaderStep 1) model

        ( ReaderScreen, "ArrowRight" ) ->
            updateModel (ReaderStep 1) model

        ( ReaderScreen, "k" ) ->
            updateModel (ReaderStep -1) model

        ( ReaderScreen, "ArrowLeft" ) ->
            updateModel (ReaderStep -1) model

        ( ReaderScreen, "Escape" ) ->
            if model.readerGloss /= Nothing then
                ( { model | readerGloss = Nothing }, Cmd.none )

            else
                ( { model | screen = WorkspaceScreen }, Cmd.none )

        _ ->
            ( model, Cmd.none )



-- ROUTING


{-| Shows a route whose work is loaded, or records it and loads the work first.
-}
applyRoute : Route -> Model -> ( Model, Cmd Msg )
applyRoute route model =
    case route of
        Route.Library ->
            ( { model | screen = LibraryScreen, pendingRoute = Nothing }, Cmd.none )

        Route.Settings ->
            ( { model | screen = SettingsScreen, pendingRoute = Nothing }, Cmd.none )

        Route.WorkLanding work ->
            ( model, Nav.replaceUrl model.key (Route.toPath (Route.Study work (Dict.get work model.positions |> Maybe.withDefault 1))) )

        _ ->
            case routeWork route of
                Just work ->
                    if model.corpusReady && Maybe.map .id model.activeEntry == Just work then
                        showRoute route model

                    else
                        requestWork work route model

                Nothing ->
                    ( model, Cmd.none )


routeWork : Route -> Maybe String
routeWork route =
    case route of
        Route.Study work _ ->
            Just work

        Route.Reader work _ ->
            Just work

        Route.History work _ ->
            Just work

        Route.Comparison work _ ->
            Just work

        _ ->
            Nothing


requestWork : String -> Route -> Model -> ( Model, Cmd Msg )
requestWork work route model =
    let
        waiting =
            { model | requestedWork = Just work, pendingRoute = Just route }
    in
    if List.isEmpty model.library then
        -- handleManifest resumes this request once the library arrives.
        ( waiting, Cmd.none )

    else
        case List.filter (\entry -> entry.id == work) model.library of
            entry :: _ ->
                ( { waiting | notice = Just ("Loading " ++ entry.title ++ "…") }, fetchCorpus entry )

            [] ->
                ( { model | screen = LibraryScreen, pendingRoute = Nothing, notice = Just ("No work named “" ++ work ++ "” is bundled.") }, Cmd.none )


showRoute : Route -> Model -> ( Model, Cmd Msg )
showRoute route model =
    let
        settled =
            { model | pendingRoute = Nothing }

        clampIndex passage =
            clamp 0 (List.length model.corpus.sentences - 1) (passage - 1)

        at passage screen =
            let
                index =
                    clampIndex passage

                moved =
                    if index == settled.sentenceIndex then
                        settled

                    else
                        moveToSentence index settled
            in
            ( { moved | screen = screen }, Cmd.none )
    in
    case route of
        Route.Study _ passage ->
            at passage WorkspaceScreen

        Route.History _ passage ->
            at passage HistoryScreen

        Route.Comparison _ passage ->
            at passage AttemptComparisonScreen

        Route.Reader work passage ->
            let
                index =
                    clampIndex (passage |> Maybe.withDefault (Dict.get work model.positions |> Maybe.withDefault (model.sentenceIndex + 1)))
            in
            ( { settled | screen = ReaderScreen, sentenceIndex = index, readerGloss = Nothing }, scrollToSentence index )

        _ ->
            ( settled, Cmd.none )


{-| The URL follows the model. Reader scrolling and route normalization replace the history entry; other moves push one.
-}
syncUrl : Bool -> Model -> Cmd Msg -> ( Model, Cmd Msg )
syncUrl replace model cmd =
    case ( model.pendingRoute, pathFor model ) of
        ( Nothing, Just path ) ->
            if path == model.currentPath then
                ( model, cmd )

            else
                ( { model | currentPath = path }
                , Cmd.batch
                    [ cmd
                    , if replace then
                        Nav.replaceUrl model.key path

                      else
                        Nav.pushUrl model.key path
                    , savePosition model
                    ]
                )

        _ ->
            ( model, cmd )


pathFor : Model -> Maybe String
pathFor model =
    let
        passage =
            model.sentenceIndex + 1

        forWork toRoute =
            model.activeEntry |> Maybe.map (\entry -> Route.toPath (toRoute entry.id))
    in
    case model.screen of
        LibraryScreen ->
            Just (Route.toPath Route.Library)

        SettingsScreen ->
            Just (Route.toPath Route.Settings)

        WorkspaceScreen ->
            forWork (\work -> Route.Study work passage)

        ReaderScreen ->
            forWork (\work -> Route.Reader work (Just passage))

        HistoryScreen ->
            forWork (\work -> Route.History work passage)

        AttemptComparisonScreen ->
            forWork (\work -> Route.Comparison work passage)


savePosition : Model -> Cmd Msg
savePosition model =
    case model.activeEntry of
        Just entry ->
            if model.screen == WorkspaceScreen || model.screen == ReaderScreen then
                storagePut "save-positions" "metadata"
                    (Encode.object
                        [ ( "key", Encode.string "positions" )
                        , ( "value", Encode.dict identity Encode.int (Dict.insert entry.id (model.sentenceIndex + 1) model.positions) )
                        ]
                    )

            else
                Cmd.none

        Nothing ->
            Cmd.none



-- READER SCROLLING


readerScrollId : String
readerScrollId =
    "reader-scroll"


sentenceElementId : Int -> String
sentenceElementId index =
    "passage-" ++ String.fromInt (index + 1)


scrollToSentence : Int -> Cmd Msg
scrollToSentence index =
    Task.map3
        (\container viewport sentence -> viewport.viewport.y + sentence.element.y - container.element.y - 24)
        (Dom.getElement readerScrollId)
        (Dom.getViewportOf readerScrollId)
        (Dom.getElement (sentenceElementId index))
        |> Task.andThen (\y -> Dom.setViewportOf readerScrollId 0 y)
        |> Task.attempt (\_ -> NoOp)


measureReader : Model -> Cmd Msg
measureReader model =
    Task.map2 Tuple.pair
        (Dom.getElement readerScrollId)
        (model.corpus.sentences |> List.indexedMap (\index _ -> Dom.getElement (sentenceElementId index)) |> Task.sequence)
        |> Task.attempt ReaderMeasured


updateInteraction : Msg -> Model -> ( Model, Cmd Msg )
updateInteraction msg model =
    ( case msg of
        ShowLibrary ->
            { model | screen = LibraryScreen, notice = Nothing }

        ShowWorkspace ->
            if model.corpusReady then
                { model | screen = WorkspaceScreen, notice = Nothing }

            else
                { model | notice = Just "The local corpus is still loading." }

        ShowSettings ->
            { model | screen = SettingsScreen, notice = Nothing }

        ShowHistory ->
            { model | screen = HistoryScreen, notice = Nothing }

        ShowAttemptComparison ->
            if model.attemptCount < 2 then
                { model | notice = Just "Submit a revision before comparing two attempts." }

            else
                { model | screen = AttemptComparisonScreen, notice = Nothing }

        PreviousSentence ->
            moveToSentence (model.sentenceIndex - 1) model

        NextSentence ->
            moveToSentence (model.sentenceIndex + 1) model

        JumpToChapter chapterValue ->
            case String.toInt chapterValue of
                Just chapter ->
                    case firstSentenceIndexForChapter chapter model.corpus.sentences of
                        Just sentenceIndex ->
                            moveToSentence sentenceIndex model

                        Nothing ->
                            model

                Nothing ->
                    model

        SelectToken tokenId ->
            { model
                | selectedTokenId = Just tokenId
                , activeModule = Just MorphologyModule
                , draft = resetMorphologyDraft model.draft
            }

        SelectPreset preset ->
            { model
                | preset = preset
                , settings = settingsForPreset preset model.settings
                , activeModule = firstEnabled (settingsForPreset preset model.settings)
            }

        SelectScope scope ->
            { model | scope = scope }

        ToggleModule moduleId ->
            let
                updatedSettings =
                    setModuleMode moduleId
                        (if moduleMode moduleId model.settings == ModuleOff then
                            Suggested

                         else
                            ModuleOff
                        )
                        model.settings
            in
            { model
                | preset = CustomPreset
                , settings = updatedSettings
                , activeModule = ensureActiveModule model.activeModule updatedSettings
            }

        CycleModuleMode moduleId ->
            { model
                | preset = CustomPreset
                , settings = setModuleMode moduleId (nextMode (moduleMode moduleId model.settings)) model.settings
            }

        OpenModule moduleId ->
            if moduleMode moduleId model.settings == ModuleOff || model.phase == Rereading then
                model

            else
                { model | activeModule = Just moduleId, notice = Nothing }

        CloseWorkbench ->
            { model | activeModule = Nothing }

        UpdateGloss tokenId entered ->
            updateDraft (\draft -> { draft | glosses = Dict.insert tokenId entered draft.glosses }) model

        UpdateMorphCase entered ->
            updateDraft (\draft -> { draft | morphCase = entered }) model

        UpdateMorphNumber entered ->
            updateDraft (\draft -> { draft | morphNumber = entered }) model

        UpdateMorphGender entered ->
            updateDraft (\draft -> { draft | morphGender = entered }) model

        UpdateDependencyRoot entered ->
            updateDraft (\draft -> { draft | dependencyRoot = entered }) model

        UpdateDependencyHead entered ->
            updateDraft (\draft -> { draft | dependencyHead = entered }) model

        UpdateDependencyRelation entered ->
            updateDraft (\draft -> { draft | dependencyRelation = entered }) model

        UpdateLiteral entered ->
            updateDraft (\draft -> { draft | literal = entered }) model

        UpdateProse entered ->
            updateDraft (\draft -> { draft | prose = entered }) model

        SkipCurrentModule ->
            case model.activeModule of
                Just moduleId ->
                    { model
                        | skippedModules = addUniqueModule moduleId model.skippedModules
                        , activeModule = Nothing
                        , notice = Just (moduleName moduleId ++ " skipped for this checkpoint—not marked incorrect.")
                    }

                Nothing ->
                    model

        RevealAnyway ->
            { model
                | referenceRevealed = True
                , notice = Just "Reference revealed. This checkpoint will be recorded as assisted."
            }

        SubmitCheckpoint ->
            if model.phase /= Drafting then
                model

            else
                { model
                    | phase = Compared
                    , attemptCount = model.attemptCount + 1
                    , notice = Just "Checkpoint submitted. This attempt is now immutable."
                    , revisionParent = Nothing
                }

        ReviseAttempt ->
            if model.phase /= Compared then
                model

            else
                { model
                    | phase = Drafting
                    , previousDraft = Just model.draft
                    , revisionParent = Just model.attemptCount
                    , referenceRevealed = True
                    , notice = Just ("Revision started from attempt " ++ twoDigit model.attemptCount ++ ". Submitting creates a linked child attempt.")
                }

        BeginReread ->
            { model
                | phase = Rereading
                , activeModule = Nothing
                , notice = Just "Feedback closed. Read the Greek straight through."
            }

        FinishPassage ->
            if model.sentenceIndex < List.length model.corpus.sentences - 1 then
                moveToSentence (model.sentenceIndex + 1) model
                    |> withNotice ("Passage reread recorded. The next " ++ workTitle model ++ " passage is ready.")

            else
                { model | screen = LibraryScreen, notice = Just (workTitle model ++ " reread recorded. You reached the end of the bundled text.") }

        ShowNotice notice ->
            { model | notice = Just notice }

        DismissNotice ->
            { model | notice = Nothing }

        ToggleTheme ->
            { model
                | theme =
                    if model.theme == DarkTheme then
                        LightTheme

                    else
                        DarkTheme
            }

        Tick _ ->
            { model | elapsedSeconds = model.elapsedSeconds + 1 }

        GotManifest _ ->
            model

        JumpToPassage _ ->
            model

        Navigate _ ->
            model

        UrlRequested _ ->
            model

        UrlChanged _ ->
            model

        KeyPressed _ _ ->
            model

        ReaderTokenTapped _ _ ->
            model

        ReaderToggleTranslation _ ->
            model

        ReaderStep _ ->
            model

        ReaderScrolled ->
            model

        ReaderSettled _ ->
            model

        ReaderMeasured _ ->
            model

        NoOp ->
            model

        GotCorpus _ _ ->
            model

        GotStorage _ ->
            model
    , commandFor msg model
    )


commandFor : Msg -> Model -> Cmd Msg
commandFor msg model =
    case msg of
        ToggleTheme ->
            storagePut "theme" "metadata"
                (Encode.object
                    [ ( "key", Encode.string "theme" )
                    , ( "value"
                      , Encode.string
                            (if model.theme == DarkTheme then
                                "light"

                             else
                                "dark"
                            )
                      )
                    ]
                )

        SubmitCheckpoint ->
            if model.phase == Drafting then
                storagePut "save-progress" "progress"
                    (encodeProgress False (model.attemptCount + 1) model)

            else
                Cmd.none

        FinishPassage ->
            storagePut "save-progress" "progress"
                (encodeProgress True model.attemptCount model)

        _ ->
            Cmd.none


fetchManifest : Cmd Msg
fetchManifest =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Cache-Control" "no-cache" ]
        , url = "/preload/corpora.json"
        , body = Http.emptyBody
        , expect = Http.expectJson GotManifest manifestDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


handleManifest : Result Http.Error Manifest -> Model -> ( Model, Cmd Msg )
handleManifest result model =
    case result of
        Ok manifest ->
            if manifest.version /= 1 then
                ( model, Cmd.none )

            else
                -- A work URL opened before the library arrived loads now.
                case ( model.pendingRoute |> Maybe.andThen routeWork, model.corpusReady ) of
                    ( Just work, False ) ->
                        case model.pendingRoute of
                            Just route ->
                                requestWork work route { model | library = manifest.corpora }

                            Nothing ->
                                ( { model | library = manifest.corpora }, Cmd.none )

                    _ ->
                        ( { model | library = manifest.corpora }, Cmd.none )

        Err _ ->
            ( model, Cmd.none )


fetchCorpus : ManifestEntry -> Cmd Msg
fetchCorpus entry =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Cache-Control" "no-cache" ]
        , url = "/preload/" ++ entry.path
        , body = Http.emptyBody
        , expect = Http.expectString (GotCorpus entry)
        , timeout = Nothing
        , tracker = Nothing
        }


handleFetchedCorpus : ManifestEntry -> Result Http.Error String -> Model -> ( Model, Cmd Msg )
handleFetchedCorpus entry result model =
    case result of
        Ok raw ->
            case Conllu.parse entry.source raw of
                Ok corpus ->
                    if model.requestedWork /= Just entry.id then
                        ( model, Cmd.none )

                    else
                        let
                            -- A fresh download of the work already shown from cache keeps the reader's place.
                            installed =
                                if model.corpusReady && Maybe.map .id model.activeEntry == Just entry.id then
                                    { model
                                        | corpus = corpus
                                        , activeEntry = Just entry
                                        , corpusLoadedFromNetwork = True
                                        , sentenceIndex = clamp 0 (List.length corpus.sentences - 1) model.sentenceIndex
                                    }

                                else
                                    installCorpus True entry corpus model

                            ( shown, routeCmd ) =
                                showPending installed
                        in
                        ( shown
                        , Cmd.batch
                            [ routeCmd
                            , storagePut "cache-corpus" "metadata"
                                (Encode.object
                                    [ ( "key", Encode.string "cached-corpus" )
                                    , ( "value"
                                      , Encode.object
                                            [ ( "entry", encodeManifestEntry entry )
                                            , ( "raw", Encode.string raw )
                                            ]
                                      )
                                    ]
                                )
                            , storagePut "cache-manifest" "metadata"
                                (Encode.object
                                    [ ( "key", Encode.string "preload-manifest" )
                                    , ( "value"
                                      , Encode.object
                                            [ ( "version", Encode.int 1 )
                                            , ( "corpora", Encode.list encodeManifestEntry [ entry ] )
                                            ]
                                      )
                                    ]
                                )
                            , storagePut "cache-raw-corpus" "corpora"
                                (Encode.object
                                    [ ( "id", Encode.string entry.id )
                                    , ( "path", Encode.string entry.path )
                                    , ( "content", Encode.string raw )
                                    ]
                                )
                            ]
                        )

                Err problem ->
                    ( { model | pendingRoute = Nothing, notice = Just (entry.title ++ " could not be parsed: " ++ problem) }, Cmd.none )

        Err _ ->
            if model.requestedWork == Just entry.id then
                ( { model | pendingRoute = Nothing, notice = Just (entry.title ++ " could not be downloaded. Try again.") }, Cmd.none )

            else
                ( model, Cmd.none )


handleStorageResponse : Decode.Value -> Model -> Model
handleStorageResponse value model =
    case Decode.decodeValue storageResponseDecoder value of
        Ok response ->
            if not response.ok then
                model

            else if response.id == "positions" then
                case Decode.decodeValue (Decode.field "value" (Decode.dict Decode.int)) response.value of
                    Ok positions ->
                        { model | positions = Dict.union model.positions positions }

                    Err _ ->
                        model

            else if response.id == "theme" then
                case Decode.decodeValue (Decode.field "value" Decode.string) response.value of
                    Ok "light" ->
                        { model | theme = LightTheme }

                    Ok "dark" ->
                        { model | theme = DarkTheme }

                    _ ->
                        model

            else if response.id == "cached-corpus" && not model.corpusLoadedFromNetwork then
                case Decode.decodeValue (Decode.field "value" cachedCorpusDecoder) response.value of
                    Ok ( entry, raw ) ->
                        useCachedCorpus entry raw model

                    Err _ ->
                        model

            else if response.id == "legacy-manifest" then
                case Decode.decodeValue (Decode.field "value" manifestDecoder) response.value of
                    Ok manifest ->
                        { model | legacyManifestEntry = List.head manifest.corpora }
                            |> loadLegacyCache

                    Err _ ->
                        model

            else if response.id == "legacy-corpus" then
                case Decode.decodeValue (Decode.field "content" Decode.string) response.value of
                    Ok raw ->
                        { model | legacyCorpusRaw = Just raw }
                            |> loadLegacyCache

                    Err _ ->
                        model

            else
                model

        Err _ ->
            model


useCachedCorpus : ManifestEntry -> String -> Model -> Model
useCachedCorpus entry raw model =
    case ( model.requestedWork == Just entry.id && not model.corpusReady, Conllu.parse entry.source raw ) of
        ( True, Ok corpus ) ->
            installCorpus False entry corpus model

        _ ->
            model


installCorpus : Bool -> ManifestEntry -> Corpus -> Model -> Model
installCorpus loadedFromNetwork entry corpus model =
    { model
        | notice = Nothing
        , activeEntry = Just entry
        , corpus = corpus
        , corpusReady = True
        , corpusLoadedFromNetwork = model.corpusLoadedFromNetwork || loadedFromNetwork
        , sentenceIndex = 0
        , selectedTokenId = Nothing
        , activeModule = Nothing
        , phase = Drafting
        , draft = emptyDraft
        , drafts = Dict.empty
        , previousDraft = Nothing
        , skippedModules = []
        , referenceRevealed = False
        , revisionParent = Nothing
        , attemptCount = 0
        , elapsedSeconds = 0
        , readerGloss = Nothing
        , readerRevealed = Set.empty
    }


{-| Shows the route that was waiting for this work to load.
-}
showPending : Model -> ( Model, Cmd Msg )
showPending model =
    case model.pendingRoute of
        Just route ->
            if model.corpusReady && Maybe.map .id model.activeEntry == routeWork route then
                showRoute route model

            else
                ( model, Cmd.none )

        Nothing ->
            ( model, Cmd.none )


loadLegacyCache : Model -> Model
loadLegacyCache model =
    if model.corpusReady then
        model

    else
        case ( model.legacyManifestEntry, model.legacyCorpusRaw ) of
            ( Just entry, Just raw ) ->
                useCachedCorpus entry raw model

            _ ->
                model


storageGet : String -> String -> String -> Cmd msg
storageGet requestId store key =
    storageRequest
        (Encode.object
            [ ( "id", Encode.string requestId )
            , ( "operation", Encode.string "get" )
            , ( "store", Encode.string store )
            , ( "key", Encode.string key )
            ]
        )


storagePut : String -> String -> Encode.Value -> Cmd msg
storagePut requestId store storedValue =
    storageRequest
        (Encode.object
            [ ( "id", Encode.string requestId )
            , ( "operation", Encode.string "put" )
            , ( "store", Encode.string store )
            , ( "value", storedValue )
            ]
        )


encodeManifestEntry : ManifestEntry -> Encode.Value
encodeManifestEntry entry =
    Encode.object
        [ ( "id", Encode.string entry.id )
        , ( "title", Encode.string entry.title )
        , ( "path", Encode.string entry.path )
        , ( "sentenceCount", Encode.int entry.sentenceCount )
        , ( "tokenCount", Encode.int entry.tokenCount )
        , ( "source", encodeCorpusSource entry.source )
        ]


encodeCorpusSource : CorpusSource -> Encode.Value
encodeCorpusSource source =
    Encode.object
        [ ( "name", Encode.string source.name )
        , ( "url", Encode.string source.url )
        , ( "commit", Encode.string source.commit )
        , ( "license", Encode.string source.license )
        , ( "edition", Encode.string source.edition )
        ]


encodeProgress : Bool -> Int -> Model -> Encode.Value
encodeProgress completed attemptCount model =
    Encode.object
        [ ( "id", Encode.string (currentSentence model).id )
        , ( "sentenceIndex", Encode.int model.sentenceIndex )
        , ( "attemptCount", Encode.int attemptCount )
        , ( "elapsedSeconds", Encode.int model.elapsedSeconds )
        , ( "completed", Encode.bool completed )
        ]


moveToSentence : Int -> Model -> Model
moveToSentence sentenceIndex model =
    if sentenceIndex < 0 || sentenceIndex >= List.length model.corpus.sentences then
        model

    else
        let
            -- An unsubmitted draft stays with its passage for this visit.
            drafts =
                if model.phase == Drafting && model.draft /= emptyDraft then
                    Dict.insert model.sentenceIndex model.draft model.drafts

                else
                    Dict.remove model.sentenceIndex model.drafts
        in
        { model
            | screen = WorkspaceScreen
            , sentenceIndex = sentenceIndex
            , selectedTokenId = Nothing
            , activeModule = Nothing
            , phase = Drafting
            , draft = Dict.get sentenceIndex drafts |> Maybe.withDefault emptyDraft
            , drafts = drafts
            , previousDraft = Nothing
            , skippedModules = []
            , referenceRevealed = False
            , revisionParent = Nothing
            , attemptCount = 0
            , elapsedSeconds = 0
            , notice = Nothing
        }


withNotice : String -> Model -> Model
withNotice notice model =
    { model | notice = Just notice }


resetMorphologyDraft : Draft -> Draft
resetMorphologyDraft draft =
    { draft
        | morphCase = "—"
        , morphNumber = "—"
        , morphGender = "—"
    }


firstSentenceIndexForChapter : Int -> List Sentence -> Maybe Int
firstSentenceIndexForChapter chapter sentences =
    sentences
        |> List.indexedMap Tuple.pair
        |> List.filter (\( _, sentence ) -> sentence.chapter == chapter)
        |> List.head
        |> Maybe.map Tuple.first


corpusChapters : List Sentence -> List Int
corpusChapters sentences =
    sentences
        |> List.map .chapter
        |> List.foldl
            (\chapter chapters ->
                if List.member chapter chapters then
                    chapters

                else
                    chapter :: chapters
            )
            []
        |> List.sort


sourceDetails : CorpusSource -> String
sourceDetails source =
    [ source.edition
    , source.license
    , if String.isEmpty source.commit then
        ""

      else
        "source " ++ String.left 12 source.commit
    ]
        |> List.filter (not << String.isEmpty)
        |> String.join " · "


updateDraft : (Draft -> Draft) -> Model -> Model
updateDraft change model =
    if model.phase == Drafting then
        { model | draft = change model.draft }

    else
        model


settingsForPreset : Preset -> ModuleSettings -> ModuleSettings
settingsForPreset preset current =
    case preset of
        ReadPreset ->
            readSettings

        AssistedPreset ->
            assistedSettings

        IntensivePreset ->
            intensiveSettings

        CustomPreset ->
            current


firstEnabled : ModuleSettings -> Maybe ModuleId
firstEnabled settings =
    [ GlossModule, MorphologyModule, LiteralModule, ProseModule ]
        |> List.filter (\moduleId -> moduleMode moduleId settings /= ModuleOff)
        |> List.head


ensureActiveModule : Maybe ModuleId -> ModuleSettings -> Maybe ModuleId
ensureActiveModule active settings =
    case active of
        Just moduleId ->
            if moduleMode moduleId settings == ModuleOff then
                firstEnabled settings

            else
                active

        Nothing ->
            Nothing


nextMode : ModuleMode -> ModuleMode
nextMode mode =
    case mode of
        ModuleOff ->
            OnDemand

        OnDemand ->
            Suggested

        Suggested ->
            EverySentence

        EverySentence ->
            OnDemand


moduleMode : ModuleId -> ModuleSettings -> ModuleMode
moduleMode moduleId settings =
    case moduleId of
        GlossModule ->
            settings.gloss

        MorphologyModule ->
            settings.morphology

        DependencyModule ->
            settings.dependency

        LiteralModule ->
            settings.literal

        ProseModule ->
            settings.prose


setModuleMode : ModuleId -> ModuleMode -> ModuleSettings -> ModuleSettings
setModuleMode moduleId mode settings =
    case moduleId of
        GlossModule ->
            { settings | gloss = mode }

        MorphologyModule ->
            { settings | morphology = mode }

        DependencyModule ->
            { settings | dependency = mode }

        LiteralModule ->
            { settings | literal = mode }

        ProseModule ->
            { settings | prose = mode }


view : Model -> Html Msg
view model =
    div
        [ classList
            [ ( "app-shell", True )
            , ( "dark-theme", model.theme == DarkTheme )
            , ( "light-theme", model.theme == LightTheme )
            , ( "is-reading", model.screen == ReaderScreen )
            ]
        ]
        [ if model.screen == ReaderScreen then
            text ""

          else
            viewAppHeader model
        , case model.notice of
            Just notice ->
                div [ class "notice", attribute "role" "status" ]
                    [ span [] [ text notice ]
                    , button [ type_ "button", onClick DismissNotice, attribute "aria-label" "Dismiss message" ] [ text "×" ]
                    ]

            Nothing ->
                text ""
        , case model.screen of
            LibraryScreen ->
                viewLibrary model

            WorkspaceScreen ->
                viewWorkspace model

            SettingsScreen ->
                viewSettings model

            HistoryScreen ->
                viewHistory model

            AttemptComparisonScreen ->
                viewAttemptComparison model

            ReaderScreen ->
                viewReader model
        ]


viewReader : Model -> Html Msg
viewReader model =
    let
        total =
            List.length model.corpus.sentences
    in
    main_ [ class "reader-page" ]
        [ header [ class "reader-bar" ]
            [ button [ class "icon-button", type_ "button", onClick ShowLibrary, attribute "aria-label" "Back to library" ] [ text "←" ]
            , div [ class "reader-bar-title" ]
                [ span [ class "context-work" ] [ text (workTitle model) ]
                , span [ class "reader-position" ] [ text (String.fromInt (model.sentenceIndex + 1) ++ " / " ++ String.fromInt total) ]
                ]
            , div [ class "reader-bar-actions" ]
                [ button [ class "icon-button", type_ "button", onClick (ReaderStep -1), disabled (model.sentenceIndex == 0), attribute "aria-label" "Previous passage (k)" ] [ text "‹" ]
                , button [ class "icon-button", type_ "button", onClick (ReaderStep 1), disabled (model.sentenceIndex >= total - 1), attribute "aria-label" "Next passage (j)" ] [ text "›" ]
                , button [ class "icon-button", type_ "button", onClick ToggleTheme, attribute "aria-label" (themeActionLabel model.theme) ]
                    [ text
                        (if model.theme == DarkTheme then
                            "☀"

                         else
                            "☾"
                        )
                    ]
                , button [ class "secondary-button", type_ "button", onClick ShowWorkspace ] [ text "Study this passage" ]
                ]
            ]
        , div [ id readerScrollId, class "reader-scroll", on "scroll" (Decode.succeed ReaderScrolled) ]
            [ article [ class "reader-text", attribute "lang" "grc" ]
                (List.indexedMap (viewReaderSentence model) model.corpus.sentences)
            , p [ class "reader-end" ] [ text ("End of " ++ workTitle model ++ " in this edition.") ]
            ]
        ]


viewReaderSentence : Model -> Int -> Sentence -> Html Msg
viewReaderSentence model index sentence =
    let
        revealed =
            Set.member index model.readerRevealed
    in
    section
        [ id (sentenceElementId index)
        , classList [ ( "reader-sentence", True ), ( "is-current", index == model.sentenceIndex ) ]
        ]
        [ button
            [ classList [ ( "reader-marker", True ), ( "is-open", revealed ) ]
            , type_ "button"
            , onClick (ReaderToggleTranslation index)
            , attribute "aria-label" ("Passage " ++ String.fromInt (index + 1) ++ ": " ++ (if revealed then "hide" else "show") ++ " translation")
            , attribute "aria-expanded" (boolString revealed)
            ]
            [ text (String.fromInt (index + 1)) ]
        , p [ class "reader-greek" ] (List.concat (List.indexedMap (viewReaderToken model index) sentence.tokens))
        , if revealed && not (String.isEmpty sentence.proseTranslation) then
            div [ class "reader-translation", attribute "lang" "en" ]
                [ p [] [ text sentence.proseTranslation ]
                , if String.isEmpty sentence.literalTranslation then
                    text ""

                  else
                    p [ class "reader-literal" ] [ text sentence.literalTranslation ]
                ]

          else
            text ""
        ]


{-| Each token is preceded by a space except the first and punctuation, which the imported spacing does not mark.
-}
viewReaderToken : Model -> Int -> Int -> CorpusToken -> List (Html Msg)
viewReaderToken model sentenceIndex position token =
    let
        open =
            model.readerGloss == Just ( sentenceIndex, token.id )

        spaceBefore =
            if position == 0 || isPunctuation token.form then
                text ""

            else
                text " "
    in
    [ spaceBefore
    , button
        [ classList [ ( "reader-token", True ), ( "is-open", open ) ]
        , type_ "button"
        , onClick (ReaderTokenTapped sentenceIndex token.id)
        ]
        [ text token.form
        , if open then
            span [ class "reader-gloss", attribute "role" "tooltip", attribute "lang" "en" ]
                [ text
                    (if String.isEmpty token.gloss then
                        "No gloss"

                     else
                        String.replace "-" " " token.gloss
                    )
                ]

          else
            text ""
        ]
    ]


isPunctuation : String -> Bool
isPunctuation form =
    not (String.isEmpty form) && String.all (\char -> String.contains (String.fromChar char) ".,;:!?·\u{0387}\u{037E})]»”’—–") form


viewAppHeader : Model -> Html Msg
viewAppHeader model =
    header [ class "app-header" ]
        [ button [ class "brand-button", type_ "button", onClick ShowLibrary, attribute "aria-label" "Aristos library" ]
            [ span [ class "brand-mark", attribute "aria-hidden" "true" ] [ text "Α" ]
            , span [ class "brand-word" ] [ text "Aristos" ]
            ]
        , nav [ class "global-nav", attribute "aria-label" "Primary navigation" ]
            (navButton "Library" ShowLibrary (model.screen == LibraryScreen)
                :: (case model.activeEntry of
                        Just entry ->
                            [ navButton "Read" (Navigate (Route.Reader entry.id (Just (model.sentenceIndex + 1)))) False
                            , navButton "Study" ShowWorkspace (List.member model.screen [ WorkspaceScreen, SettingsScreen, HistoryScreen, AttemptComparisonScreen ])
                            ]

                        Nothing ->
                            []
                   )
            )
        , div [ class "header-actions" ]
            [ button
                [ class "theme-button"
                , type_ "button"
                , onClick ToggleTheme
                , attribute "aria-label" (themeActionLabel model.theme)
                , attribute "aria-pressed" (boolString (model.theme == DarkTheme))
                , attribute "title" (themeActionLabel model.theme)
                ]
                [ span [ attribute "aria-hidden" "true" ]
                    [ text
                        (if model.theme == DarkTheme then
                            "☀"

                         else
                            "☾"
                        )
                    ]
                , span [ class "theme-label" ]
                    [ text
                        (if model.theme == DarkTheme then
                            "Light"

                         else
                            "Dark"
                        )
                    ]
                ]
            ]
        ]


navButton : String -> Msg -> Bool -> Html Msg
navButton label msg isActive =
    button
        [ classList [ ( "global-nav-button", True ), ( "is-active", isActive ) ]
        , type_ "button"
        , onClick msg
        ]
        [ text label ]


viewLibrary : Model -> Html Msg
viewLibrary model =
    main_ [ class "page library-page" ]
        [ section [ class "pack-list", attribute "aria-label" "Works" ]
            (if List.isEmpty model.library then
                [ p [ class "muted" ] [ text "Loading the library…" ] ]

             else
                List.map (viewWorkCard model) model.library
            )
        ]


viewWorkCard : Model -> ManifestEntry -> Html Msg
viewWorkCard model entry =
    let
        isActive =
            model.corpusReady && Maybe.map .id model.activeEntry == Just entry.id

        isLoading =
            model.pendingRoute /= Nothing && model.requestedWork == Just entry.id

        coverage =
            corpusCoverage model.corpus

        details =
            [ entry.source.name, entry.source.license ]
                |> List.filter (not << String.isEmpty)
                |> String.join " · "
    in
    section [ classList [ ( "pack-card", True ), ( "featured-pack", isActive ) ] ]
        [ div [ class "pack-body" ]
            [ div [ class "pack-heading" ]
                [ div []
                    [ p [ class "pack-language" ] [ text details ]
                    , h2 [] [ text entry.title ]
                    , p [ class "greek-subtitle" ] [ text entry.source.edition ]
                    ]
                , span [ class "availability good" ] [ text "Bundled" ]
                ]
            , if isActive then
                div [ class "capability-strip" ]
                    [ capabilityPill (coverage.glossed > 0) ("Glosses " ++ fraction coverage.glossed coverage.tokens)
                    , capabilityPill (coverage.morphology > 0) ("Morphology " ++ fraction coverage.morphology coverage.tokens)
                    , capabilityPill (coverage.dependencies > 0) ("Dependencies " ++ fraction coverage.dependencies coverage.sentences)
                    , capabilityPill (coverage.prose > 0) ("Translations " ++ fraction coverage.prose coverage.sentences)
                    ]

              else
                text ""
            , div [ class "pack-footer" ]
                [ span [ class "muted" ] [ text (String.fromInt entry.sentenceCount ++ " " ++ plural entry.sentenceCount "sentence" "sentences" ++ " · " ++ String.fromInt entry.tokenCount ++ " tokens") ]
                , div [ class "button-row" ]
                    [ button [ class "secondary-button", type_ "button", disabled isLoading, onClick (Navigate (Route.WorkLanding entry.id)) ] [ text "Study" ]
                    , button [ class "primary-button", type_ "button", disabled isLoading, onClick (Navigate (Route.Reader entry.id Nothing)) ]
                        [ text
                            (if isLoading then
                                "Loading…"

                             else
                                "Read →"
                            )
                        ]
                    ]
                ]
            ]
        ]


corpusCoverage : Corpus -> Coverage
corpusCoverage corpus =
    let
        tokens =
            List.concatMap .tokens corpus.sentences

        countSentences predicate =
            List.length (List.filter predicate corpus.sentences)
    in
    { tokens = List.length tokens
    , glossed = List.length (List.filter (\token -> not (String.isEmpty token.gloss)) tokens)
    , morphology = List.length (List.filter (\token -> not (String.isEmpty token.morphology.summary)) tokens)
    , sentences = List.length corpus.sentences
    , dependencies = countSentences (\sentence -> List.any (\token -> token.head == 0) sentence.tokens)
    , literal = countSentences (\sentence -> not (String.isEmpty sentence.literalTranslation))
    , prose = countSentences (\sentence -> not (String.isEmpty sentence.proseTranslation))
    }


fraction : Int -> Int -> String
fraction part whole =
    String.fromInt part ++ "/" ++ String.fromInt whole


plural : Int -> String -> String -> String
plural count singular pluralForm =
    if count == 1 then
        singular

    else
        pluralForm


workTitle : Model -> String
workTitle model =
    model.activeEntry
        |> Maybe.map .title
        |> Maybe.withDefault model.corpus.source.name


capabilityPill : Bool -> String -> Html Msg
capabilityPill available label =
    span [ classList [ ( "capability-pill", True ), ( "is-limited", not available ) ] ]
        [ span [ class "capability-dot", attribute "aria-hidden" "true" ] []
        , text label
        ]


viewSettings : Model -> Html Msg
viewSettings model =
    let
        coverage =
            corpusCoverage model.corpus

        provenance =
            model.corpus.source.name
    in
    main_ [ class "page settings-page" ]
        [ section [ class "settings-intro compact-intro" ]
            [ div []
                [ p [ class "eyebrow" ] [ text (workTitle model) ]
                , h1 [] [ text "Study tools" ]
                ]
            , button [ class "primary-button open-workspace-button", type_ "button", onClick ShowWorkspace ] [ text "Back to study →" ]
            ]
        , section [ class "setting-block" ]
            [ div [ class "preset-grid" ]
                [ viewPresetCard model.preset ReadPreset "Read" "Word help only when you ask." "≈ 4 min / passage"
                , viewPresetCard model.preset AssistedPreset "Assisted" "Glosses, forms on request, and a prose draft to check your understanding." "≈ 8 min / passage"
                , viewPresetCard model.preset IntensivePreset "Intensive" "Glosses, forms, and both translation drafts." "≈ 15 min / passage"
                , viewPresetCard model.preset CustomPreset "Custom" "Your own choice of tools." "Variable"
                ]
            ]
        , section [ class "module-settings" ]
            [ viewModuleSetting model GlossModule "Contextual glosses" "Recall each word's sense in this sentence, then compare with the imported gloss." (String.fromInt coverage.glossed ++ " of " ++ String.fromInt coverage.tokens ++ " words") (provenance ++ " · imported")
            , viewModuleSetting model MorphologyModule "Morphology" "Choose the features of a selected form, checked feature by feature." (String.fromInt coverage.morphology ++ " of " ++ String.fromInt coverage.tokens ++ " words") (provenance ++ " · imported")
            , viewModuleSetting model LiteralModule "Literal translation" "Expose the structure in your own words, then compare." (String.fromInt coverage.literal ++ " of " ++ String.fromInt coverage.sentences ++ " sentences") (provenance ++ " · aligned reference")
            , viewModuleSetting model ProseModule "Prose translation" "State the meaning naturally, then compare." (String.fromInt coverage.prose ++ " of " ++ String.fromInt coverage.sentences ++ " sentences") (provenance ++ " · aligned reference")
            ]
        ]


viewScopeControl : SettingScope -> Html Msg
viewScopeControl scope =
    div [ class "scope-control", attribute "aria-label" "Setting scope" ]
        [ scopeButton scope GlobalScope "All works"
        , scopeButton scope WorkScope "This work"
        , scopeButton scope SessionScope "This session"
        ]


scopeButton : SettingScope -> SettingScope -> String -> Html Msg
scopeButton current target label =
    button
        [ classList [ ( "is-active", current == target ) ]
        , type_ "button"
        , onClick (SelectScope target)
        ]
        [ text label ]


viewPresetCard : Preset -> Preset -> String -> String -> String -> Html Msg
viewPresetCard current target title description budget =
    button
        [ classList [ ( "preset-card", True ), ( "is-selected", current == target ) ]
        , type_ "button"
        , onClick (SelectPreset target)
        , attribute "aria-pressed" (boolString (current == target))
        ]
        [ span [ class "preset-check", attribute "aria-hidden" "true" ]
            [ text
                (if current == target then
                    "✓"

                 else
                    ""
                )
            ]
        , span [ class "preset-title" ] [ text title ]
        , span [ class "preset-description" ] [ text description ]
        , span [ class "preset-budget" ] [ text budget ]
        ]


viewRequiredModule : Html Msg
viewRequiredModule =
    div [ class "module-row required-module" ]
        [ div [ class "module-toggle-wrap" ]
            [ input [ type_ "checkbox", checked True, disabled True, attribute "aria-label" "Greek text required" ] [] ]
        , div [ class "module-copy" ]
            [ div [ class "module-title-line" ]
                [ h3 [] [ text "Greek text" ]
                , span [ class "required-badge" ] [ text "Required" ]
                ]
            , p [] [ text "The passage is the workspace. Every other module may be disabled." ]
            , span [ class "provenance" ] [ text "Source text · 100% coverage" ]
            ]
        , span [ class "module-mode fixed-mode" ] [ text "Always available" ]
        ]


viewModuleSetting : Model -> ModuleId -> String -> String -> String -> String -> Html Msg
viewModuleSetting model moduleId title description coverage provenance =
    let
        mode =
            moduleMode moduleId model.settings

        enabled =
            mode /= ModuleOff
    in
    div [ classList [ ( "module-row", True ), ( "is-enabled", enabled ) ] ]
        [ div [ class "module-toggle-wrap" ]
            [ input
                [ type_ "checkbox"
                , checked enabled
                , onClick (ToggleModule moduleId)
                , attribute "aria-label" ("Enable " ++ title)
                ]
                []
            ]
        , div [ class "module-copy" ]
            [ div [ class "module-title-line" ]
                [ h3 [] [ text title ]
                , span [ class "coverage-badge" ] [ text coverage ]
                ]
            , p [] [ text description ]
            , span [ class "provenance" ] [ text provenance ]
            ]
        ]


viewUnavailableModule : String -> String -> String -> Html Msg
viewUnavailableModule title reason coverage =
    div [ class "module-row unavailable-module" ]
        [ div [ class "module-toggle-wrap" ]
            [ input [ type_ "checkbox", disabled True, attribute "aria-label" (title ++ " unavailable") ] [] ]
        , div [ class "module-copy" ]
            [ div [ class "module-title-line" ]
                [ h3 [] [ text title ]
                , span [ class "coverage-badge unavailable-badge" ] [ text coverage ]
                ]
            , p [] [ text reason ]
            , span [ class "provenance" ] [ text "Unavailable in this content pack" ]
            ]
        , span [ class "module-mode fixed-mode" ] [ text "Unavailable" ]
        ]


viewWorkspace : Model -> Html Msg
viewWorkspace model =
    let
        sentence =
            currentSentence model

        showWorkbench =
            model.phase /= Rereading && model.activeModule /= Nothing
    in
    main_ [ class "workspace-page" ]
        [ div [ class "work-context-bar" ]
            [ div [ class "context-title" ]
                [ button [ class "icon-button", type_ "button", onClick ShowLibrary, attribute "aria-label" "Back to library" ] [ text "←" ]
                , div []
                    [ span [ class "context-work" ] [ text (workTitle model) ]
                    ]
                ]
            , div [ class "context-actions" ]
                [ div [ class "passage-nav" ]
                    [ button [ class "icon-button", type_ "button", onClick PreviousSentence, disabled (model.sentenceIndex == 0), attribute "aria-label" "Previous passage (← or k)" ] [ text "‹" ]
                    , label [ class "chapter-jump" ]
                        [ span [] [ text "Passage" ]
                        , select [ value (String.fromInt (model.sentenceIndex + 1)), onInput JumpToPassage ]
                            (List.range 1 (List.length model.corpus.sentences)
                                |> List.map (\number -> option [ value (String.fromInt number), selected (number == model.sentenceIndex + 1) ] [ text (String.fromInt number ++ " / " ++ String.fromInt (List.length model.corpus.sentences)) ])
                            )
                        ]
                    , button [ class "icon-button", type_ "button", onClick NextSentence, disabled (model.sentenceIndex >= List.length model.corpus.sentences - 1), attribute "aria-label" "Next passage (→ or j)" ] [ text "›" ]
                    ]
                ]
            ]
        , div [ classList [ ( "workspace-grid", True ), ( "has-workbench", showWorkbench ) ] ]
            [ viewReadingStage model
            , if showWorkbench then
                viewWorkbench model

              else
                text ""
            ]
        , viewWorkspaceFooter model
        ]


viewSourceRail : Model -> Html Msg
viewSourceRail model =
    let
        sentence =
            currentSentence model

        previousText =
            getAt (model.sentenceIndex - 1) model.corpus.sentences
                |> Maybe.map .text
                |> Maybe.withDefault "This is the first passage."
    in
    aside [ class "source-rail" ]
        [ div [ class "rail-section" ]
            [ p [ class "rail-label" ] [ text "Source" ]
            , h2 [] [ text (workTitle model) ]
            , p [ class "muted" ] [ text (sentenceReference sentence) ]
            ]
        , div [ class "rail-section" ]
            [ p [ class "rail-label" ] [ text "Session" ]
            , div [ class "rail-stat" ] [ span [] [ text "Preset" ], strongText (presetLabel model.preset) ]
            , div [ class "rail-stat" ] [ span [] [ text "Active time" ], strongText (formatDuration model.elapsedSeconds) ]
            , div [ class "rail-stat" ] [ span [] [ text "Modules" ], strongText (String.fromInt (List.length (enabledModules model.settings))) ]
            , button [ class "rail-link", type_ "button", onClick ShowSettings ] [ text "Adjust modules →" ]
            ]
        , div [ class "rail-section prior-context" ]
            [ p [ class "rail-label" ] [ text "Previous Greek" ]
            , p [ class "greek-context" ] [ text (truncate 105 previousText) ]
            , p [ class "context-note" ] [ text "Source-native context only. No authored summary is present in this pack." ]
            ]
        , div [ class "pack-provenance" ]
            [ span [ class "provenance-icon", attribute "aria-hidden" "true" ] [ text "i" ]
            , span []
                [ a [ href model.corpus.source.url, target "_blank", rel "noopener noreferrer" ] [ text model.corpus.source.name ]
                , span [ class "muted" ] [ text (" · " ++ sourceDetails model.corpus.source) ]
                ]
            ]
        ]


viewReadingStage : Model -> Html Msg
viewReadingStage model =
    let
        sentence =
            currentSentence model
    in
    section [ class "reading-stage" ]
        [ if model.phase == Rereading then
            div [ class "reread-instruction" ]
                [ span [ class "reread-icon", attribute "aria-hidden" "true" ] [ text "↻" ]
                , div []
                    [ strongText "Clean reread"
                    , p [] [ text "Feedback and word tools are closed. Let the Greek carry the meaning." ]
                    ]
                ]

          else
            p [ class "reading-instruction" ]
                [ text "Read the sentence first. "
                , span [] [ text "References stay hidden until you submit." ]
                ]
        , viewGreekPassage model
        , div [ class "source-line" ]
            [ span [] [ text model.corpus.source.edition ]
            , span [] [ text (String.fromInt (List.length sentence.tokens) ++ " tokens · imported annotation") ]
            ]
        , if model.phase == Rereading then
            div [ class "reread-space" ] []

          else
            viewActivityTray model
        ]


viewGreekPassage : Model -> Html Msg
viewGreekPassage model =
    let
        sentence =
            currentSentence model

        tokenButton token =
            let
                morphologyAvailable =
                    moduleMode MorphologyModule model.settings /= ModuleOff && isMorphologyEligible token

                glossAvailable =
                    moduleMode GlossModule model.settings /= ModuleOff && token.gloss /= ""

                toolAvailable =
                    morphologyAvailable || glossAvailable

                action =
                    if morphologyAvailable then
                        SelectToken token.id

                    else
                        OpenModule GlossModule
            in
            button
                [ classList
                    [ ( "greek-token", True )
                    , ( "no-space-after", not token.spaceAfter )
                    , ( "is-selected", model.selectedTokenId == Just token.id )
                    ]
                , type_ "button"
                , disabled (not toolAvailable || model.phase == Rereading)
                , onClick action
                , attribute "aria-label" (token.form ++ if toolAvailable then " · open word activity" else "")
                ]
                [ text token.form ]
    in
    div [ classList [ ( "greek-passage", True ), ( "clean-passage", model.phase == Rereading ) ], attribute "lang" "grc" ]
        (List.map tokenButton sentence.tokens)


viewActivityTray : Model -> Html Msg
viewActivityTray model =
    let
        modules =
            enabledModules model.settings
    in
    section [ class "activity-area" ]
        [ div [ class "activity-heading" ]
            [ p [ class "eyebrow" ] [ text "Tools" ]
            , button [ class "text-button", type_ "button", onClick ShowSettings ] [ text "Choose tools" ]
            ]
        , if List.isEmpty modules then
            div [ class "read-only-state" ]
                [ span [ class "read-only-mark", attribute "aria-hidden" "true" ] [ text "α" ]
                , div []
                    [ strongText "Read-only session"
                    , p [] [ text "No tools are on. Add one only if it serves your reading." ]
                    ]
                , button [ class "secondary-button", type_ "button", onClick ShowSettings ] [ text "Choose tools" ]
                ]

          else
            div [ class "activity-tray" ] (List.map (viewActivityChip model) modules)
        ]


viewActivityChip : Model -> ModuleId -> Html Msg
viewActivityChip model moduleId =
    let
        isActive =
            model.activeModule == Just moduleId

        status =
            moduleStatus model moduleId
    in
    button
        [ classList
            [ ( "activity-chip", True )
            , ( "is-active", isActive )
            , ( "is-skipped", moduleListMember moduleId model.skippedModules )
            ]
        , type_ "button"
        , onClick (OpenModule moduleId)
        , attribute "aria-pressed" (boolString isActive)
        ]
        [ span [ class "chip-icon", attribute "aria-hidden" "true" ] [ text (moduleIcon moduleId) ]
        , span [ class "chip-copy" ]
            [ span [ class "chip-name" ] [ text (moduleShortName moduleId) ]
            , span [ class "chip-status" ] [ text status ]
            ]
        ]


viewWorkbench : Model -> Html Msg
viewWorkbench model =
    aside
        [ classList
            [ ( "workbench", True )
            , ( "is-empty", model.activeModule == Nothing )
            ]
        ]
        [ case model.activeModule of
            Nothing ->
                viewCheckpointSummary model

            Just moduleId ->
                div []
                    [ div [ class "workbench-heading" ]
                        [ div []
                            [ p [ class "eyebrow" ] [ text "Workbench" ]
                            , h2 [] [ text (moduleName moduleId) ]
                            ]
                        , button [ class "close-workbench", type_ "button", onClick CloseWorkbench, attribute "aria-label" "Close workbench" ] [ text "×" ]
                        ]
                    , p [ class "workbench-purpose" ] [ text (modulePurpose moduleId) ]
                    , if model.phase == Compared then
                        viewModuleComparison model moduleId

                      else
                        viewModuleDraft model moduleId
                    , viewWorkbenchMeta model moduleId
                    ]
        ]


viewCheckpointSummary : Model -> Html Msg
viewCheckpointSummary model =
    div [ class "checkpoint-summary" ]
        [ span [ class "summary-symbol", attribute "aria-hidden" "true" ] [ text "✓" ]
        , p [ class "eyebrow" ] [ text "Passage checkpoint" ]
        , h2 []
            [ text
                (if model.phase == Compared then
                    "Attempt submitted"

                 else
                    "Work at your own depth"
                )
            ]
        , p []
            [ text
                (if model.phase == Compared then
                    "Open a module to review your response and any reference available in this pack."

                 else
                    "Open any module from the tray. One submission freezes all drafts together."
                )
            ]
        , div [ class "summary-list" ]
            [ summaryLine "Enabled" (String.fromInt (List.length (enabledModules model.settings)))
            , summaryLine "Skipped" (String.fromInt (List.length model.skippedModules))
            , summaryLine "Reference viewed" (if model.referenceRevealed then "Yes · assisted" else "No")
            ]
        ]


viewModuleDraft : Model -> ModuleId -> Html Msg
viewModuleDraft model moduleId =
    case moduleId of
        GlossModule ->
            viewGlossDraft model

        MorphologyModule ->
            viewMorphologyDraft model

        DependencyModule ->
            viewDependencyDraft model

        LiteralModule ->
            viewTranslationDraft model True

        ProseModule ->
            viewTranslationDraft model False


viewGlossDraft : Model -> Html Msg
viewGlossDraft model =
    let
        targets =
            glossTargets (currentSentence model)

        fields =
            targets
                |> List.map
                    (\token ->
                        glossField token.form (glossDraftAt token.id model.draft) (UpdateGloss token.id)
                    )

        references =
            targets
                |> List.map (\token -> token.form ++ " — " ++ token.gloss)
                |> String.join " · "
    in
    div [ class "form-stack" ]
        (fields
            ++ [ p [ class "field-note" ] [ text "Original wording is preserved. A different synonym is not automatically wrong." ]
               , viewRevealedReference model ("Imported glosses: " ++ references)
               ]
        )


glossField : String -> String -> (String -> Msg) -> Html Msg
glossField token entered msg =
    label [ class "gloss-field" ]
        [ span [ class "field-token" ] [ text token ]
        , input [ type_ "text", value entered, onInput msg, placeholder "Contextual sense…" ] []
        ]


viewMorphologyDraft : Model -> Html Msg
viewMorphologyDraft model =
    let
        target =
            morphologyTarget model

        reference =
            String.join " · "
                [ String.toLower target.upos
                , featureLabel target.morphology.case_
                , featureLabel target.morphology.number
                , featureLabel target.morphology.gender
                ]
    in
    div []
        [ div [ class "target-token-card" ]
            [ span [ class "token-index" ] [ text (String.fromInt target.id) ]
            , div []
                [ span [ class "target-token" ] [ text target.form ]
                , span [ class "target-lemma" ]
                    [ text
                        (if model.referenceRevealed then
                            "Lemma · " ++ target.lemma

                         else
                            "Lemma hidden until submit"
                        )
                    ]
                ]
            ]
        , div [ class "structured-fields" ]
            [ selectField "Case" model.draft.morphCase UpdateMorphCase [ "—", "Nominative", "Genitive", "Dative", "Accusative", "Vocative" ]
            , selectField "Number" model.draft.morphNumber UpdateMorphNumber [ "—", "Singular", "Dual", "Plural" ]
            , selectField "Gender" model.draft.morphGender UpdateMorphGender [ "—", "Masculine", "Feminine", "Neuter", "Common" ]
            ]
        , p [ class "field-note" ] [ text "These features describe the whole token. No automatic stem/ending boundary is claimed." ]
        , button [ class "uncertain-button", type_ "button", onClick (ShowNotice "Uncertainty recorded with this draft; it will remain distinct from an omitted answer.") ] [ text "+ Mark an uncertain alternative" ]
        , viewRevealedReference model ("Imported analysis: " ++ reference)
        ]


selectField : String -> String -> (String -> Msg) -> List String -> Html Msg
selectField fieldLabel current msg choices =
    selectValueField fieldLabel current msg (List.map (\choice -> ( choice, choice )) choices)


selectValueField : String -> String -> (String -> Msg) -> List ( String, String ) -> Html Msg
selectValueField fieldLabel current msg choices =
    label [ class "select-field" ]
        [ span [] [ text fieldLabel ]
        , select [ value current, onInput msg ]
            (List.map
                (\( choiceValue, choiceLabel ) -> option [ value choiceValue, selected (choiceValue == current) ] [ text choiceLabel ])
                choices
            )
        ]


viewDependencyDraft : Model -> Html Msg
viewDependencyDraft model =
    let
        sentence =
            currentSentence model

        target =
            dependencyTarget sentence

        root =
            dependencyRoot sentence

        tokenChoices =
            ( "—", "—" )
                :: (sentence.tokens
                        |> List.filter (\token -> token.upos /= "PUNCT")
                        |> List.map (\token -> ( String.fromInt token.id, token.form ++ " · " ++ String.toLower token.upos ))
                   )

        relationChoices =
            ( "—", "—" )
                :: (target.relation :: [ "nsubj", "nsubj:pass", "obj", "iobj", "ccomp", "xcomp", "obl" ]
                        |> uniqueStrings
                        |> List.map (\relation -> ( relation, String.toUpper relation ))
                   )
    in
    div []
        [ div [ class "task-scope" ]
            [ span [ class "scope-pill" ] [ text "Partial task" ]
            , span [] [ text ("Find the root, then choose the head and relation of “" ++ target.form ++ ".") ]
            ]
        , viewMiniTree model False
        , div [ class "dependency-fields" ]
            [ selectValueField "Finite predicate / root" model.draft.dependencyRoot UpdateDependencyRoot tokenChoices
            , div [ class "edge-builder" ]
                [ span [ class "edge-dependent" ] [ text target.form ]
                , span [ class "edge-arrow", attribute "aria-hidden" "true" ] [ text "→" ]
                , selectValueField "Head" model.draft.dependencyHead UpdateDependencyHead tokenChoices
                ]
            , selectValueField "Relation" model.draft.dependencyRelation UpdateDependencyRelation relationChoices
            ]
        , p [ class "field-note" ] [ text "Answers store token IDs and relations—not screen coordinates. Imported dependencies are attributed references, not unquestionable truth." ]
        , viewRevealedReference model ("Imported edge: " ++ target.form ++ " → " ++ rootOrHeadForm sentence target ++ " · " ++ String.toUpper target.relation)
        ]


viewMiniTree : Model -> Bool -> Html Msg
viewMiniTree model showReference =
    let
        sentence =
            currentSentence model

        target =
            dependencyTarget sentence

        root =
            dependencyRoot sentence

        draftRootForm =
            tokenFormForValue sentence model.draft.dependencyRoot

        draftHeadForm =
            tokenFormForValue sentence model.draft.dependencyHead

        candidates =
            target
                :: root
                :: (sentence.tokens |> List.filter (\token -> token.upos /= "PUNCT"))
                |> uniqueTokens
                |> List.take 3
    in
    if showReference then
        div [ class "mini-tree show-reference", attribute "aria-label" "Imported dependency reference" ]
            [ div [ class "tree-root" ]
                [ span [ class "tree-relation" ] [ text "ROOT" ]
                , span [ class "tree-token" ] [ text root.form ]
                ]
            , div [ class "tree-stem", attribute "aria-hidden" "true" ] []
            , div [ class "tree-children single-edge" ]
                [ div [ class "tree-node answer-node" ]
                    [ span [ class "tree-relation" ] [ text (String.toUpper target.relation) ]
                    , span [ class "tree-token" ] [ text target.form ]
                    ]
                ]
            ]

    else
        div [ class "mini-tree tree-draft", attribute "aria-label" "Your dependency draft; reference hidden" ]
            [ div [ class "tree-draft-heading" ]
                [ span [] [ text "Your graph" ]
                , span [] [ text "Reference hidden" ]
                ]
            , if hasResponse model.draft.dependencyRoot then
                div [ class "tree-root" ]
                    [ span [ class "tree-relation" ] [ text "YOUR ROOT" ]
                    , span [ class "tree-token" ] [ text draftRootForm ]
                    ]

              else
                div [ class "tree-empty" ] [ text "Choose a root below" ]
            , div [ class "tree-draft-tokens" ]
                (candidates
                    |> List.map
                        (\token ->
                            div [ classList [ ( "tree-node", True ), ( "answer-node", token.id == target.id ) ] ]
                                [ span [ class "tree-token" ] [ text token.form ] ]
                        )
                )
            , if hasResponse model.draft.dependencyHead then
                div [ class "draft-edge-preview" ]
                    [ span [] [ text "Your edge" ]
                    , strongText
                        (target.form
                            ++ " → "
                            ++ draftHeadForm
                            ++ (if hasResponse model.draft.dependencyRelation then
                                    " · " ++ String.toUpper model.draft.dependencyRelation

                                else
                                    ""
                               )
                        )
                    ]

              else
                p [ class "tree-empty-note" ] [ text "No relationships attached yet." ]
            ]


viewTranslationDraft : Model -> Bool -> Html Msg
viewTranslationDraft model literal =
    let
        sentence =
            currentSentence model

        draftText =
            if literal then
                model.draft.literal

            else
                model.draft.prose

        reference =
            if literal then
                sentence.literalTranslation

            else
                sentence.proseTranslation

        updateMsg =
            if literal then
                UpdateLiteral

            else
                UpdateProse

        promptText =
            if literal then
                "Keep visible Greek structure and supplied words where useful."

            else
                "State the proposition in natural English without imitating Greek order."
    in
    div []
        [ label [ class "translation-editor" ]
            [ span [] [ text promptText ]
            , textarea [ rows 8, value draftText, onInput updateMsg, placeholder "Write your translation…" ] []
            ]
        , div [ class "editor-status" ]
            [ span [] [ text (String.fromInt (String.length draftText) ++ " characters") ]
            , span [] [ text "Autosaved locally" ]
            ]
        , viewRevealedReference model ("Imported translation: " ++ reference)
        ]


viewRevealedReference : Model -> String -> Html Msg
viewRevealedReference model reference =
    if model.referenceRevealed then
        div [ class "early-reference" ]
            [ span [ class "assisted-label" ] [ text "Revealed · assisted" ]
            , p [] [ text reference ]
            ]

    else
        button [ class "reveal-button", type_ "button", onClick RevealAnyway ]
            [ span [ attribute "aria-hidden" "true" ] [ text "◉" ]
            , span [] [ strongText "Reveal reference anyway", span [] [ text "Records this attempt as assisted" ] ]
            ]


viewModuleComparison : Model -> ModuleId -> Html Msg
viewModuleComparison model moduleId =
    let
        sentence =
            currentSentence model
    in
    case moduleId of
        GlossModule ->
            let
                targets =
                    glossTargets sentence

                rows =
                    targets
                        |> List.map
                            (\token ->
                                let
                                    entered =
                                        glossDraftAt token.id model.draft
                                in
                                comparisonRow token.form entered token.gloss (normalizedGlossMatch entered token.gloss)
                            )
            in
            div [ class "comparison-stack" ]
                (comparisonBanner "Compared with imported contextual glosses" "Differences require your judgment"
                    :: rows
                    ++ [ viewSelfAssessment ]
                )

        MorphologyModule ->
            let
                target =
                    morphologyTarget model

                referenceCase =
                    featureLabel target.morphology.case_

                referenceNumber =
                    featureLabel target.morphology.number

                referenceGender =
                    featureLabel target.morphology.gender

                matches =
                    countTrue
                        [ model.draft.morphCase == referenceCase
                        , model.draft.morphNumber == referenceNumber
                        , model.draft.morphGender == referenceGender
                        ]
            in
            div [ class "comparison-stack" ]
                [ comparisonBanner (String.fromInt matches ++ " of 3 features match") "Accuracy on this token · imported reference"
                , featureComparison "Case" model.draft.morphCase referenceCase (model.draft.morphCase == referenceCase)
                , featureComparison "Number" model.draft.morphNumber referenceNumber (model.draft.morphNumber == referenceNumber)
                , featureComparison "Gender" model.draft.morphGender referenceGender (model.draft.morphGender == referenceGender)
                , p [ class "provenance-panel" ] [ text ("Lemma " ++ target.lemma ++ " · " ++ target.morphology.summary ++ " · " ++ model.corpus.source.name) ]
                ]

        DependencyModule ->
            let
                root =
                    dependencyRoot sentence

                target =
                    dependencyTarget sentence

                rootId =
                    String.fromInt root.id

                headId =
                    String.fromInt target.head

                matches =
                    countTrue
                        [ model.draft.dependencyRoot == rootId
                        , model.draft.dependencyHead == headId
                        , model.draft.dependencyRelation == target.relation
                        ]

                submittedHead =
                    tokenFormForValue sentence model.draft.dependencyHead

                referenceHead =
                    rootOrHeadForm sentence target
            in
            div [ class "comparison-stack" ]
                [ comparisonBanner (String.fromInt matches ++ " of 3 fields match") "Task-scoped result · imported reference"
                , viewMiniTree model True
                , featureComparison "Root" (tokenFormForValue sentence model.draft.dependencyRoot) root.form (model.draft.dependencyRoot == rootId)
                , featureComparison "Core edge" (target.form ++ " → " ++ submittedHead) (target.form ++ " → " ++ referenceHead) (model.draft.dependencyHead == headId)
                , featureComparison "Relation" model.draft.dependencyRelation target.relation (model.draft.dependencyRelation == target.relation)
                , button [ class "disagree-button", type_ "button", onClick (ShowNotice "Disagreement noted. The imported analysis remains visible with its provenance.") ] [ text "I disagree with this reference" ]
                ]

        LiteralModule ->
            viewTranslationComparison model.draft.literal sentence.literalTranslation "Literal attempt"

        ProseModule ->
            viewTranslationComparison model.draft.prose sentence.proseTranslation "Prose attempt"


comparisonBanner : String -> String -> Html Msg
comparisonBanner title note =
    div [ class "comparison-banner" ]
        [ span [ class "comparison-check", attribute "aria-hidden" "true" ] [ text "✓" ]
        , div []
            [ strongText title
            , span [] [ text note ]
            ]
        ]


comparisonRow : String -> String -> String -> Bool -> Html Msg
comparisonRow token mine reference matches =
    div [ class "gloss-comparison" ]
        [ span [ class "field-token" ] [ text token ]
        , div [] [ span [ class "compare-label" ] [ text "You" ], span [] [ text mine ] ]
        , div [] [ span [ class "compare-label" ] [ text "Reference" ], span [] [ text reference ] ]
        , span [ classList [ ( "match-mark", True ), ( "is-different", not matches ) ] ]
            [ text (if matches then "Match" else "Different") ]
        ]


featureComparison : String -> String -> String -> Bool -> Html Msg
featureComparison feature mine reference matches =
    div [ class "feature-comparison" ]
        [ span [ class "feature-name" ] [ text feature ]
        , span [] [ text mine ]
        , span [ class "reference-value" ] [ text reference ]
        , span [ classList [ ( "feature-result", True ), ( "is-wrong", not matches ) ] ]
            [ text (if matches then "✓" else "!") ]
        ]


viewTranslationComparison : String -> String -> String -> Html Msg
viewTranslationComparison mine reference labelText =
    div [ class "comparison-stack" ]
        [ comparisonBanner "Compared with imported translation" "No automatic translation score"
        , div [ class "text-comparison" ]
            [ div []
                [ span [ class "compare-label" ] [ text labelText ]
                , p []
                    [ text
                        (if String.isEmpty mine then
                            "No response submitted."

                         else
                            mine
                        )
                    ]
                ]
            , div []
                [ span [ class "compare-label" ] [ text "Reference" ]
                , p [] [ text reference ]
                ]
            ]
        , p [ class "field-note" ] [ text "Translation differences require judgment; wording is not scored automatically." ]
        ]


viewSelfAssessment : Html Msg
viewSelfAssessment =
    div [ class "self-assessment" ]
        [ span [] [ text "How would you assess the difference?" ]
        , div [ class "assessment-options" ]
            [ button [ type_ "button", onClick (ShowNotice "Self-assessment recorded: acceptable.") ] [ text "Acceptable" ]
            , button [ type_ "button", onClick (ShowNotice "Self-assessment recorded: meaning missed.") ] [ text "Meaning missed" ]
            , button [ type_ "button", onClick (ShowNotice "Self-assessment recorded: structure missed.") ] [ text "Structure missed" ]
            , button [ type_ "button", onClick (ShowNotice "Self-assessment recorded: wording differs.") ] [ text "Wording differs" ]
            ]
        ]


viewWorkbenchMeta : Model -> ModuleId -> Html Msg
viewWorkbenchMeta model moduleId =
    div [ class "workbench-meta" ]
        [ span [] [ text (modeLabel (moduleMode moduleId model.settings)) ]
        , if model.phase == Drafting then
            button [ class "skip-module", type_ "button", onClick SkipCurrentModule ] [ text "Do this one later" ]

          else
            span [] [ text ("Attempt " ++ twoDigit model.attemptCount) ]
        ]


viewWorkspaceFooter : Model -> Html Msg
viewWorkspaceFooter model =
    footer [ class "workspace-footer" ]
        [ button [ class "footer-side-button", type_ "button", disabled (model.sentenceIndex == 0), onClick PreviousSentence ] [ text "← Previous" ]
        , div [ class "checkpoint-copy" ]
            [ strongText (checkpointTitle model)
            , span [] [ text (checkpointSubtitle model) ]
            ]
        , case model.phase of
            Drafting ->
                button [ class "checkpoint-button", type_ "button", onClick SubmitCheckpoint ]
                    [ text
                        (case model.revisionParent of
                            Just _ ->
                                "Submit revision"

                            Nothing ->
                                "Submit checkpoint"
                        )
                    , span [ attribute "aria-hidden" "true" ] [ text " →" ]
                    ]

            Compared ->
                div [ class "footer-button-pair" ]
                    [ button [ class "secondary-button", type_ "button", onClick ReviseAttempt ] [ text "Revise" ]
                    , button [ class "checkpoint-button", type_ "button", onClick BeginReread ] [ text "Clean reread →" ]
                    ]

            Rereading ->
                button [ class "checkpoint-button", type_ "button", onClick FinishPassage ] [ text "Finish & continue →" ]
        ]


viewHistory : Model -> Html Msg
viewHistory model =
    let
        sentence =
            currentSentence model

        attemptCards =
            if model.attemptCount == 0 then
                [ div [ class "history-empty" ]
                    [ span [ class "summary-symbol", attribute "aria-hidden" "true" ] [ text "∅" ]
                    , h2 [] [ text "No submitted attempts for this passage" ]
                    , p [] [ text "Return to the workspace and submit a checkpoint. No fictional history is preloaded." ]
                    ]
                ]

            else
                List.range 1 model.attemptCount
                    |> List.reverse
                    |> List.map
                        (\attemptNumber ->
                            viewAttemptCard
                                (twoDigit attemptNumber)
                                "This browser session"
                                (presetLabel model.preset)
                                (if attemptNumber == model.attemptCount then "Current checkpoint" else "Parent attempt")
                                (String.fromInt (List.length (enabledModules model.settings)) ++ " tools · " ++ if model.referenceRevealed then "assisted" else "unassisted")
                                (attemptNumber == model.attemptCount)
                        )
    in
    main_ [ class "page history-page" ]
        [ section [ class "history-intro" ]
            [ div []
                [ p [ class "eyebrow" ] [ text "Attempt history" ]
                , h1 [] [ text "Your work remains yours—and unchanged." ]
                , p [ class "lead" ] [ text "This prototype retains attempts in memory for the current passage. Refreshing still resets them." ]
                ]
            , button [ class "primary-button", type_ "button", onClick ShowWorkspace ] [ text "Return to passage" ]
            ]
        , div [ class "history-layout" ]
            [ aside [ class "history-filter" ]
                [ p [ class "rail-label" ] [ text "Showing" ]
                , button [ class "filter-button is-active", type_ "button" ] [ text "This passage", span [] [ text (String.fromInt model.attemptCount) ] ]
                , button [ class "filter-button", type_ "button", onClick (ShowNotice "Cross-passage history arrives with persistent attempt storage.") ] [ text ("All " ++ workTitle model), span [] [ text "—" ] ]
                , div [ class "privacy-note" ]
                    [ strongText "In-memory prototype"
                    , p [] [ text "Refreshing the page clears attempts in this release." ]
                    ]
                ]
            , section [ class "attempt-series" ]
                ([ div [ class "series-heading" ]
                    [ div []
                        [ span [ class "series-reference" ] [ text (sentenceReference sentence) ]
                        , p [ class "series-greek" ] [ text (truncate 100 sentence.text) ]
                        ]
                    , span [ class "version-badge" ] [ text model.corpus.source.name ]
                    ]
                 ]
                    ++ attemptCards
                    ++ [ button [ class "compare-attempts-button", type_ "button", disabled (model.attemptCount < 2), onClick ShowAttemptComparison ]
                            [ span [ attribute "aria-hidden" "true" ] [ text "⇄" ]
                            , span []
                                [ strongText
                                    (if model.attemptCount < 2 then
                                        "Submit a revision to compare"

                                     else
                                        "Compare attempts " ++ twoDigit (model.attemptCount - 1) ++ " and " ++ twoDigit model.attemptCount
                                    )
                                , span [] [ text "Responses and assistance conditions" ]
                                ]
                            , span [ attribute "aria-hidden" "true" ] [ text "→" ]
                            ]
                       ]
                )
            ]
        ]


viewAttemptCard : String -> String -> String -> String -> String -> Bool -> Html Msg
viewAttemptCard number date preset status details isCurrent =
    articleElement [ classList [ ( "attempt-card", True ), ( "is-current", isCurrent ) ] ]
        [ div [ class "attempt-number" ] [ text number ]
        , div [ class "attempt-main" ]
            [ div [ class "attempt-topline" ]
                [ span [] [ text date ]
                , span [ class "attempt-preset" ] [ text preset ]
                ]
            , h2 [] [ text status ]
            , p [] [ text details ]
            ]
        , span [ class "immutable-badge" ] [ text "Locked" ]
        ]


viewAttemptComparison : Model -> Html Msg
viewAttemptComparison model =
    let
        previous =
            Maybe.withDefault emptyDraft model.previousDraft

        responseOrEmpty response =
            if String.isEmpty response then
                "No response submitted."

            else
                response
    in
    main_ [ class "page attempt-comparison-page" ]
        [ button [ class "back-link", type_ "button", onClick ShowHistory ] [ text "← Attempt history" ]
        , section [ class "comparison-intro" ]
            [ p [ class "eyebrow" ] [ text (sentenceReference (currentSentence model)) ]
            , h1 [] [ text "What changed between attempts?" ]
            , p [ class "lead" ] [ text "These are practice conditions and responses—not proof of Greek mastery." ]
            ]
        , div [ class "attempt-columns heading-columns" ]
            [ div [] [ span [ class "column-label" ] [ text "Parent" ], h2 [] [ text ("Attempt " ++ twoDigit (max 1 (model.attemptCount - 1))) ], p [] [ text "Immutable submitted response" ] ]
            , div [] [ span [ class "column-label current-label" ] [ text "Revision" ], h2 [] [ text ("Attempt " ++ twoDigit model.attemptCount) ], p [] [ text "Current submitted response" ] ]
            ]
        , section [ class "comparison-section" ]
            [ div [ class "comparison-section-heading" ]
                [ p [ class "eyebrow" ] [ text "Prose translation" ]
                , span [ class "neutral-badge" ] [ text "Imported reference available in workspace" ]
                ]
            , div [ class "attempt-columns" ]
                [ blockquoteElement (responseOrEmpty previous.prose)
                , blockquoteElement (responseOrEmpty model.draft.prose)
                ]
            ]
        , section [ class "comparison-section" ]
            [ div [ class "comparison-section-heading" ]
                [ p [ class "eyebrow" ] [ text "Morphology response" ]
                , span [ class "neutral-badge" ] [ text "Same reference version" ]
                ]
            , div [ class "condition-table" ]
                [ conditionRow "Case" previous.morphCase model.draft.morphCase
                , conditionRow "Number" previous.morphNumber model.draft.morphNumber
                , conditionRow "Gender" previous.morphGender model.draft.morphGender
                , conditionRow "Reference visibility" "Hidden at parent submit" (if model.referenceRevealed then "Visible · assisted" else "Hidden · unassisted")
                ]
            ]
        , section [ class "evidence-limit" ]
            [ span [ class "evidence-icon", attribute "aria-hidden" "true" ] [ text "i" ]
            , div []
                [ strongText "Repeated-sentence improvement is practice performance."
                , p [] [ text "A delayed check on comparable unseen Greek is required before making a learning claim." ]
                ]
            ]
        ]


blockquoteElement : String -> Html Msg
blockquoteElement content =
    div [ class "attempt-quote" ] [ p [] [ text content ] ]


conditionRow : String -> String -> String -> Html Msg
conditionRow labelText earlier current =
    div [ class "condition-row" ]
        [ strongText labelText
        , span [] [ text earlier ]
        , span [] [ text current ]
        ]


articleElement : List (Html.Attribute msg) -> List (Html msg) -> Html msg
articleElement attributes children =
    Html.article attributes children


strongText : String -> Html msg
strongText content =
    Html.strong [] [ text content ]


summaryLine : String -> String -> Html Msg
summaryLine labelText valueText =
    div [] [ span [] [ text labelText ], strongText valueText ]


currentSentence : Model -> Sentence
currentSentence model =
    getAt model.sentenceIndex model.corpus.sentences
        |> Maybe.withDefault fallbackSentence


fallbackSentence : Sentence
fallbackSentence =
    fallbackCorpus.sentences
        |> List.head
        |> Maybe.withDefault
            { id = "missing"
            , chapter = 1
            , verse = "1.1.1"
            , text = "No corpus loaded."
            , literalTranslation = ""
            , proseTranslation = ""
            , tokens = []
            }


sentenceReference : Sentence -> String
sentenceReference sentence =
    "§ " ++ String.replace "-" "–" sentence.verse


getAt : Int -> List a -> Maybe a
getAt index items =
    if index < 0 then
        Nothing

    else
        items |> List.drop index |> List.head


truncate : Int -> String -> String
truncate limit content =
    if String.length content <= limit then
        content

    else
        String.left limit content ++ "…"


glossTargets : Sentence -> List CorpusToken
glossTargets sentence =
    sentence.tokens
        |> List.filter (\token -> token.gloss /= "" && token.upos /= "PUNCT")


glossDraftAt : Int -> Draft -> String
glossDraftAt tokenId draft =
    Dict.get tokenId draft.glosses
        |> Maybe.withDefault ""


morphologyTarget : Model -> CorpusToken
morphologyTarget model =
    let
        eligible =
            currentSentence model
                |> .tokens
                |> List.filter isMorphologyEligible

        selected =
            model.selectedTokenId
                |> Maybe.andThen
                    (\tokenId ->
                        eligible
                            |> List.filter (\token -> token.id == tokenId)
                            |> List.head
                    )
    in
    selected
        |> Maybe.withDefault
            (eligible
                |> List.head
                |> Maybe.withDefault blankToken
            )


isMorphologyEligible : CorpusToken -> Bool
isMorphologyEligible token =
    token.morphology.case_ /= ""
        && token.morphology.number /= ""
        && token.morphology.gender /= ""
        && not (String.contains "," token.morphology.case_)
        && not (String.contains "," token.morphology.number)
        && not (String.contains "," token.morphology.gender)


featureLabel : String -> String
featureLabel feature =
    case feature of
        "Nom" ->
            "Nominative"

        "Gen" ->
            "Genitive"

        "Dat" ->
            "Dative"

        "Acc" ->
            "Accusative"

        "Voc" ->
            "Vocative"

        "Sing" ->
            "Singular"

        "Dual" ->
            "Dual"

        "Plur" ->
            "Plural"

        "Masc" ->
            "Masculine"

        "Fem" ->
            "Feminine"

        "Neut" ->
            "Neuter"

        "Com" ->
            "Common"

        _ ->
            feature


dependencyRoot : Sentence -> CorpusToken
dependencyRoot sentence =
    sentence.tokens
        |> List.filter (\token -> token.head == 0)
        |> List.head
        |> Maybe.withDefault blankToken


dependencyTarget : Sentence -> CorpusToken
dependencyTarget sentence =
    let
        eligible =
            sentence.tokens
                |> List.filter (\token -> token.head /= 0 && token.upos /= "PUNCT")

        preferred =
            eligible
                |> List.filter
                    (\token ->
                        String.startsWith "nsubj" token.relation
                            || token.relation == "obj"
                            || token.relation == "iobj"
                    )
    in
    preferred
        |> List.head
        |> Maybe.withDefault
            (eligible
                |> List.head
                |> Maybe.withDefault blankToken
            )


tokenById : Int -> Sentence -> Maybe CorpusToken
tokenById tokenId sentence =
    sentence.tokens
        |> List.filter (\token -> token.id == tokenId)
        |> List.head


tokenFormForValue : Sentence -> String -> String
tokenFormForValue sentence tokenIdValue =
    String.toInt tokenIdValue
        |> Maybe.andThen (\tokenId -> tokenById tokenId sentence)
        |> Maybe.map .form
        |> Maybe.withDefault "—"


rootOrHeadForm : Sentence -> CorpusToken -> String
rootOrHeadForm sentence token =
    tokenById token.head sentence
        |> Maybe.map .form
        |> Maybe.withDefault (dependencyRoot sentence).form


uniqueTokens : List CorpusToken -> List CorpusToken
uniqueTokens tokens =
    List.foldl
        (\token result ->
            if List.any (\existing -> existing.id == token.id) result then
                result

            else
                result ++ [ token ]
        )
        []
        tokens


uniqueStrings : List String -> List String
uniqueStrings values =
    List.foldl
        (\value result ->
            if List.member value result then
                result

            else
                result ++ [ value ]
        )
        []
        values


normalizedGlossMatch : String -> String -> Bool
normalizedGlossMatch entered reference =
    let
        normalizedEntered =
            entered |> String.trim |> String.toLower

        references =
            reference
                |> String.replace ";" ","
                |> String.split ","
                |> List.map (String.trim >> String.toLower)
    in
    normalizedEntered /= "" && List.member normalizedEntered references


blankToken : CorpusToken
blankToken =
    fallbackToken 0 "—" "—" "X" "" "" "" "" 0 "dep" "" True


enabledModules : ModuleSettings -> List ModuleId
enabledModules settings =
    [ GlossModule, MorphologyModule, LiteralModule, ProseModule ]
        |> List.filter (\moduleId -> moduleMode moduleId settings /= ModuleOff)


moduleName : ModuleId -> String
moduleName moduleId =
    case moduleId of
        GlossModule ->
            "Contextual glosses"

        MorphologyModule ->
            "Morphology analysis"

        DependencyModule ->
            "Dependency relationships"

        LiteralModule ->
            "Literal translation"

        ProseModule ->
            "Prose translation"


moduleShortName : ModuleId -> String
moduleShortName moduleId =
    case moduleId of
        GlossModule ->
            "Gloss"

        MorphologyModule ->
            "Morphology"

        DependencyModule ->
            "Tree"

        LiteralModule ->
            "Literal"

        ProseModule ->
            "Prose"


moduleIcon : ModuleId -> String
moduleIcon moduleId =
    case moduleId of
        GlossModule ->
            "Aa"

        MorphologyModule ->
            "μ"

        DependencyModule ->
            "⌘"

        LiteralModule ->
            "≡"

        ProseModule ->
            "¶"


modulePurpose : ModuleId -> String
modulePurpose moduleId =
    case moduleId of
        GlossModule ->
            "Enter a contextual sense for each word before seeing the imported gloss."

        MorphologyModule ->
            "Describe only the applicable features of one selected form."

        DependencyModule ->
            "Reconstruct a small semantic edge set; the complete tree is not required."

        LiteralModule ->
            "Draft wording that makes Greek structure and supplied relationships visible."

        ProseModule ->
            "Express the proposition naturally and preserve it for comparison with a later revision."


moduleStatus : Model -> ModuleId -> String
moduleStatus model moduleId =
    if moduleListMember moduleId model.skippedModules then
        "Skipped"

    else
        case model.phase of
            Compared ->
                "Compared"

            Rereading ->
                "Closed"

            Drafting ->
                case moduleId of
                    GlossModule ->
                        let
                            targets =
                                glossTargets (currentSentence model)
                        in
                        responseCountLabel
                            (targets
                                |> List.map (\token -> glossDraftAt token.id model.draft)
                                |> countResponses
                            )
                            (List.length targets)

                    MorphologyModule ->
                        responseCountLabel
                            (countResponses [ model.draft.morphCase, model.draft.morphNumber, model.draft.morphGender ])
                            3

                    DependencyModule ->
                        responseCountLabel
                            (countResponses [ model.draft.dependencyRoot, model.draft.dependencyHead, model.draft.dependencyRelation ])
                            3

                    LiteralModule ->
                        draftStatus model.draft.literal

                    ProseModule ->
                        draftStatus model.draft.prose


countResponses : List String -> Int
countResponses responses =
    responses |> List.filter hasResponse |> List.length


countTrue : List Bool -> Int
countTrue values =
    values |> List.filter identity |> List.length


hasResponse : String -> Bool
hasResponse response =
    response /= "" && response /= "—"


responseCountLabel : Int -> Int -> String
responseCountLabel count total =
    if count == 0 then
        "Not started"

    else
        String.fromInt count ++ " / " ++ String.fromInt total ++ " fields"


draftStatus : String -> String
draftStatus response =
    if hasResponse response then
        "Draft"

    else
        "Not started"


modeLabel : ModuleMode -> String
modeLabel mode =
    case mode of
        ModuleOff ->
            "Off"

        OnDemand ->
            "On demand"

        Suggested ->
            "Suggested"

        EverySentence ->
            "Every sentence"


presetLabel : Preset -> String
presetLabel preset =
    case preset of
        ReadPreset ->
            "Read"

        AssistedPreset ->
            "Assisted"

        IntensivePreset ->
            "Intensive"

        CustomPreset ->
            "Custom"


themeActionLabel : Theme -> String
themeActionLabel theme =
    case theme of
        DarkTheme ->
            "Use light theme"

        LightTheme ->
            "Use dark theme"


scopeLabel : SettingScope -> String
scopeLabel scope =
    case scope of
        GlobalScope ->
            "Default for all works"

        WorkScope ->
            "Override for this work"

        SessionScope ->
            "This session only"


phaseEyebrow : WorkspacePhase -> String
phaseEyebrow phase =
    case phase of
        Drafting ->
            "Cold read · respond"

        Compared ->
            "Compare · reflect"

        Rereading ->
            "Fluent pass"


phaseLabel : WorkspacePhase -> String
phaseLabel phase =
    case phase of
        Drafting ->
            "Drafting"

        Compared ->
            "Submitted · locked"

        Rereading ->
            "Reread"


checkpointTitle : Model -> String
checkpointTitle model =
    case model.phase of
        Drafting ->
            case model.revisionParent of
                Just parent ->
                    "Revision of attempt 0" ++ String.fromInt parent

                Nothing ->
                    "One checkpoint · " ++ String.fromInt (List.length (enabledModules model.settings)) ++ " tools"

        Compared ->
            "Attempt 0" ++ String.fromInt model.attemptCount ++ " is immutable"

        Rereading ->
            "Finish when the sentence reads as a whole"


checkpointSubtitle : Model -> String
checkpointSubtitle model =
    case model.phase of
        Drafting ->
            if model.referenceRevealed then
                "Reference viewed · will be marked assisted"

            else
                "References hidden · draft autosaved"

        Compared ->
            "Review any module, revise, or close feedback"

        Rereading ->
            "Completion means reread—not mastered"


formatDuration : Int -> String
formatDuration seconds =
    let
        minutes =
            seconds // 60

        remainder =
            modBy 60 seconds
    in
    String.fromInt minutes ++ "m " ++ String.fromInt remainder ++ "s"


addUniqueModule : ModuleId -> List ModuleId -> List ModuleId
addUniqueModule moduleId modules =
    if moduleListMember moduleId modules then
        modules

    else
        moduleId :: modules


moduleListMember : ModuleId -> List ModuleId -> Bool
moduleListMember moduleId modules =
    List.any (\candidate -> moduleKey candidate == moduleKey moduleId) modules


moduleKey : ModuleId -> String
moduleKey moduleId =
    case moduleId of
        GlossModule ->
            "gloss"

        MorphologyModule ->
            "morphology"

        DependencyModule ->
            "dependency"

        LiteralModule ->
            "literal"

        ProseModule ->
            "prose"


twoDigit : Int -> String
twoDigit number =
    if number < 10 then
        "0" ++ String.fromInt number

    else
        String.fromInt number


boolString : Bool -> String
boolString value =
    if value then
        "true"

    else
        "false"
