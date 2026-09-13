module Main exposing (main)

import Browser
import Html exposing (Html, aside, button, div, footer, h1, h2, h3, header, input, label, main_, nav, option, p, section, select, span, text, textarea)
import Html.Attributes exposing (attribute, checked, class, classList, disabled, id, placeholder, rows, selected, type_, value)
import Html.Events exposing (onClick, onInput)
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


type alias Model =
    { screen : Screen
    , preset : Preset
    , scope : SettingScope
    , settings : ModuleSettings
    , activeModule : Maybe ModuleId
    , phase : WorkspacePhase
    , draft : Draft
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


main : Program () Model Msg
main =
    Browser.element
        { init = \_ -> ( init, Cmd.none )
        , update = update
        , subscriptions = subscriptions
        , view = view
        }


init : Model
init =
    { screen = WorkspaceScreen
    , preset = IntensivePreset
    , scope = SessionScope
    , settings = intensiveSettings
    , activeModule = Nothing
    , phase = Drafting
    , draft = emptyDraft
    , skippedModules = []
    , referenceRevealed = False
    , revisionParent = Nothing
    , attemptCount = 2
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
            { model | screen = AttemptComparisonScreen, notice = Nothing }

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
            { model | screen = LibraryScreen, notice = Just "Passage reread recorded. Your next reading remains optional." }

        ShowNotice notice ->
            { model | notice = Just notice }

        DismissNotice ->
            { model | notice = Nothing }

        Tick _ ->
            { model | elapsedSeconds = model.elapsedSeconds + 1 }
    , Cmd.none
    )


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
                [ span [ class "summary-value" ] [ text "3" ]
                , span [] [ text "content packs" ]
                , span [ class "summary-divider" ] []
                , span [ class "summary-value" ] [ text (String.fromInt model.attemptCount) ]
                , span [] [ text "attempts saved" ]
                ]
            ]
        , section [ class "pack-list", attribute "aria-label" "Content packs" ]
            [ viewFeaturedPack
            , viewPackCard "Κατὰ Μᾶρκον" "Gospel of Mark" "Koine · Narrative" "Greek 100% · Morphology 99%" "No validated dependency layer" "8 of 42 passages"
            , viewPackCard "Ἰλιάς" "Iliad · Book 1" "Homeric · Poetry" "Greek 100% · Lemmas 100%" "Translation alignment limited" "Not started"
            ]
        ]


