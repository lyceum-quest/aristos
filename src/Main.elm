module Main exposing (main)

import Browser
import Html exposing (Html, aside, button, div, footer, h1, h2, h3, header, main_, nav, p, section, span, text)
import Html.Attributes exposing (attribute, class, classList, disabled, id, tabindex, type_)
import Html.Events exposing (onClick)
import Time


type alias WorkId =
    String


type alias UnitId =
    String


type alias TokenId =
    String


type Screen
    = LibraryScreen
    | ContentsScreen WorkId
    | ReaderScreen WorkId UnitId
    | EvidenceScreen


type alias Work =
    { id : WorkId
    , title : String
    , author : String
    , label : String
    , description : String
    , progressLabel : String
    , availabilityLabel : String
    , actionLabel : String
    , divisions : List Division
    }


type alias Division =
    { title : String
    , progressLabel : String
    , units : List Unit
    }


type alias Unit =
    { id : UnitId
    , reference : String
    , context : String
    , tokens : List Token
    , translation : String
    , gistQuestion : String
    , gistOptions : List GistOption
    , focusPrompt : String
    , focusNote : String
    , progressLabel : String
    }


type alias GistOption =
    { label : String
    , correct : Bool
    }


type alias Token =
    { id : TokenId
    , form : String
    , lemma : String
    , morphology : String
    , gloss : String
    }


type LearningPhase
    = ColdRead
    | CheckMeaning
    | Review
    | Rereading


type HelpLevel
    = GlossHelp
    | LemmaHelp
    | MorphologyHelp


type alias SessionStats =
    { startedUnitIds : List UnitId
    , completedUnitIds : List UnitId
    , readingSeconds : Int
    , completedWords : Int
    , gistAttempts : Int
    , gistCorrect : Int
    , unassistedGistAttempts : Int
    , unassistedGistCorrect : Int
    , glossReveals : Int
    , lemmaReveals : Int
    , morphologyReveals : Int
    , translationReveals : Int
    , rereads : Int
    }


type alias Model =
    { screen : Screen
    , phase : LearningPhase
    , selectedToken : Maybe ( TokenId, HelpLevel )
    , translationOpen : Bool
    , focusOpen : Bool
    , menuOpen : Bool
    , gistResult : Maybe Bool
    , unitHadHelp : Bool
    , elapsedSeconds : Int
    , stats : SessionStats
    }


type Msg
    = ShowLibrary
    | ShowEvidence
    | ShowContents WorkId
    | ShowReader WorkId UnitId
    | BeginMeaningCheck
    | AnswerGist Bool
    | SelectToken TokenId
    | RevealLemma
    | RevealMorphology
    | CloseTokenHelp
    | ToggleTranslation
    | ToggleFocus
    | RereadGreek
    | FinishAndNext
    | ToggleMenu
    | PreviousFixtureUnit
    | NextFixtureUnit
    | Tick Time.Posix


