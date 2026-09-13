module Main exposing (main)

import Browser
import Html exposing (Html, aside, button, div, footer, h1, h2, h3, header, input, label, main_, nav, option, p, section, select, span, text, textarea)
import Html.Attributes exposing (attribute, checked, class, classList, disabled, id, placeholder, rows, selected, type_, value)
import Html.Events exposing (onClick, onInput)
import Json.Decode as Decode
import Time


type Screen
    = LibraryScreen
    | WorkspaceScreen
    | SettingsScreen
    | HistoryScreen
    | AttemptComparisonScreen


type Preset
    = ReadPreset
    | AssistedPreset
    | IntensivePreset
    | CustomPreset


type SettingScope
    = GlobalScope
    | WorkScope
    | SessionScope


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
    { glossDareios : String
    , glossPaides : String
    , glossGignontai : String
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
    { source : CorpusSource
    , sentences : List Sentence
    }


type alias CorpusSource =
    { name : String
    , url : String
    , commit : String
    , license : String
    , edition : String
    }


type alias Sentence =
    { id : String
    , chapter : Int
    , verse : String
    , text : String
    , tokens : List CorpusToken
    }


type alias CorpusToken =
    { id : Int
    , form : String
    , lemma : String
    , upos : String
    , morphology : Morphology
    , head : Int
    , relation : String
    , gloss : String
    , spaceAfter : Bool
    }


type alias Morphology =
    { summary : String
    , case_ : String
    , number : String
    , gender : String
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
    | SelectToken Int
    | SelectPreset Preset
    | SelectScope SettingScope
    | ToggleModule ModuleId
    | CycleModuleMode ModuleId
    | OpenModule ModuleId
    | CloseWorkbench
    | UpdateGlossDareios String
    | UpdateGlossPaides String
    | UpdateGlossGignontai String
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
    | Tick Time.Posix


main : Program Decode.Value Model Msg
main =
    Browser.element
        { init = \flags -> ( init flags, Cmd.none )
        , update = update
        , subscriptions = subscriptions
        , view = view
        }


init : Decode.Value -> Model
init flags =
    { screen = LibraryScreen
    , corpus =
        Decode.decodeValue corpusDecoder flags
            |> Result.withDefault fallbackCorpus
    , sentenceIndex = 0
    , selectedTokenId = Nothing
    , preset = IntensivePreset
    , scope = SessionScope
    , settings = intensiveSettings
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
    }


emptyDraft : Draft
emptyDraft =
    { glossDareios = ""
    , glossPaides = ""
    , glossGignontai = ""
    , morphCase = "—"
    , morphNumber = "—"
    , morphGender = "—"
    , dependencyRoot = "—"
    , dependencyHead = "—"
    , dependencyRelation = "—"
    , literal = ""
    , prose = ""
    }


corpusDecoder : Decode.Decoder Corpus
corpusDecoder =
    Decode.map2 Corpus
        (Decode.field "source" corpusSourceDecoder)
        (Decode.field "sentences" (Decode.list sentenceDecoder))


corpusSourceDecoder : Decode.Decoder CorpusSource
corpusSourceDecoder =
    Decode.map5 CorpusSource
        (Decode.field "name" Decode.string)
        (Decode.field "url" Decode.string)
        (Decode.field "commit" Decode.string)
        (Decode.field "license" Decode.string)
        (Decode.field "edition" Decode.string)


sentenceDecoder : Decode.Decoder Sentence
sentenceDecoder =
    Decode.map5 Sentence
        (Decode.field "i" Decode.string)
        (Decode.field "c" Decode.int)
        (Decode.field "v" Decode.string)
        (Decode.field "x" Decode.string)
        (Decode.field "t" (Decode.list corpusTokenDecoder))


corpusTokenDecoder : Decode.Decoder CorpusToken
corpusTokenDecoder =
    Decode.map8
        (\tokenId form lemma upos morphology head relation gloss ->
            \spaceAfter ->
                { id = tokenId
                , form = form
                , lemma = lemma
                , upos = upos
                , morphology = morphology
                , head = head
                , relation = relation
                , gloss = gloss
                , spaceAfter = spaceAfter
                }
        )
        (Decode.field "i" Decode.int)
        (Decode.field "f" Decode.string)
        (Decode.field "l" Decode.string)
        (Decode.field "p" Decode.string)
        morphologyDecoder
        (Decode.field "h" Decode.int)
        (Decode.field "r" Decode.string)
        (Decode.field "s" Decode.string)
        |> Decode.andThen (\buildToken -> Decode.map buildToken (Decode.field "a" Decode.bool))


morphologyDecoder : Decode.Decoder Morphology
morphologyDecoder =
    Decode.map4 Morphology
        (Decode.field "m" Decode.string)
        (Decode.field "c" Decode.string)
        (Decode.field "n" Decode.string)
        (Decode.field "g" Decode.string)


fallbackCorpus : Corpus
fallbackCorpus =
    { source =
        { name = "UD Ancient Greek PTNK"
        , url = "https://github.com/UniversalDependencies/UD_Ancient_Greek-PTNK"
        , commit = "818fb315ff1f6cd95b6e7fa90f3707488d2b010d"
        , license = "CC BY-SA 4.0"
        , edition = "Septuagint according to Codex Alexandrinus"
        }
    , sentences =
        [ { id = "Septuagint-Genesis-1:1-grc"
          , chapter = 1
          , verse = "1"
          , text = "Ἐν ἀρχῇ ἐποίησεν ὁ θεὸς τὸν οὐρανὸν καὶ τὴν γῆν."
          , tokens =
                [ fallbackToken 1 "Ἐν" "ἐν" "ADP" "" "" "" "" 2 "case" "in,on,by,with,to" True
                , fallbackToken 2 "ἀρχῇ" "ἀρχή" "NOUN" "Case=Dat|Gender=Fem|Number=Sing" "Dat" "Sing" "Fem" 3 "obl:tmod" "beginning,ruler,office" True
                , fallbackToken 3 "ἐποίησεν" "ποιέω" "VERB" "Aspect=Perf|Mood=Ind|Number=Sing|Person=3|Tense=Past|VerbForm=Fin|Voice=Act" "" "Sing" "" 0 "root" "to-do,make" True
                , fallbackToken 4 "ὁ" "ὁ" "DET" "Case=Nom|Definite=Def|Gender=Masc|Number=Sing|PronType=Art" "Nom" "Sing" "Masc" 5 "det" "the;-oh" True
                , fallbackToken 5 "θεὸς" "θεός" "NOUN" "Case=Nom|Gender=Masc|Number=Sing" "Nom" "Sing" "Masc" 3 "nsubj" "god" True
                , fallbackToken 6 "τὸν" "ὁ" "DET" "Case=Acc|Definite=Def|Gender=Masc|Number=Sing|PronType=Art" "Acc" "Sing" "Masc" 7 "det" "the" True
                , fallbackToken 7 "οὐρανὸν" "οὐρανός" "NOUN" "Case=Acc|Gender=Masc|Number=Sing" "Acc" "Sing" "Masc" 3 "obj" "heaven,sky" True
                , fallbackToken 8 "καὶ" "καί" "CCONJ" "" "" "" "" 10 "cc" "and,also,even,then,next" True
                , fallbackToken 9 "τὴν" "ὁ" "DET" "Case=Acc|Definite=Def|Gender=Fem|Number=Sing|PronType=Art" "Acc" "Sing" "Fem" 10 "det" "the" True
                , fallbackToken 10 "γῆν" "γῆ" "NOUN" "Case=Acc|Gender=Fem|Number=Sing" "Acc" "Sing" "Fem" 7 "conj" "earth" False
                , fallbackToken 11 "." "." "PUNCT" "" "" "" "" 3 "punct" "" True
                ]
          }
        ]
    }


fallbackToken : Int -> String -> String -> String -> String -> String -> String -> String -> Int -> String -> String -> Bool -> CorpusToken
fallbackToken tokenId form lemma upos summary case_ number gender head relation gloss spaceAfter =
    { id = tokenId
    , form = form
    , lemma = lemma
    , upos = upos
    , morphology = Morphology summary case_ number gender
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
    , dependency = Suggested
    , literal = Suggested
    , prose = Suggested
    }


subscriptions : Model -> Sub Msg
subscriptions model =
    if model.screen == WorkspaceScreen then
        Time.every 1000 Tick

    else
        Sub.none


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    ( case msg of
        ShowLibrary ->
            { model | screen = LibraryScreen, notice = Nothing }

        ShowWorkspace ->
            { model | screen = WorkspaceScreen, notice = Nothing }

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

        UpdateGlossDareios entered ->
            updateDraft (\draft -> { draft | glossDareios = entered }) model

        UpdateGlossPaides entered ->
            updateDraft (\draft -> { draft | glossPaides = entered }) model

        UpdateGlossGignontai entered ->
            updateDraft (\draft -> { draft | glossGignontai = entered }) model

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
                    |> withNotice "Passage reread recorded. The next Genesis passage is ready."

            else
                { model | screen = LibraryScreen, notice = Just "Genesis reread recorded. You reached the end of the bundled text." }

        ShowNotice notice ->
            { model | notice = Just notice }

        DismissNotice ->
            { model | notice = Nothing }

        Tick _ ->
            { model | elapsedSeconds = model.elapsedSeconds + 1 }
    , Cmd.none
    )


moveToSentence : Int -> Model -> Model
moveToSentence sentenceIndex model =
    if sentenceIndex < 0 || sentenceIndex >= List.length model.corpus.sentences then
        model

    else
        { model
            | screen = WorkspaceScreen
            , sentenceIndex = sentenceIndex
            , selectedTokenId = Nothing
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
    [ GlossModule, MorphologyModule, DependencyModule, LiteralModule, ProseModule ]
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
    div [ class "app-shell" ]
        [ viewAppHeader model
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
        ]


viewAppHeader : Model -> Html Msg
viewAppHeader model =
    header [ class "app-header" ]
        [ button [ class "brand-button", type_ "button", onClick ShowLibrary, attribute "aria-label" "Aristos library" ]
            [ span [ class "brand-mark", attribute "aria-hidden" "true" ] [ text "Α" ]
            , span [ class "brand-word" ] [ text "Aristos" ]
            ]
        , nav [ class "global-nav", attribute "aria-label" "Primary navigation" ]
            [ navButton "Library" ShowLibrary (model.screen == LibraryScreen)
            , navButton "Workspace" ShowWorkspace (model.screen == WorkspaceScreen)
            , navButton "History" ShowHistory (model.screen == HistoryScreen || model.screen == AttemptComparisonScreen)
            ]
        , button [ class "settings-button", type_ "button", onClick ShowSettings ]
            [ span [ attribute "aria-hidden" "true" ] [ text "⚙" ]
            , span [ class "settings-label" ] [ text "Modules" ]
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
        [ section [ class "library-hero" ]
            [ div []
                [ p [ class "eyebrow" ] [ text "Local Greek library" ]
                , h1 [] [ text "Choose a text. Build a workspace." ]
                , p [ class "lead" ] [ text "Read freely, or compose only the form, syntax, and translation tools useful for this session." ]
                ]
            , div [ class "library-summary" ]
                [ span [ class "summary-value" ] [ text "50" ]
                , span [] [ text "Genesis chapters" ]
                , span [ class "summary-divider" ] []
                , span [ class "summary-value" ] [ text (String.fromInt (List.length model.corpus.sentences)) ]
                , span [] [ text "real passages" ]
                ]
            ]
        , section [ class "pack-list", attribute "aria-label" "Content packs" ]
            [ viewFeaturedPack model
            , viewPackCard "Ξενοφῶντος Ἀνάβασις" "Anabasis · Book 1" "Classical Attic · Prose" "UI fixture removed" "Not bundled in this build" "Coming later"
            , viewPackCard "Ἰλιάς" "Iliad · Book 1" "Homeric · Poetry" "UI fixture removed" "Not bundled in this build" "Coming later"
            ]
        ]


viewFeaturedPack : Model -> Html Msg
viewFeaturedPack model =
    section [ class "pack-card featured-pack" ]
        [ div [ class "pack-accent", attribute "aria-hidden" "true" ] [ text "Γ" ]
        , div [ class "pack-body" ]
            [ div [ class "pack-heading" ]
                [ div []
                    [ p [ class "pack-language" ] [ text "Septuagint · Biblical Greek" ]
                    , h2 [] [ text "Genesis · Complete" ]
                    , p [ class "greek-subtitle" ] [ text "Γένεσις" ]
                    ]
                , span [ class "availability good" ] [ text "Bundled · 6.2 MB" ]
                ]
            , p [ class "pack-description" ] [ text "All 50 chapters from a real annotated treebank—not repeated prototype copy." ]
            , div [ class "capability-strip" ]
                [ capabilityPill True "Glosses 100%"
                , capabilityPill True "Morphology 76%"
                , capabilityPill True "Dependencies 100%"
                , capabilityPill False "Translation 0%"
                ]
            , div [ class "pack-footer" ]
                [ div [ class "pack-progress" ]
                    [ div [ class "progress-track" ] [ span [ class "progress-fill" ] [] ]
                    , span [] [ text (String.fromInt (List.length model.corpus.sentences) ++ " passages · 37,106 tokens · CC BY-SA 4.0") ]
                    ]
                , div [ class "button-row" ]
                    [ button [ class "secondary-button", type_ "button", onClick ShowSettings ] [ text "Configure" ]
                    , button [ class "primary-button", type_ "button", onClick ShowWorkspace ] [ text "Start Genesis →" ]
                    ]
                ]
            ]
        ]


viewPackCard : String -> String -> String -> String -> String -> String -> Html Msg
viewPackCard greekTitle englishTitle genre coverage limitation progress =
    section [ class "pack-card compact-pack" ]
        [ div [ class "pack-heading" ]
            [ div []
                [ p [ class "pack-language" ] [ text genre ]
                , h2 [] [ text englishTitle ]
                , p [ class "greek-subtitle" ] [ text greekTitle ]
                ]
            , span [ class "availability" ] [ text "Not bundled" ]
            ]
        , div [ class "compact-capabilities" ]
            [ span [] [ text coverage ]
            , span [ class "limited-capability" ] [ text limitation ]
            ]
        , div [ class "pack-footer" ]
            [ span [ class "muted" ] [ text progress ]
            , button [ class "text-button", type_ "button", onClick (ShowNotice (englishTitle ++ " is not bundled in this real-data build.")) ] [ text "Unavailable" ]
            ]
        ]


capabilityPill : Bool -> String -> Html Msg
capabilityPill available label =
    span [ classList [ ( "capability-pill", True ), ( "is-limited", not available ) ] ]
        [ span [ class "capability-dot", attribute "aria-hidden" "true" ] []
        , text label
        ]


viewSettings : Model -> Html Msg
viewSettings model =
    main_ [ class "page settings-page" ]
        [ section [ class "settings-intro" ]
            [ div []
                [ p [ class "eyebrow" ] [ text "Genesis · Complete" ]
                , h1 [] [ text "Compose your reading workspace" ]
                , p [ class "lead" ] [ text "A preset is only a starting point. Greek remains available even when every learning module is off." ]
                ]
            , button [ class "primary-button open-workspace-button", type_ "button", onClick ShowWorkspace ] [ text "Open workspace →" ]
            ]
        , section [ class "setting-block" ]
            [ div [ class "setting-heading" ]
                [ div []
                    [ p [ class "eyebrow" ] [ text "Start with a preset" ]
                    , h2 [] [ text "How intensively do you want to read?" ]
                    ]
                , viewScopeControl model.scope
                ]
            , div [ class "preset-grid" ]
                [ viewPresetCard model.preset ReadPreset "Read" "Greek first, with word help available only when needed." "≈ 4 min / passage"
                , viewPresetCard model.preset AssistedPreset "Assisted" "Selective help and a light comparison prompt." "≈ 8 min / passage"
                , viewPresetCard model.preset IntensivePreset "Intensive" "Forms, structure, and both translation drafts." "≈ 18 min / passage"
                , viewPresetCard model.preset CustomPreset "Custom" "Your explicit module and cadence choices." "Variable"
                ]
            ]
        , section [ class "module-settings" ]
            [ div [ class "module-section-heading" ]
                [ div []
                    [ p [ class "eyebrow" ] [ text "Workspace modules" ]
                    , h2 [] [ text "Available from this content pack" ]
                    ]
                , span [ class "coverage-key" ] [ text "UD Ancient Greek PTNK · commit 818fb31" ]
                ]
            , viewRequiredModule
            , viewModuleSetting model GlossModule "Enter contextual glosses" "Recall a sense for selected blockers, then compare with the imported gloss." "100% of content tokens" "UD Ancient Greek PTNK · imported"
            , viewModuleSetting model MorphologyModule "Analyze morphology" "Choose applicable features for selected forms; no free-text label matching." "76% feature coverage" "UD Ancient Greek PTNK · imported"
            , viewModuleSetting model DependencyModule "Build dependency relationships" "Find the root and attach one core argument. Full trees remain optional." "100% of sentences" "UD PTNK · projected, corrected reference"
            , viewModuleSetting model LiteralModule "Draft a literal translation" "Expose structure and supplied relationships in your own words." "All Greek passages" "Learner-authored · no reference"
            , viewModuleSetting model ProseModule "Draft a prose translation" "State the understood proposition naturally and retain it for later comparison." "All Greek passages" "Learner-authored · no aligned reference"
            , viewUnavailableModule "Reference translations" "No source-aligned English translation in this pack" "0 of 1,491 passages"
            , viewUnavailableModule "Curated gist check" "No curated prompts in this edition" "0 of 1,491 passages"
            , viewUnavailableModule "Reconstruct word order" "Activity generator not included in this prototype" "Capability pending"
            ]
        , footer [ class "settings-footer" ]
            [ div []
                [ strongText (scopeLabel model.scope)
                , span [ class "muted" ] [ text " · Changes are explicit and reversible." ]
                ]
            , button [ class "primary-button", type_ "button", onClick ShowWorkspace ] [ text "Use this workspace" ]
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
        , button
            [ classList [ ( "module-mode", True ), ( "is-off", not enabled ) ]
            , type_ "button"
            , disabled (not enabled)
            , onClick (CycleModuleMode moduleId)
            , attribute "aria-label" ("Change cadence for " ++ title)
            ]
            [ text (modeLabel mode)
            , span [ attribute "aria-hidden" "true" ] [ text " ↻" ]
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
    in
    main_ [ class "workspace-page" ]
        [ div [ class "work-context-bar" ]
            [ div [ class "context-title" ]
                [ button [ class "icon-button", type_ "button", onClick ShowLibrary, attribute "aria-label" "Back to library" ] [ text "←" ]
                , div []
                    [ span [ class "context-work" ] [ text "Genesis · Septuagint" ]
                    , span [ class "context-division" ] [ text (sentenceReference sentence ++ " · Passage " ++ String.fromInt (model.sentenceIndex + 1) ++ " of " ++ String.fromInt (List.length model.corpus.sentences)) ]
                    ]
                ]
            , div [ class "context-actions" ]
                [ label [ class "chapter-jump" ]
                    [ span [] [ text "Chapter" ]
                    , select [ value (String.fromInt sentence.chapter), onInput JumpToChapter ]
                        (List.range 1 50
                            |> List.map (\chapter -> option [ value (String.fromInt chapter), selected (chapter == sentence.chapter) ] [ text (String.fromInt chapter) ])
                        )
                    ]
                , span [ class "autosave-status" ] [ span [ class "save-dot" ] [], text "Draft saved" ]
                , button [ class "text-button", type_ "button", onClick ShowHistory ] [ text "History · ", text (String.fromInt model.attemptCount) ]
                ]
            ]
        , div [ classList [ ( "workspace-grid", True ), ( "is-rereading", model.phase == Rereading ) ] ]
            [ viewSourceRail model
            , viewReadingStage model
            , if model.phase == Rereading then
                text ""

              else
                viewWorkbench model
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
            , h2 [] [ text "Ἡ Γένεσις κατὰ τοὺς Ἑβδομήκοντα" ]
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
            , span [] [ text model.corpus.source.name, span [ class "muted" ] [ text (" · " ++ model.corpus.source.license ++ " · 818fb31") ] ]
            ]
        ]


viewReadingStage : Model -> Html Msg
viewReadingStage model =
    let
        sentence =
            currentSentence model
    in
    section [ class "reading-stage" ]
        [ div [ class "passage-heading" ]
            [ div []
                [ p [ class "eyebrow" ] [ text (phaseEyebrow model.phase) ]
                , h1 [] [ text (sentenceReference sentence) ]
                ]
            , span [ classList [ ( "phase-badge", True ), ( "is-compared", model.phase == Compared ), ( "is-reread", model.phase == Rereading ) ] ]
                [ text (phaseLabel model.phase) ]
            ]
        , if model.phase == Rereading then
            div [ class "reread-instruction" ]
                [ span [ class "reread-icon", attribute "aria-hidden" "true" ] [ text "↻" ]
                , div []
                    [ strongText "Clean reread"
                    , p [] [ text "Feedback and word tools are closed. Let the Greek carry the meaning." ]
                    ]
                ]

          else
            p [ class "reading-instruction" ]
                [ text "Read the whole sentence before opening a tool. "
                , span [] [ text "Attempt first; references remain hidden until submission." ]
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
                    moduleMode MorphologyModule model.settings /= ModuleOff && token.morphology.summary /= ""

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
            [ div []
                [ p [ class "eyebrow" ] [ text "Activity tray" ]
                , h2 [] [ text "Your tools for this passage" ]
                ]
            , span [ class "tray-help" ] [ text "One opens at a time" ]
            ]
        , if List.isEmpty modules then
            div [ class "read-only-state" ]
                [ span [ class "read-only-mark", attribute "aria-hidden" "true" ] [ text "α" ]
                , div []
                    [ strongText "Read-only session"
                    , p [] [ text "No exercise interrupts this passage. Add a module only if it serves your reading." ]
                    ]
                , button [ class "secondary-button", type_ "button", onClick ShowSettings ] [ text "Add modules" ]
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
                |> List.indexedMap
                    (\index token ->
                        glossField token.form (glossDraftAt index model.draft) (glossUpdateAt index)
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
            , selectField "Gender" model.draft.morphGender UpdateMorphGender [ "—", "Masculine", "Feminine", "Neuter" ]
            ]
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
        , p [ class "field-note" ] [ text "Answers store token IDs and relations—not screen coordinates. PTNK dependencies are attributed references, not unquestionable truth." ]
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
        draftText =
            if literal then
                model.draft.literal

            else
                model.draft.prose

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
        , div [ class "no-reference-panel" ]
            [ strongText "No aligned translation in this content pack"
            , p [] [ text "Your draft will be retained exactly as written, but no English reference or translation score will be shown." ]
            ]
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
                        |> List.indexedMap
                            (\index token ->
                                let
                                    entered =
                                        glossDraftAt index model.draft
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
                , p [ class "provenance-panel" ] [ text ("Lemma " ++ target.lemma ++ " · " ++ target.morphology.summary ++ " · UD Ancient Greek PTNK") ]
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
                [ comparisonBanner (String.fromInt matches ++ " of 3 fields match") "Task-scoped result · imported PTNK reference"
                , viewMiniTree model True
                , featureComparison "Root" (tokenFormForValue sentence model.draft.dependencyRoot) root.form (model.draft.dependencyRoot == rootId)
                , featureComparison "Core edge" (target.form ++ " → " ++ submittedHead) (target.form ++ " → " ++ referenceHead) (model.draft.dependencyHead == headId)
                , featureComparison "Relation" model.draft.dependencyRelation target.relation (model.draft.dependencyRelation == target.relation)
                , button [ class "disagree-button", type_ "button", onClick (ShowNotice "Disagreement noted. The imported analysis remains visible with its provenance.") ] [ text "I disagree with this reference" ]
                ]

        LiteralModule ->
            viewTranslationComparison model.draft.literal "Literal attempt"

        ProseModule ->
            viewTranslationComparison model.draft.prose "Prose attempt"


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


viewTranslationComparison : String -> String -> Html Msg
viewTranslationComparison mine labelText =
    div [ class "comparison-stack" ]
        [ comparisonBanner "Draft submitted" "No automatic translation score"
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
            ]
        , div [ class "no-reference-panel" ]
            [ strongText "No aligned English reference"
            , p [] [ text "This PTNK content pack supplies Greek annotations but no translation. Your exact draft remains available for a later revision." ]
            ]
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
                                (String.fromInt (List.length (enabledModules model.settings)) ++ " modules · " ++ if model.referenceRevealed then "assisted" else "unassisted")
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
                , button [ class "filter-button", type_ "button", onClick (ShowNotice "Cross-passage history arrives with persistent attempt storage.") ] [ text "All Genesis", span [] [ text "—" ] ]
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
                    , span [ class "version-badge" ] [ text "PTNK · 818fb31" ]
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
                , span [ class "neutral-badge" ] [ text "No aligned reference or score" ]
                ]
            , div [ class "attempt-columns" ]
                [ blockquoteElement (responseOrEmpty previous.prose)
                , blockquoteElement (responseOrEmpty model.draft.prose)
                ]
            ]
        , section [ class "comparison-section" ]
            [ div [ class "comparison-section-heading" ]
                [ p [ class "eyebrow" ] [ text "Morphology response" ]
                , span [ class "neutral-badge" ] [ text "Same PTNK reference version" ]
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
            , verse = "1"
            , text = "No Genesis data loaded."
            , tokens = []
            }


sentenceReference : Sentence -> String
sentenceReference sentence =
    "Genesis " ++ String.fromInt sentence.chapter ++ ":" ++ String.replace "-" "–" sentence.verse


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
        |> List.filter
            (\token ->
                token.gloss /= ""
                    && not (List.member token.upos [ "PUNCT", "DET", "CCONJ", "SCONJ", "PART", "ADP" ])
            )
        |> List.take 3


glossDraftAt : Int -> Draft -> String
glossDraftAt index draft =
    case index of
        0 ->
            draft.glossDareios

        1 ->
            draft.glossGignontai

        _ ->
            draft.glossPaides


glossUpdateAt : Int -> String -> Msg
glossUpdateAt index =
    case index of
        0 ->
            UpdateGlossDareios

        1 ->
            UpdateGlossGignontai

        _ ->
            UpdateGlossPaides


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
    [ GlossModule, MorphologyModule, DependencyModule, LiteralModule, ProseModule ]
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
            "Enter a contextual sense for selected blockers before seeing the imported gloss."

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
                        responseCountLabel
                            (countResponses [ model.draft.glossDareios, model.draft.glossGignontai, model.draft.glossPaides ])
                            3

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
                    "One checkpoint · " ++ String.fromInt (List.length (enabledModules model.settings)) ++ " modules"

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