viewFeaturedPack : Html Msg
viewFeaturedPack =
    section [ class "pack-card featured-pack" ]
        [ div [ class "pack-accent", attribute "aria-hidden" "true" ] [ text "Ξ" ]
        , div [ class "pack-body" ]
            [ div [ class "pack-heading" ]
                [ div []
                    [ p [ class "pack-language" ] [ text "Classical Attic · Prose" ]
                    , h2 [] [ text "Anabasis · Book 1" ]
                    , p [ class "greek-subtitle" ] [ text "Ξενοφῶντος Ἀνάβασις" ]
                    ]
                , span [ class "availability good" ] [ text "On device" ]
                ]
            , p [ class "pack-description" ] [ text "A mass-imported fixture with enough annotation layers to exercise the complete workbench." ]
            , div [ class "capability-strip" ]
                [ capabilityPill True "Morphology 99%"
                , capabilityPill True "Dependencies 98%"
                , capabilityPill True "Translation 100%"
                , capabilityPill False "Curated gist 0%"
                ]
            , div [ class "pack-footer" ]
                [ div [ class "pack-progress" ]
                    [ div [ class "progress-track" ] [ span [ class "progress-fill" ] [] ]
                    , span [] [ text "12 of 86 passages · last read today" ]
                    ]
                , div [ class "button-row" ]
                    [ button [ class "secondary-button", type_ "button", onClick ShowSettings ] [ text "Configure" ]
                    , button [ class "primary-button", type_ "button", onClick ShowWorkspace ] [ text "Resume reading →" ]
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
            , span [ class "availability" ] [ text "On device" ]
            ]
        , div [ class "compact-capabilities" ]
            [ span [] [ text coverage ]
            , span [ class "limited-capability" ] [ text limitation ]
            ]
        , div [ class "pack-footer" ]
            [ span [ class "muted" ] [ text progress ]
            , button [ class "text-button", type_ "button", onClick ShowWorkspace ] [ text "Open →" ]
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
                [ p [ class "eyebrow" ] [ text "Anabasis · Book 1" ]
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
                , span [ class "coverage-key" ] [ text "Imported fixture · pack v2026.09" ]
                ]
            , viewRequiredModule
            , viewModuleSetting model GlossModule "Enter contextual glosses" "Recall a sense for selected blockers, then compare with the imported gloss." "100% of content tokens" "Perseus treebank · imported"
            , viewModuleSetting model MorphologyModule "Analyze morphology" "Choose applicable features for selected forms; no free-text label matching." "99.4% of tokens" "UD Greek Perseus · imported"
            , viewModuleSetting model DependencyModule "Build dependency relationships" "Find the root and attach one core argument. Full trees remain optional." "98.9% of sentences" "UD Greek Perseus · imported"
            , viewModuleSetting model LiteralModule "Draft a literal translation" "Expose structure and supplied relationships in your own words." "All Greek passages" "Learner-authored"
            , viewModuleSetting model ProseModule "Draft a prose translation" "State the understood proposition naturally, then compare after submission." "Reference aligned 100%" "Public-domain alignment"
            , viewUnavailableModule "Curated gist check" "No curated prompts in this edition" "0 of 86 passages"
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
    main_ [ class "workspace-page" ]
        [ div [ class "work-context-bar" ]
            [ div [ class "context-title" ]
                [ button [ class "icon-button", type_ "button", onClick ShowLibrary, attribute "aria-label" "Back to library" ] [ text "←" ]
                , div []
                    [ span [ class "context-work" ] [ text "Anabasis · Book 1" ]
                    , span [ class "context-division" ] [ text "Chapter 1 · Passage 1 of 6" ]
                    ]
                ]
            , div [ class "context-actions" ]
                [ span [ class "autosave-status" ] [ span [ class "save-dot" ] [], text "Draft saved" ]
                , button [ class "text-button", type_ "button", onClick ShowHistory ] [ text "History · " , text (String.fromInt model.attemptCount) ]
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
    aside [ class "source-rail" ]
        [ div [ class "rail-section" ]
            [ p [ class "rail-label" ] [ text "Source" ]
            , h2 [] [ text "Ξενοφῶντος Ἀνάβασις" ]
            , p [ class "muted" ] [ text "Book 1 · Chapter 1.1" ]
            ]
        , div [ class "rail-section" ]
            [ p [ class "rail-label" ] [ text "Session" ]
            , div [ class "rail-stat" ] [ span [] [ text "Preset" ], strongText (presetLabel model.preset) ]
            , div [ class "rail-stat" ] [ span [] [ text "Active time" ], strongText (formatDuration model.elapsedSeconds) ]
            , div [ class "rail-stat" ] [ span [] [ text "Modules" ], strongText (String.fromInt (List.length (enabledModules model.settings))) ]
            , button [ class "rail-link", type_ "button", onClick ShowSettings ] [ text "Adjust modules →" ]
            ]
        , div [ class "rail-section prior-context" ]
            [ p [ class "rail-label" ] [ text "Source context" ]
            , p [ class "greek-context" ] [ text "Δαρεῖος μὲν οὖν ἀπέθανεν…" ]
            , p [ class "context-note" ] [ text "Previous Greek only. No authored summary is present in this pack." ]
            ]
        , div [ class "pack-provenance" ]
            [ span [ class "provenance-icon", attribute "aria-hidden" "true" ] [ text "i" ]
            , span [] [ text "Imported text and annotations", span [ class "muted" ] [ text " · pack v2026.09" ] ]
            ]
        ]


viewReadingStage : Model -> Html Msg
viewReadingStage model =
    section [ class "reading-stage" ]
        [ div [ class "passage-heading" ]
            [ div []
                [ p [ class "eyebrow" ] [ text (phaseEyebrow model.phase) ]
                , h1 [] [ text "Anabasis 1.1.1" ]
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
            [ span [] [ text "Xenophon · normalized public-domain fixture" ]
            , span [] [ text "18 tokens · 1 sentence" ]
            ]
        , if model.phase == Rereading then
            div [ class "reread-space" ] []

          else
            viewActivityTray model
        ]


viewGreekPassage : Model -> Html Msg
viewGreekPassage model =
    let
        toolsAvailable =
            moduleMode GlossModule model.settings /= ModuleOff || moduleMode MorphologyModule model.settings /= ModuleOff

        tokenButton form =
            button
                [ class "greek-token"
                , type_ "button"
                , disabled (not toolsAvailable || model.phase == Rereading)
                , onClick
                    (if moduleMode MorphologyModule model.settings /= ModuleOff then
                        OpenModule MorphologyModule

                     else
                        OpenModule GlossModule
                    )
                ]
                [ text form ]
    in
    div [ classList [ ( "greek-passage", True ), ( "clean-passage", model.phase == Rereading ) ], attribute "lang" "grc" ]
        [ tokenButton "Δαρείου"
        , tokenButton "καὶ"
        , tokenButton "Παρυσάτιδος"
        , tokenButton "γίγνονται"
        , tokenButton "παῖδες"
        , tokenButton "δύο,"
        , tokenButton "πρεσβύτερος"
        , tokenButton "μὲν"
        , tokenButton "Ἀρταξέρξης,"
        , tokenButton "νεώτερος"
        , tokenButton "δὲ"
        , tokenButton "Κῦρος."
        ]


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
                    "Open a module to compare your response with its imported reference."

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
    div [ class "form-stack" ]
        [ glossField "Δαρείου" model.draft.glossDareios UpdateGlossDareios
        , glossField "γίγνονται" model.draft.glossGignontai UpdateGlossGignontai
        , glossField "παῖδες" model.draft.glossPaides UpdateGlossPaides
        , p [ class "field-note" ] [ text "Original wording is preserved. A different synonym is not automatically wrong." ]
        , viewRevealedReference model "Imported glosses: of Darius · are born · sons"
        ]


glossField : String -> String -> (String -> Msg) -> Html Msg
glossField token entered msg =
    label [ class "gloss-field" ]
        [ span [ class "field-token" ] [ text token ]
        , input [ type_ "text", value entered, onInput msg, placeholder "Contextual sense…" ] []
        ]


viewMorphologyDraft : Model -> Html Msg
viewMorphologyDraft model =
    div []
        [ div [ class "target-token-card" ]
            [ span [ class "token-index" ] [ text "5" ]
            , div []
                [ span [ class "target-token" ] [ text "παῖδες" ]
                , span [ class "target-lemma" ] [ text "Lemma hidden until submit" ]
                ]
            ]
        , div [ class "structured-fields" ]
            [ selectField "Case" model.draft.morphCase UpdateMorphCase [ "—", "Nominative", "Genitive", "Accusative", "Vocative" ]
            , selectField "Number" model.draft.morphNumber UpdateMorphNumber [ "—", "Singular", "Dual", "Plural" ]
            , selectField "Gender" model.draft.morphGender UpdateMorphGender [ "—", "Masculine", "Feminine", "Neuter" ]
            ]
        , button [ class "uncertain-button", type_ "button", onClick (ShowNotice "Uncertainty recorded with this draft; it will remain distinct from an omitted answer.") ] [ text "+ Mark an uncertain alternative" ]
        , viewRevealedReference model "Imported analysis: noun · nominative plural masculine"
        ]


selectField : String -> String -> (String -> Msg) -> List String -> Html Msg
selectField fieldLabel current msg choices =
    label [ class "select-field" ]
        [ span [] [ text fieldLabel ]
        , select [ value current, onInput msg ]
            (List.map
                (\choice -> option [ value choice, selected (choice == current) ] [ text choice ])
                choices
            )
        ]


viewDependencyDraft : Model -> Html Msg
viewDependencyDraft model =
    div []
        [ div [ class "task-scope" ]
            [ span [ class "scope-pill" ] [ text "Partial task" ]
            , span [] [ text "Find the root and attach one core argument." ]
            ]
        , viewMiniTree model False
        , div [ class "dependency-fields" ]
            [ selectField "Finite predicate / root" model.draft.dependencyRoot UpdateDependencyRoot [ "—", "γίγνονται", "παῖδες", "δύο" ]
            , div [ class "edge-builder" ]
                [ span [ class "edge-dependent" ] [ text "παῖδες" ]
                , span [ class "edge-arrow", attribute "aria-hidden" "true" ] [ text "→" ]
                , selectField "Head" model.draft.dependencyHead UpdateDependencyHead [ "—", "γίγνονται", "δύο", "Ἀρταξέρξης" ]
                ]
            , selectField "Relation" model.draft.dependencyRelation UpdateDependencyRelation [ "—", "nsubj", "obj", "appos", "conj" ]
            ]
        , p [ class "field-note" ] [ text "Keyboard controls store token IDs and relations—not screen coordinates." ]
        , viewRevealedReference model "Imported edge: παῖδες → γίγνονται · NSUBJ"
        ]


viewMiniTree : Model -> Bool -> Html Msg
viewMiniTree model showReference =
    if showReference then
        div [ class "mini-tree show-reference", attribute "aria-label" "Imported dependency reference" ]
            [ div [ class "tree-root" ]
                [ span [ class "tree-relation" ] [ text "ROOT" ]
                , span [ class "tree-token" ] [ text "γίγνονται" ]
                ]
            , div [ class "tree-stem", attribute "aria-hidden" "true" ] []
            , div [ class "tree-children" ]
                [ div [ class "tree-node muted-node" ]
                    [ span [ class "tree-relation" ] [ text "obl" ]
                    , span [ class "tree-token" ] [ text "Δαρείου" ]
                    ]
                , div [ class "tree-node answer-node" ]
                    [ span [ class "tree-relation" ] [ text "NSUBJ" ]
                    , span [ class "tree-token" ] [ text "παῖδες" ]
                    ]
                , div [ class "tree-node muted-node" ]
                    [ span [ class "tree-relation" ] [ text "appos" ]
                    , span [ class "tree-token" ] [ text "Ἀρταξέρξης" ]
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
                    , span [ class "tree-token" ] [ text model.draft.dependencyRoot ]
                    ]

              else
                div [ class "tree-empty" ] [ text "Choose a root below" ]
            , div [ class "tree-draft-tokens" ]
                [ div [ class "tree-node" ] [ span [ class "tree-token" ] [ text "Δαρείου" ] ]
                , div [ class "tree-node answer-node" ] [ span [ class "tree-token" ] [ text "παῖδες" ] ]
                , div [ class "tree-node" ] [ span [ class "tree-token" ] [ text "Ἀρταξέρξης" ] ]
                ]
            , if hasResponse model.draft.dependencyHead then
                div [ class "draft-edge-preview" ]
                    [ span [] [ text "Your edge" ]
                    , strongText
                        ("παῖδες → "
                            ++ model.draft.dependencyHead
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
        , viewRevealedReference model "Reference: Darius and Parysatis had two sons, Artaxerxes the elder and Cyrus the younger."
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
    case moduleId of
        GlossModule ->
            div [ class "comparison-stack" ]
                [ comparisonBanner "Compared with imported contextual glosses" "Differences require your judgment"
                , comparisonRow "Δαρείου" model.draft.glossDareios "of Darius" True
                , comparisonRow "γίγνονται" model.draft.glossGignontai "are born" True
                , comparisonRow "παῖδες" model.draft.glossPaides "sons" False
                , viewSelfAssessment
                ]

        MorphologyModule ->
            let
                matches =
                    countTrue
                        [ model.draft.morphCase == "Nominative"
                        , model.draft.morphNumber == "Plural"
                        , model.draft.morphGender == "Masculine"
                        ]
            in
            div [ class "comparison-stack" ]
                [ comparisonBanner (String.fromInt matches ++ " of 3 features match") "Accuracy on this token · imported reference"
                , featureComparison "Case" model.draft.morphCase "Nominative" (model.draft.morphCase == "Nominative")
                , featureComparison "Number" model.draft.morphNumber "Plural" (model.draft.morphNumber == "Plural")
                , featureComparison "Gender" model.draft.morphGender "Masculine" (model.draft.morphGender == "Masculine")
                , p [ class "provenance-panel" ] [ text "Reference · UD Greek Perseus 2.15 · imported annotation · pack v2026.09" ]
                ]

        DependencyModule ->
            let
                matches =
                    countTrue
                        [ model.draft.dependencyRoot == "γίγνονται"
                        , model.draft.dependencyHead == "γίγνονται"
                        , model.draft.dependencyRelation == "nsubj"
                        ]
            in
            div [ class "comparison-stack" ]
                [ comparisonBanner (String.fromInt matches ++ " of 3 fields match") "Task-scoped result · imported reference"
                , viewMiniTree model True
                , featureComparison "Root" model.draft.dependencyRoot "γίγνονται" (model.draft.dependencyRoot == "γίγνονται")
                , featureComparison "Core edge" ("παῖδες → " ++ model.draft.dependencyHead) "παῖδες → γίγνονται" (model.draft.dependencyHead == "γίγνονται")
                , featureComparison "Relation" model.draft.dependencyRelation "nsubj" (model.draft.dependencyRelation == "nsubj")
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
        [ comparisonBanner "Ready for your judgment" "No automatic translation score"
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
            , div [ class "reference-text" ]
                [ span [ class "compare-label" ] [ text "Aligned reference" ]
                , p [] [ text "Darius and Parysatis had two sons, Artaxerxes the elder and Cyrus the younger." ]
                ]
            ]
        , viewSelfAssessment
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
            span [] [ text "Attempt 0" , text (String.fromInt model.attemptCount) ]
        ]


viewWorkspaceFooter : Model -> Html Msg
viewWorkspaceFooter model =
    footer [ class "workspace-footer" ]
        [ button [ class "footer-side-button", type_ "button", disabled True ] [ text "← Previous" ]
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
    main_ [ class "page history-page" ]
        [ section [ class "history-intro" ]
            [ div []
                [ p [ class "eyebrow" ] [ text "Attempt history" ]
                , h1 [] [ text "Your work remains yours—and unchanged." ]
                , p [ class "lead" ] [ text "Submitted attempts are immutable. Compare them, or revise by creating a linked child attempt." ]
                ]
            , button [ class "primary-button", type_ "button", onClick ShowWorkspace ] [ text "Return to passage" ]
            ]
        , div [ class "history-layout" ]
            [ aside [ class "history-filter" ]
                [ p [ class "rail-label" ] [ text "Showing" ]
                , button [ class "filter-button is-active", type_ "button" ] [ text "This sentence", span [] [ text (String.fromInt model.attemptCount) ] ]
                , button [ class "filter-button", type_ "button", onClick (ShowNotice "The full-work history filter is outside this fixture’s sample data.") ] [ text "All Anabasis", span [] [ text "18" ] ]
                , button [ class "filter-button", type_ "button", onClick (ShowNotice "The all-works history filter is outside this fixture’s sample data.") ] [ text "All works", span [] [ text "31" ] ]
                , div [ class "privacy-note" ]
                    [ strongText "Local-first history"
                    , p [] [ text "Clearing site data removes attempts unless exported." ]
                    , button [ class "text-button", type_ "button", onClick (ShowNotice "Export is represented in the UI; persistence arrives with the attempt-history milestone.") ] [ text "Export data →" ]
                    ]
                ]
            , section [ class "attempt-series" ]
                [ div [ class "series-heading" ]
                    [ div []
                        [ span [ class "series-reference" ] [ text "Anabasis 1.1.1" ]
                        , p [ class "series-greek" ] [ text "Δαρείου καὶ Παρυσάτιδος γίγνονται παῖδες δύο…" ]
                        ]
                    , span [ class "version-badge" ] [ text "Same content version" ]
                    ]
                , if model.attemptCount > 2 then
                    div []
                        [ viewAttemptCard (twoDigit model.attemptCount) "Today · 10:42" "Intensive" "Current checkpoint" "5 modules · no prior answer visible" True
                        , div [ class "attempt-link", attribute "aria-hidden" "true" ] [ text "│", span [] [ text "revision of" ], text "│" ]
                        ]

                  else
                    text ""
                , viewAttemptCard "02" "Sep 06 · 09:18" "Assisted" "Compared" "Gloss + prose · 1 reference reveal" False
                , div [ class "attempt-link", attribute "aria-hidden" "true" ] [ text "│", span [] [ text "earlier reading" ], text "│" ]
                , viewAttemptCard "01" "Aug 24 · 16:03" "Read" "Reread" "Greek only · 3m 12s" False
                , button [ class "compare-attempts-button", type_ "button", onClick ShowAttemptComparison ]
                    [ span [ attribute "aria-hidden" "true" ] [ text "⇄" ]
                    , span [] [ strongText ("Compare attempts " ++ twoDigit (max 1 (model.attemptCount - 1)) ++ " and " ++ twoDigit model.attemptCount), span [] [ text "Translations, morphology, assistance, and time" ] ]
                    , span [ attribute "aria-hidden" "true" ] [ text "→" ]
                    ]
                ]
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
    main_ [ class "page attempt-comparison-page" ]
        [ button [ class "back-link", type_ "button", onClick ShowHistory ] [ text "← Attempt history" ]
        , section [ class "comparison-intro" ]
            [ p [ class "eyebrow" ] [ text "Attempt comparison" ]
            , h1 [] [ text "What changed between readings?" ]
            , p [ class "lead" ] [ text "These are practice conditions and responses—not proof of Greek mastery." ]
            ]
        , div [ class "attempt-columns heading-columns" ]
            [ div [] [ span [ class "column-label" ] [ text "Earlier" ], h2 [] [ text ("Attempt " ++ twoDigit (max 1 (model.attemptCount - 1))) ], p [] [ text "Sep 06 · Assisted" ] ]
            , div [] [ span [ class "column-label current-label" ] [ text "Current" ], h2 [] [ text ("Attempt " ++ twoDigit model.attemptCount) ], p [] [ text "Today · Intensive" ] ]
            ]
        , section [ class "comparison-section" ]
            [ div [ class "comparison-section-heading" ]
                [ p [ class "eyebrow" ] [ text "Prose translation" ]
                , span [ class "neutral-badge" ] [ text "No automatic score" ]
                ]
            , div [ class "attempt-columns" ]
                [ blockquoteElement "Darius had sons, the older Artaxerxes and young Cyrus."
                , blockquoteElement model.draft.prose
                ]
            ]
        , section [ class "comparison-section" ]
            [ div [ class "comparison-section-heading" ]
                [ p [ class "eyebrow" ] [ text "Conditions" ]
                , span [ class "neutral-badge" ] [ text "Same pack + reference version" ]
                ]
            , div [ class "condition-table" ]
                [ conditionRow "Modules" "Gloss, prose" "Gloss, morphology, tree, literal, prose"
                , conditionRow "Reference before submit" "Yes · prose" (if model.referenceRevealed then "Yes · assisted" else "No · unassisted")
                , conditionRow "Active time" "7m 42s" (formatDuration model.elapsedSeconds)
                , conditionRow "Morphology" "Not prompted" "3 of 3 features"
                , conditionRow "Dependency" "Not prompted" "Root + core edge matched"
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
            "Express the proposition naturally, then judge it against an aligned reference."


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