main : Program () Model Msg
main =
    Browser.element
        { init = \_ -> ( init, Cmd.none )
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


init : Model
init =
    { screen = LibraryScreen
    , phase = ColdRead
    , selectedToken = Nothing
    , translationOpen = False
    , focusOpen = False
    , menuOpen = False
    , gistResult = Nothing
    , unitHadHelp = False
    , elapsedSeconds = 0
    , stats = emptyStats
    }


emptyStats : SessionStats
emptyStats =
    { startedUnitIds = []
    , completedUnitIds = []
    , readingSeconds = 0
    , completedWords = 0
    , gistAttempts = 0
    , gistCorrect = 0
    , unassistedGistAttempts = 0
    , unassistedGistCorrect = 0
    , glossReveals = 0
    , lemmaReveals = 0
    , morphologyReveals = 0
    , translationReveals = 0
    , rereads = 0
    }


subscriptions : Model -> Sub Msg
subscriptions model =
    case model.screen of
        ReaderScreen _ _ ->
            Time.every 1000 Tick

        _ ->
            Sub.none


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    ( case msg of
        ShowLibrary ->
            resetPanels { model | screen = LibraryScreen }

        ShowEvidence ->
            resetPanels { model | screen = EvidenceScreen }

        ShowContents workId ->
            resetPanels { model | screen = ContentsScreen workId }

        ShowReader workId unitId ->
            openUnit workId unitId model

        BeginMeaningCheck ->
            { model | phase = CheckMeaning, selectedToken = Nothing, translationOpen = False }

        AnswerGist correct ->
            recordGistAnswer correct model

        SelectToken tokenId ->
            if model.phase == Rereading then
                model

            else
                { model
                    | selectedToken = Just ( tokenId, GlossHelp )
                    , menuOpen = False
                    , unitHadHelp = True
                    , stats = incrementGloss model.stats
                }

        RevealLemma ->
            case model.selectedToken of
                Just ( tokenId, GlossHelp ) ->
                    { model
                        | selectedToken = Just ( tokenId, LemmaHelp )
                        , stats = incrementLemma model.stats
                    }

                _ ->
                    model

        RevealMorphology ->
            case model.selectedToken of
                Just ( tokenId, LemmaHelp ) ->
                    { model
                        | selectedToken = Just ( tokenId, MorphologyHelp )
                        , stats = incrementMorphology model.stats
                    }

                _ ->
                    model

        CloseTokenHelp ->
            { model | selectedToken = Nothing }

        ToggleTranslation ->
            if model.phase /= Review then
                model

            else if model.translationOpen then
                { model | translationOpen = False }

            else
                { model
                    | translationOpen = True
                    , selectedToken = Nothing
                    , unitHadHelp = True
                    , stats = incrementTranslation model.stats
                }

        ToggleFocus ->
            { model | focusOpen = not model.focusOpen }

        RereadGreek ->
            beginReread model

        FinishAndNext ->
            finishCurrentUnit model

        ToggleMenu ->
            { model | menuOpen = not model.menuOpen, selectedToken = Nothing }

        PreviousFixtureUnit ->
            moveUnit -1 model

        NextFixtureUnit ->
            moveUnit 1 model

        Tick _ ->
            { model | elapsedSeconds = model.elapsedSeconds + 1 }
    , Cmd.none
    )


resetPanels : Model -> Model
resetPanels model =
    { model
        | selectedToken = Nothing
        , translationOpen = False
        , focusOpen = False
        , menuOpen = False
    }


openUnit : WorkId -> UnitId -> Model -> Model
openUnit workId unitId model =
    let
        started =
            addUnique unitId model.stats.startedUnitIds

        stats =
            model.stats
    in
    { model
        | screen = ReaderScreen workId unitId
        , phase = ColdRead
        , selectedToken = Nothing
        , translationOpen = False
        , focusOpen = False
        , menuOpen = False
        , gistResult = Nothing
        , unitHadHelp = False
        , elapsedSeconds = 0
        , stats = { stats | startedUnitIds = started }
    }


recordGistAnswer : Bool -> Model -> Model
recordGistAnswer correct model =
    if model.phase /= CheckMeaning || model.gistResult /= Nothing then
        model

    else
        let
            stats =
                model.stats

            updated =
                { stats
                    | gistAttempts = stats.gistAttempts + 1
                    , gistCorrect = stats.gistCorrect + boolInt correct
                    , unassistedGistAttempts = stats.unassistedGistAttempts + boolInt (not model.unitHadHelp)
                    , unassistedGistCorrect = stats.unassistedGistCorrect + boolInt (correct && not model.unitHadHelp)
                }
        in
        { model | phase = Review, gistResult = Just correct, stats = updated }


beginReread : Model -> Model
beginReread model =
    if model.phase == Review then
        let
            stats =
                model.stats
        in
        { model
            | phase = Rereading
            , selectedToken = Nothing
            , translationOpen = False
            , focusOpen = False
            , stats = { stats | rereads = stats.rereads + 1 }
        }

    else
        model


finishCurrentUnit : Model -> Model
finishCurrentUnit model =
    case model.screen of
        ReaderScreen workId unitId ->
            case findUnit workId unitId of
                Just unit ->
                    let
                        alreadyCompleted =
                            List.member unitId model.stats.completedUnitIds

                        stats =
                            model.stats

                        completedStats =
                            if alreadyCompleted then
                                stats

                            else
                                { stats
                                    | completedUnitIds = unitId :: stats.completedUnitIds
                                    , readingSeconds = stats.readingSeconds + model.elapsedSeconds
                                    , completedWords = stats.completedWords + List.length unit.tokens
                                }

                        completedModel =
                            { model | stats = completedStats }
                    in
                    if model.phase /= Rereading then
                        model

                    else
                        case adjacentUnit 1 workId unitId of
                            Just nextUnit ->
                                openUnit workId nextUnit.id completedModel

                            Nothing ->
                                resetPanels { completedModel | screen = ContentsScreen workId }

                Nothing ->
                    model

        _ ->
            model


moveUnit : Int -> Model -> Model
moveUnit offset model =
    case model.screen of
        ReaderScreen workId unitId ->
            case adjacentUnit offset workId unitId of
                Just unit ->
                    openUnit workId unit.id model

                Nothing ->
                    model

        _ ->
            model


adjacentUnit : Int -> WorkId -> UnitId -> Maybe Unit
adjacentUnit offset workId unitId =
    findWork workId
        |> Maybe.andThen
            (\work ->
                let
                    units =
                        workUnits work
                in
                findIndex (\unit -> unit.id == unitId) units
                    |> Maybe.andThen (\index -> getAt (index + offset) units)
            )


incrementGloss : SessionStats -> SessionStats
incrementGloss stats =
    { stats | glossReveals = stats.glossReveals + 1 }


incrementLemma : SessionStats -> SessionStats
incrementLemma stats =
    { stats | lemmaReveals = stats.lemmaReveals + 1 }


incrementMorphology : SessionStats -> SessionStats
incrementMorphology stats =
    { stats | morphologyReveals = stats.morphologyReveals + 1 }


incrementTranslation : SessionStats -> SessionStats
incrementTranslation stats =
    { stats | translationReveals = stats.translationReveals + 1 }


addUnique : comparable -> List comparable -> List comparable
addUnique item items =
    if List.member item items then
        items

    else
        item :: items


boolInt : Bool -> Int
boolInt value =
    if value then
        1

    else
        0


view : Model -> Html Msg
view model =
    div [ class "app-shell" ]
        [ case model.screen of
            LibraryScreen ->
                viewLibrary model

            ContentsScreen workId ->
                viewContents workId

            ReaderScreen workId unitId ->
                viewReader model workId unitId

            EvidenceScreen ->
                viewEvidence model
        ]


viewLibrary : Model -> Html Msg
viewLibrary model =
    div []
        [ header [ class "site-header" ]
            [ div [ class "brand" ]
                [ span [ class "brand-mark", attribute "aria-hidden" "true" ] [ text "Α" ]
                , span [] [ text "Aristos" ]
                ]
            , button [ class "quiet-button evidence-link", type_ "button", onClick ShowEvidence ] [ text "Session evidence" ]
            ]
        , main_ [ class "page library-page" ]
            [ section [ class "intro" ]
                [ p [ class "eyebrow" ] [ text "Your Greek library" ]
                , h1 [] [ text "Read, check, reread." ]
                , p [ class "intro-copy" ] [ text "Build understanding through connected Greek, selective help, immediate feedback, and a fluent second pass." ]
                ]
            , viewSessionPulse model.stats
            , div [ class "work-grid" ] (List.map viewWorkCard works)
            ]
        ]


viewSessionPulse : SessionStats -> Html Msg
viewSessionPulse stats =
    button [ class "session-pulse", type_ "button", onClick ShowEvidence ]
        [ span [ class "pulse-mark", attribute "aria-hidden" "true" ] [ text "↗" ]
        , span [ class "pulse-copy" ]
            [ span [ class "pulse-title" ] [ text "This session" ]
            , span []
                [ text
                    (String.fromInt (List.length stats.completedUnitIds)
                        ++ " units completed · "
                        ++ accuracyLabel stats.gistCorrect stats.gistAttempts
                        ++ " gist accuracy"
                    )
                ]
            ]
        , span [ class "unit-arrow", attribute "aria-hidden" "true" ] [ text "View →" ]
        ]


viewWorkCard : Work -> Html Msg
viewWorkCard work =
    section [ class "work-card" ]
        [ div [ class "work-card-top" ]
            [ div []
                [ p [ class "work-label" ] [ text work.label ]
                , h2 [ class "work-title" ] [ text work.title ]
                , p [ class "work-author" ] [ text work.author ]
                ]
            , span [ class "status-pill" ] [ text work.availabilityLabel ]
            ]
        , p [ class "work-description" ] [ text work.description ]
        , div [ class "progress-track", attribute "aria-hidden" "true" ]
            [ span [ class ("progress-fill progress-" ++ work.id) ] [] ]
        , div [ class "work-card-footer" ]
            [ span [ class "progress-label" ] [ text work.progressLabel ]
            , button [ class "primary-button", type_ "button", onClick (ShowContents work.id) ] [ text work.actionLabel ]
            ]
        ]


viewContents : WorkId -> Html Msg
viewContents workId =
    case findWork workId of
        Nothing ->
            viewNotFound

        Just work ->
            div []
                [ header [ class "site-header" ]
                    [ button [ class "back-button", type_ "button", onClick ShowLibrary ] [ text "← Library" ]
                    , span [ class "header-title" ] [ text "Contents" ]
                    , span [ class "header-spacer" ] []
                    ]
                , main_ [ class "page contents-page" ]
                    [ section [ class "contents-heading" ]
                        [ p [ class "work-label" ] [ text work.label ]
                        , h1 [] [ text work.title ]
                        , p [ class "work-author" ] [ text work.author ]
                        ]
                    , div [ class "division-list" ] (List.indexedMap (viewDivision work.id) work.divisions)
                    ]
                ]


viewDivision : WorkId -> Int -> Division -> Html Msg
viewDivision workId divisionIndex division =
    section [ class "division" ]
        [ div [ class "division-heading" ]
            [ div []
                [ p [ class "division-kicker" ] [ text ("Division " ++ String.fromInt (divisionIndex + 1)) ]
                , h2 [] [ text division.title ]
                ]
            , span [ class "progress-label" ] [ text division.progressLabel ]
            ]
        , div [ class "unit-list" ] (List.indexedMap (viewUnitRow workId) division.units)
        ]


viewUnitRow : WorkId -> Int -> Unit -> Html Msg
viewUnitRow workId index unit =
    button [ class "unit-row", type_ "button", onClick (ShowReader workId unit.id) ]
        [ span [ class "unit-number" ] [ text (String.fromInt (index + 1)) ]
        , span [ class "unit-details" ]
            [ span [ class "unit-reference" ] [ text unit.reference ]
            , span [ class "unit-sample" ] [ text (unitPreview unit) ]
            ]
        , span [ class "unit-progress" ] [ text unit.progressLabel ]
        , span [ class "unit-arrow", attribute "aria-hidden" "true" ] [ text "→" ]
        ]


viewReader : Model -> WorkId -> UnitId -> Html Msg
viewReader model workId unitId =
    case ( findWork workId, findUnit workId unitId ) of
        ( Just work, Just unit ) ->
            let
                units =
                    workUnits work

                currentIndex =
                    Maybe.withDefault 0 (findIndex (\candidate -> candidate.id == unit.id) units)

                previousDisabled =
                    currentIndex == 0

                nextDisabled =
                    currentIndex >= List.length units - 1
            in
            div [ class "reader-layout" ]
                [ header [ class "reader-header" ]
                    [ button [ class "back-button", type_ "button", onClick (ShowContents workId) ] [ text "← Contents" ]
                    , div [ class "reader-heading" ]
                        [ span [ class "reader-work" ] [ text work.title ]
                        , span [ class "reader-reference" ] [ text unit.reference ]
                        ]
                    , button
                        [ class "menu-button"
                        , type_ "button"
                        , onClick ToggleMenu
                        , attribute "aria-expanded" (boolString model.menuOpen)
                        , attribute "aria-label" "Reader menu"
                        ]
                        [ text "•••" ]
                    ]
                , if model.menuOpen then
                    viewReaderMenu

                  else
                    text ""
                , main_ [ class "reader-main" ]
                    [ viewLearningPath model.phase
                    , div [ class "reader-meta" ]
                        [ span [] [ text "Demo text · Homer, Iliad 1.1–7" ]
                        , span [] [ text (formatDuration model.elapsedSeconds ++ " · " ++ unit.progressLabel) ]
                        ]
                    , viewOrientation model.phase unit
                    , section
                        [ classList
                            [ ( "passage", True )
                            , ( "reread-passage", model.phase == Rereading )
                            ]
                        , attribute "aria-label" "Greek passage"
                        ]
                        (List.map (viewToken model.phase model.selectedToken) unit.tokens)
                    , p [ class "sample-note" ] [ text "Original Homeric Greek is reused as sample copy throughout this UI prototype." ]
                    , viewPhasePanel model unit
                    ]
                , case selectedTokenInUnit model.selectedToken unit of
                    Just ( token, level ) ->
                        viewTokenHelp token level

                    Nothing ->
                        text ""
                , footer [ class "reader-actions" ]
                    [ button
                        [ class "action-button previous-action"
                        , type_ "button"
                        , disabled previousDisabled
                        , onClick PreviousFixtureUnit
                        ]
                        [ span [ attribute "aria-hidden" "true" ] [ text "←" ]
                        , span [] [ text "Previous" ]
                        ]
                    , viewPrimaryLearningAction model.phase
                    , button
                        [ class "action-button skip-action"
                        , type_ "button"
                        , disabled nextDisabled
                        , onClick NextFixtureUnit
                        , attribute "aria-label" "Skip to next fixture unit"
                        ]
                        [ span [] [ text "Skip" ]
                        , span [ attribute "aria-hidden" "true" ] [ text "→" ]
                        ]
                    ]
                ]

        _ ->
            viewNotFound


viewLearningPath : LearningPhase -> Html Msg
viewLearningPath phase =
    nav [ class "learning-path", attribute "aria-label" "Learning steps" ]
        [ viewLearningStep 1 "Read" (phaseRank phase) 1
        , viewLearningStep 2 "Check" (phaseRank phase) 2
        , viewLearningStep 3 "Review" (phaseRank phase) 3
        , viewLearningStep 4 "Reread" (phaseRank phase) 4
        ]


viewLearningStep : Int -> String -> Int -> Int -> Html Msg
viewLearningStep number label current rank =
    div
        [ classList
            [ ( "learning-step", True )
            , ( "is-current", current == rank )
            , ( "is-complete", current > rank )
            ]
        ]
        [ span [ class "step-number" ]
            [ text
                (if current > rank then
                    "✓"

                 else
                    String.fromInt number
                )
            ]
        , span [] [ text label ]
        ]


phaseRank : LearningPhase -> Int
phaseRank phase =
    case phase of
        ColdRead ->
            1

        CheckMeaning ->
            2

        Review ->
            3

        Rereading ->
            4


viewOrientation : LearningPhase -> Unit -> Html Msg
viewOrientation phase unit =
    if phase == Rereading then
        div [ class "reread-callout" ]
            [ p [ class "eyebrow" ] [ text "Fluent pass" ]
            , p [] [ text "Read straight through for meaning. Word help is closed for this pass." ]
            ]

    else
        section [ class "orientation-card" ]
            [ p [ class "eyebrow" ] [ text "Before you read" ]
            , p [] [ text unit.context ]
            , p [ class "reading-cue" ] [ text "Aim for the main event: who does what, and with what result? Tap a word only if it blocks that meaning." ]
            ]


viewPhasePanel : Model -> Unit -> Html Msg
viewPhasePanel model unit =
    case model.phase of
        ColdRead ->
            div [ class "phase-note" ]
                [ p [ class "eyebrow" ] [ text "1 · Read" ]
                , h2 [] [ text "Form a rough understanding first." ]
                , p [] [ text "You do not need to parse or translate every word. Continue when you can state the passage’s main event." ]
                ]

        CheckMeaning ->
            viewGistQuestion unit

        Review ->
            viewReview model unit

        Rereading ->
            div [ class "phase-note reread-note" ]
                [ p [ class "eyebrow" ] [ text "4 · Reread" ]
                , h2 [] [ text "Let the Greek carry the meaning." ]
                , p [] [ text "When the passage reads as a connected thought, finish the unit. Completion means reread—not mastered." ]
                ]


viewGistQuestion : Unit -> Html Msg
viewGistQuestion unit =
    section [ class "gist-panel", attribute "aria-labelledby" "gist-title" ]
        [ p [ class "eyebrow" ] [ text "2 · Check meaning" ]
        , h2 [ id "gist-title" ] [ text unit.gistQuestion ]
        , p [ class "panel-instruction" ] [ text "Choose the best account of the passage before checking a translation." ]
        , div [ class "gist-options" ] (List.map viewGistOption unit.gistOptions)
        ]


viewGistOption : GistOption -> Html Msg
viewGistOption option =
    button [ class "gist-option", type_ "button", onClick (AnswerGist option.correct) ]
        [ span [ class "option-mark", attribute "aria-hidden" "true" ] []
        , span [] [ text option.label ]
        ]


viewReview : Model -> Unit -> Html Msg
viewReview model unit =
    div [ class "review-stack" ]
        [ section
            [ classList
                [ ( "gist-feedback", True )
                , ( "is-correct", model.gistResult == Just True )
                ]
            ]
            [ p [ class "eyebrow" ] [ text "3 · Review" ]
            , h2 []
                [ text
                    (if model.gistResult == Just True then
                        "Yes—that is the main event."

                     else
                        "Not quite. Use the feedback, then look again."
                    )
                ]
            , p [] [ text ("Best answer: " ++ correctGistLabel unit) ]
            ]
        , section [ class "review-tools" ]
            [ div [ class "review-tool" ]
                [ p [ class "eyebrow" ] [ text "Check the whole" ]
                , h3 [] [ text "Compare with a translation" ]
                , p [] [ text "Use this as feedback, not as the text to memorize." ]
                , button [ class "secondary-button", type_ "button", onClick ToggleTranslation ]
                    [ text
                        (if model.translationOpen then
                            "Hide translation"

                         else
                            "Reveal translation"
                        )
                    ]
                ]
            , div [ class "review-tool" ]
                [ p [ class "eyebrow" ] [ text "Focus on one form" ]
                , h3 [] [ text unit.focusPrompt ]
                , p [] [ text "Inspect one useful signal rather than parsing every token." ]
                , button [ class "secondary-button", type_ "button", onClick ToggleFocus ]
                    [ text
                        (if model.focusOpen then
                            "Hide note"

                         else
                            "Show note"
                        )
                    ]
                , if model.focusOpen then
                    p [ class "focus-answer" ] [ text unit.focusNote ]

                  else
                    text ""
                ]
            ]
        , if model.translationOpen then
            viewTranslation unit

          else
            text ""
        , section [ class "active-prompt" ]
            [ p [ class "eyebrow" ] [ text "Active recall" ]
            , h3 [] [ text "Look away and restate the event in one short phrase." ]
            , p [] [ text "Then begin the clean reread. No written response is stored in this prototype." ]
            ]
        ]


viewPrimaryLearningAction : LearningPhase -> Html Msg
viewPrimaryLearningAction phase =
    case phase of
        ColdRead ->
            button [ class "action-button primary-learning-action", type_ "button", onClick BeginMeaningCheck ] [ text "Check understanding" ]

        CheckMeaning ->
            button [ class "action-button primary-learning-action", type_ "button", disabled True ] [ text "Choose an answer" ]

        Review ->
            button [ class "action-button primary-learning-action", type_ "button", onClick RereadGreek ] [ text "Reread Greek" ]

        Rereading ->
            button [ class "action-button primary-learning-action finish-action", type_ "button", onClick FinishAndNext ] [ text "Finish & next" ]


viewToken : LearningPhase -> Maybe ( TokenId, HelpLevel ) -> Token -> Html Msg
viewToken phase selectedToken token =
    let
        selected =
            case selectedToken of
                Just ( tokenId, _ ) ->
                    tokenId == token.id

                Nothing ->
                    False
    in
    button
        [ classList
            [ ( "greek-token", True )
            , ( "is-selected", selected )
            ]
        , type_ "button"
        , disabled (phase == Rereading)
        , onClick (SelectToken token.id)
        , attribute "aria-pressed" (boolString selected)
        ]
        [ text token.form ]


viewTranslation : Unit -> Html Msg
viewTranslation unit =
    section [ class "translation-panel", attribute "aria-label" "Translation" ]
        [ div [ class "panel-heading" ]
            [ div []
                [ p [ class "eyebrow" ] [ text "Translation feedback" ]
                , h2 [] [ text "Compare propositions, not wording." ]
                ]
            , button [ class "quiet-button", type_ "button", onClick ToggleTranslation, attribute "aria-label" "Close translation" ] [ text "×" ]
            ]
        , p [] [ text unit.translation ]
        ]


viewTokenHelp : Token -> HelpLevel -> Html Msg
viewTokenHelp token level =
    aside
        [ class "token-sheet"
        , attribute "role" "dialog"
        , attribute "aria-labelledby" "token-sheet-title"
        ]
        [ div [ class "sheet-handle", attribute "aria-hidden" "true" ] []
        , div [ class "panel-heading" ]
            [ div []
                [ p [ class "eyebrow" ] [ text "Progressive word help" ]
                , h2 [ id "token-sheet-title", class "sheet-token" ] [ text token.form ]
                ]
            , button [ class "quiet-button close-button", type_ "button", onClick CloseTokenHelp, attribute "aria-label" "Close word help" ] [ text "×" ]
            ]
        , div [ class "help-level" ]
            [ span [ class "help-label" ] [ text "1 · Contextual gloss" ]
            , p [ class "help-primary" ] [ text token.gloss ]
            ]
        , if helpRank level >= 2 then
            div [ class "help-level" ]
                [ span [ class "help-label" ] [ text "2 · Lemma" ]
                , p [] [ text token.lemma ]
                ]

          else
            button [ class "help-reveal", type_ "button", onClick RevealLemma ] [ text "Still blocked? Show lemma" ]
        , if helpRank level >= 3 then
            div [ class "help-level" ]
                [ span [ class "help-label" ] [ text "3 · Morphology" ]
                , p [] [ text token.morphology ]
                ]

          else if helpRank level >= 2 then
            button [ class "help-reveal", type_ "button", onClick RevealMorphology ] [ text "Need the form? Show morphology" ]

          else
            text ""
        ]


helpRank : HelpLevel -> Int
helpRank level =
    case level of
        GlossHelp ->
            1

        LemmaHelp ->
            2

        MorphologyHelp ->
            3


viewReaderMenu : Html Msg
viewReaderMenu =
    nav [ class "reader-menu", attribute "aria-label" "Reader settings" ]
        [ p [ class "eyebrow" ] [ text "Reading display" ]
        , div [ class "menu-row" ]
            [ span [] [ text "Greek size" ]
            , div [ class "size-controls", attribute "aria-label" "Greek font size" ]
                [ button [ type_ "button", tabindex 0 ] [ text "A−" ]
                , button [ type_ "button", class "is-active", tabindex 0 ] [ text "A" ]
                , button [ type_ "button", tabindex 0 ] [ text "A+" ]
                ]
            ]
        , div [ class "menu-row" ]
            [ span [] [ text "Theme" ]
            , span [ class "menu-value" ] [ text "System" ]
            ]
        , button [ class "menu-evidence-link", type_ "button", onClick ShowEvidence ] [ text "View session evidence →" ]
        ]


viewEvidence : Model -> Html Msg
viewEvidence model =
    let
        stats =
            model.stats

        helpTotal =
            stats.glossReveals + stats.lemmaReveals + stats.morphologyReveals + stats.translationReveals
    in
    div []
        [ header [ class "site-header" ]
            [ button [ class "back-button", type_ "button", onClick ShowLibrary ] [ text "← Library" ]
            , span [ class "header-title" ] [ text "Session evidence" ]
            , span [ class "header-spacer" ] []
            ]
        , main_ [ class "page evidence-page" ]
            [ section [ class "evidence-heading" ]
                [ p [ class "eyebrow" ] [ text "Prototype validation" ]
                , h1 [] [ text "Are we practicing the right behavior?" ]
                , p [] [ text "These in-memory signals describe this browser session. They do not establish vocabulary retention, transfer, or mastery." ]
                ]
            , section [ class "metric-grid", attribute "aria-label" "Session measurements" ]
                [ viewMetric "Units opened" (String.fromInt (List.length stats.startedUnitIds)) "Distinct fixture units"
                , viewMetric "Units reread" (String.fromInt (List.length stats.completedUnitIds)) "Finished after a clean pass"
                , viewMetric "Gist accuracy" (accuracyLabel stats.gistCorrect stats.gistAttempts) (fractionLabel stats.gistCorrect stats.gistAttempts)
                , viewMetric "Before help" (accuracyLabel stats.unassistedGistCorrect stats.unassistedGistAttempts) "Unassisted gist accuracy"
                , viewMetric "Reader time" (formatDuration stats.readingSeconds) "Completed units only"
                , viewMetric "Reading pace" (wordsPerMinuteLabel stats) (String.fromInt stats.completedWords ++ " completed words")
                ]
            , section [ class "evidence-section" ]
                [ div [ class "section-heading" ]
                    [ div []
                        [ p [ class "eyebrow" ] [ text "Assistance profile" ]
                        , h2 [] [ text (String.fromInt helpTotal ++ " help reveals") ]
                        ]
                    , span [ class "status-pill" ] [ text (String.fromInt stats.rereads ++ " rereads") ]
                    ]
                , div [ class "assistance-grid" ]
                    [ viewAssistance "Gloss" stats.glossReveals
                    , viewAssistance "Lemma" stats.lemmaReveals
                    , viewAssistance "Morphology" stats.morphologyReveals
                    , viewAssistance "Translation" stats.translationReveals
                    ]
                , p [ class "evidence-caption" ] [ text "A useful trend would be stable or improving gist accuracy with fewer high-level hints on comparable unseen passages." ]
                ]
            , section [ class "evidence-limit" ]
                [ p [ class "eyebrow" ] [ text "Missing proof" ]
                , h2 [] [ text "This is behavior, not yet learning." ]
                , p [] [ text "A real validation should add delayed tests on unseen Greek, passage difficulty controls, active-time detection, and repeated measurements across sessions." ]
                ]
            , p [ class "reset-note" ] [ text "Refresh the browser to reset this prototype session." ]
            ]
        ]


viewMetric : String -> String -> String -> Html Msg
viewMetric label value note =
    div [ class "metric-card" ]
        [ span [ class "metric-label" ] [ text label ]
        , span [ class "metric-value" ] [ text value ]
        , span [ class "metric-note" ] [ text note ]
        ]


viewAssistance : String -> Int -> Html Msg
viewAssistance label count =
    div [ class "assistance-item" ]
        [ span [] [ text label ]
        , span [ class "assistance-count" ] [ text (String.fromInt count) ]
        ]


viewNotFound : Html Msg
viewNotFound =
    main_ [ class "page empty-state" ]
        [ h1 [] [ text "This fixture is missing." ]
        , button [ class "primary-button", type_ "button", onClick ShowLibrary ] [ text "Return to library" ]
        ]


selectedTokenInUnit : Maybe ( TokenId, HelpLevel ) -> Unit -> Maybe ( Token, HelpLevel )
selectedTokenInUnit selectedToken unit =
    case selectedToken of
        Just ( tokenId, level ) ->
            List.filter (\token -> token.id == tokenId) unit.tokens
                |> List.head
                |> Maybe.map (\token -> ( token, level ))

        Nothing ->
            Nothing


findWork : WorkId -> Maybe Work
findWork workId =
    List.filter (\work -> work.id == workId) works |> List.head


findUnit : WorkId -> UnitId -> Maybe Unit
findUnit workId unitId =
    findWork workId
        |> Maybe.andThen
            (\work ->
                workUnits work
                    |> List.filter (\unit -> unit.id == unitId)
                    |> List.head
            )


workUnits : Work -> List Unit
workUnits work =
    List.concatMap .units work.divisions


findIndex : (a -> Bool) -> List a -> Maybe Int
findIndex predicate items =
    items
        |> List.indexedMap Tuple.pair
        |> List.filter (\( _, item ) -> predicate item)
        |> List.head
        |> Maybe.map Tuple.first


getAt : Int -> List a -> Maybe a
getAt index items =
    if index < 0 then
        Nothing

    else
        items |> List.drop index |> List.head


correctGistLabel : Unit -> String
correctGistLabel unit =
    unit.gistOptions
        |> List.filter .correct
        |> List.head
        |> Maybe.map .label
        |> Maybe.withDefault "No fixture answer"


accuracyLabel : Int -> Int -> String
accuracyLabel correct attempts =
    if attempts == 0 then
        "—"

    else
        String.fromInt ((correct * 100) // attempts) ++ "%"


fractionLabel : Int -> Int -> String
fractionLabel correct attempts =
    if attempts == 0 then
        "No answers yet"

    else
        String.fromInt correct ++ " of " ++ String.fromInt attempts ++ " correct"


formatDuration : Int -> String
formatDuration seconds =
    let
        minutes =
            seconds // 60

        remainder =
            modBy 60 seconds
    in
    if minutes == 0 then
        String.fromInt remainder ++ "s"

    else
        String.fromInt minutes ++ "m " ++ String.fromInt remainder ++ "s"


wordsPerMinuteLabel : SessionStats -> String
wordsPerMinuteLabel stats =
    if stats.readingSeconds == 0 then
        "—"

    else
        String.fromInt ((stats.completedWords * 60) // stats.readingSeconds) ++ " wpm"


unitPreview : Unit -> String
unitPreview unit =
    unit.tokens
        |> List.take 6
        |> List.map .form
        |> String.join " "


boolString : Bool -> String
boolString value =
    if value then
        "true"

    else
        "false"


works : List Work
works =
    [ { id = "mark"
      , title = "Gospel of Mark"
      , author = "Κατὰ Μᾶρκον"
      , label = "Koine · Narrative"
      , description = "A direct, fast-moving introduction to connected Greek prose."
      , progressLabel = "8 of 42 units · 1,140 words"
      , availabilityLabel = "On device · 1.8 MB"
      , actionLabel = "Resume"
      , divisions =
            [ { title = "Κεφάλαιον Αʹ"
              , progressLabel = "3 of 6 read"
              , units = sampleUnits "mark-a"
              }
            , { title = "Κεφάλαιον Βʹ"
              , progressLabel = "Not started"
              , units = sampleUnits "mark-b"
              }
            ]
      }
    , { id = "cyropaedia"
      , title = "Cyropaedia · Book 1"
      , author = "Ξενοφῶν"
      , label = "Classical Attic · Prose"
      , description = "Measured historical prose with clear narrative structure."
      , progressLabel = "Not started · 14,021 words"
      , availabilityLabel = "3.2 MB"
      , actionLabel = "Download"
      , divisions =
            [ { title = "Βιβλίον Αʹ · Τμῆμα Αʹ"
              , progressLabel = "Not started"
              , units = sampleUnits "cyr-a"
              }
            , { title = "Βιβλίον Αʹ · Τμῆμα Βʹ"
              , progressLabel = "Not started"
              , units = sampleUnits "cyr-b"
              }
            ]
      }
    , { id = "genesis"
      , title = "Septuagint Genesis"
      , author = "Γένεσις"
      , label = "Koine · Sacred narrative"
      , description = "A substantial reading path with compact scenes and familiar stories."
      , progressLabel = "24 of 146 units · 5,870 words"
      , availabilityLabel = "On device · 5.6 MB"
      , actionLabel = "Resume"
      , divisions =
            [ { title = "Κεφάλαιον Αʹ"
              , progressLabel = "Complete"
              , units = sampleUnits "gen-a"
              }
            , { title = "Κεφάλαιον Βʹ"
              , progressLabel = "1 of 4 read"
              , units = sampleUnits "gen-b"
              }
            ]
      }
    ]


sampleUnits : String -> List Unit
sampleUnits prefix =
    [ { id = prefix ++ "-1"
      , reference = "Ἰλιάς 1.1–2"
      , context = "The poet opens by asking a goddess to sing about the force that drives the epic’s suffering."
      , tokens = unitOneTokens (prefix ++ "-1")
      , translation = "Sing, goddess, of the destructive anger of Achilles, which brought countless sorrows upon the Achaeans. Demo translation for layout only."
      , gistQuestion = "What does the poet ask the goddess to sing about?"
      , gistOptions =
            [ { label = "Achilles’ destructive anger and the suffering it caused", correct = True }
            , { label = "The Achaeans’ joyful return from Troy", correct = False }
            , { label = "Zeus teaching Achilles how to fight", correct = False }
            ]
      , focusPrompt = "What role does Μῆνιν play at the opening?"
      , focusNote = "Its accusative form marks the theme or object of ἄειδε: ‘sing wrath.’ The delayed verb makes the opening noun especially prominent."
      , progressLabel = "1 of 3"
      }
    , { id = prefix ++ "-2"
      , reference = "Ἰλιάς 1.3–5"
      , context = "The invocation expands from anger to its consequences for heroes and their bodies."
      , tokens = unitTwoTokens (prefix ++ "-2")
      , translation = "It sent many mighty souls of heroes to Hades and made their bodies prey for dogs and birds. Demo translation for layout only."
      , gistQuestion = "What consequences of the anger are emphasized?"
      , gistOptions =
            [ { label = "Heroes died, and their bodies were left as prey", correct = True }
            , { label = "The gods immediately ended the war", correct = False }
            , { label = "Achilles rescued the Achaean army", correct = False }
            ]
      , focusPrompt = "How do ψυχὰς and αὐτοὺς contrast?"
      , focusNote = "The poem separates the heroes’ souls, sent to Hades, from ‘themselves’—their bodies—left as prey."
      , progressLabel = "2 of 3"
      }
    , { id = prefix ++ "-3"
      , reference = "Ἰλιάς 1.6–7"
      , context = "The poet now identifies the quarrel from which the poem’s central conflict began."
      , tokens = unitThreeTokens (prefix ++ "-3")
      , translation = "From the first moment when the son of Atreus and brilliant Achilles divided in strife. Demo translation for layout only."
      , gistQuestion = "Which event marks the beginning of the conflict?"
      , gistOptions =
            [ { label = "Agamemnon and Achilles separated after quarrelling", correct = True }
            , { label = "Achilles first arrived at Troy", correct = False }
            , { label = "Zeus announced peace among the Greeks", correct = False }
            ]
      , focusPrompt = "Why is διαστήτην singular-looking but about two people?"
      , focusNote = "It is a third-person dual form: the pair—the son of Atreus and Achilles—stood apart."
      , progressLabel = "3 of 3"
      }
    ]


unitOneTokens : String -> List Token
unitOneTokens prefix =
    tokenList prefix
        [ ( "Μῆνιν", ( "μῆνις", "accusative singular feminine", "wrath" ) )
        , ( "ἄειδε,", ( "ἀείδω", "present active imperative, 2nd singular", "sing" ) )
        , ( "θεά,", ( "θεά", "vocative singular feminine", "goddess" ) )
        , ( "Πηληϊάδεω", ( "Πηληϊάδης", "genitive singular masculine", "son of Peleus" ) )
        , ( "Ἀχιλῆος", ( "Ἀχιλλεύς", "genitive singular masculine", "Achilles" ) )
        , ( "οὐλομένην,", ( "ὄλλυμι", "aorist middle participle, accusative singular feminine", "destructive" ) )
        , ( "ἣ", ( "ὅς", "nominative singular feminine", "which" ) )
        , ( "μυρί᾽", ( "μυρίος", "accusative plural neuter", "countless" ) )
        , ( "Ἀχαιοῖς", ( "Ἀχαιός", "dative plural masculine", "for the Achaeans" ) )
        , ( "ἄλγε᾽", ( "ἄλγος", "accusative plural neuter", "sorrows" ) )
        , ( "ἔθηκε,", ( "τίθημι", "aorist active indicative, 3rd singular", "caused" ) )
        ]


unitTwoTokens : String -> List Token
unitTwoTokens prefix =
    tokenList prefix
        [ ( "πολλὰς", ( "πολύς", "accusative plural feminine", "many" ) )
        , ( "δ᾽", ( "δέ", "conjunction", "and" ) )
        , ( "ἰφθίμους", ( "ἴφθιμος", "accusative plural feminine", "mighty" ) )
        , ( "ψυχὰς", ( "ψυχή", "accusative plural feminine", "souls" ) )
        , ( "Ἄϊδι", ( "Ἅιδης", "dative singular masculine", "to Hades" ) )
        , ( "προΐαψεν", ( "προϊάπτω", "aorist active indicative, 3rd singular", "sent forth" ) )
        , ( "ἡρώων,", ( "ἥρως", "genitive plural masculine", "of heroes" ) )
        , ( "αὐτοὺς", ( "αὐτός", "accusative plural masculine", "them" ) )
        , ( "δὲ", ( "δέ", "conjunction", "but" ) )
        , ( "ἑλώρια", ( "ἑλώριον", "accusative plural neuter", "prey" ) )
        , ( "τεῦχε", ( "τεύχω", "imperfect active indicative, 3rd singular", "made" ) )
        , ( "κύνεσσιν", ( "κύων", "dative plural", "for dogs" ) )
        , ( "οἰωνοῖσί", ( "οἰωνός", "dative plural masculine", "for birds" ) )
        , ( "τε", ( "τε", "conjunction", "and" ) )
        , ( "πᾶσι,", ( "πᾶς", "dative plural masculine", "all" ) )
        , ( "Διὸς", ( "Ζεύς", "genitive singular masculine", "of Zeus" ) )
        , ( "δ᾽", ( "δέ", "conjunction", "and" ) )
        , ( "ἐτελείετο", ( "τελέω", "imperfect middle indicative, 3rd singular", "was fulfilled" ) )
        , ( "βουλή,", ( "βουλή", "nominative singular feminine", "will" ) )
        ]


unitThreeTokens : String -> List Token
unitThreeTokens prefix =
    tokenList prefix
        [ ( "ἐξ", ( "ἐκ", "preposition with genitive", "from" ) )
        , ( "οὗ", ( "ὅς", "genitive singular neuter", "which point" ) )
        , ( "δὴ", ( "δή", "particle", "indeed" ) )
        , ( "τὰ", ( "ὁ", "accusative plural neuter", "the" ) )
        , ( "πρῶτα", ( "πρῶτος", "accusative plural neuter", "first" ) )
        , ( "διαστήτην", ( "διΐστημι", "aorist active dual, 3rd person", "stood apart" ) )
        , ( "ἐρίσαντε", ( "ἐρίζω", "aorist active participle, nominative dual", "quarrelling" ) )
        , ( "Ἀτρεΐδης", ( "Ἀτρεΐδης", "nominative singular masculine", "son of Atreus" ) )
        , ( "τε", ( "τε", "conjunction", "and" ) )
        , ( "ἄναξ", ( "ἄναξ", "nominative singular masculine", "lord" ) )
        , ( "ἀνδρῶν", ( "ἀνήρ", "genitive plural masculine", "of men" ) )
        , ( "καὶ", ( "καί", "conjunction", "and" ) )
        , ( "δῖος", ( "δῖος", "nominative singular masculine", "brilliant" ) )
        , ( "Ἀχιλλεύς.", ( "Ἀχιλλεύς", "nominative singular masculine", "Achilles" ) )
        ]


tokenList : String -> List ( String, ( String, String, String ) ) -> List Token
tokenList prefix entries =
    entries
        |> List.indexedMap
            (\index ( form, ( lemma, morphology, gloss ) ) ->
                { id = prefix ++ "-token-" ++ String.fromInt index
                , form = form
                , lemma = lemma
                , morphology = morphology
                , gloss = gloss
                }
            )
