module Main exposing (main)

import Browser
import Html exposing (Html, aside, button, div, footer, h1, h2, h3, header, main_, nav, p, section, span, text)
import Html.Attributes exposing (attribute, class, classList, disabled, id, tabindex, type_)
import Html.Events exposing (onClick)


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
    , tokens : List Token
    , translation : String
    , progressLabel : String
    }


type alias Token =
    { id : TokenId
    , form : String
    , lemma : String
    , morphology : String
    , gloss : String
    }


type alias Model =
    { screen : Screen
    , selectedToken : Maybe TokenId
    , translationOpen : Bool
    , menuOpen : Bool
    }


type Msg
    = ShowLibrary
    | ShowContents WorkId
    | ShowReader WorkId UnitId
    | SelectToken TokenId
    | CloseTokenHelp
    | ToggleTranslation
    | RereadGreek
    | ToggleMenu
    | PreviousFixtureUnit
    | NextFixtureUnit


main : Program () Model Msg
main =
    Browser.sandbox
        { init = init
        , update = update
        , view = view
        }


init : Model
init =
    { screen = LibraryScreen
    , selectedToken = Nothing
    , translationOpen = False
    , menuOpen = False
    }


update : Msg -> Model -> Model
update msg model =
    case msg of
        ShowLibrary ->
            resetPanels { model | screen = LibraryScreen }

        ShowContents workId ->
            resetPanels { model | screen = ContentsScreen workId }

        ShowReader workId unitId ->
            resetPanels { model | screen = ReaderScreen workId unitId }

        SelectToken tokenId ->
            { model | selectedToken = Just tokenId, menuOpen = False }

        CloseTokenHelp ->
            { model | selectedToken = Nothing }

        ToggleTranslation ->
            { model | translationOpen = not model.translationOpen, selectedToken = Nothing }

        RereadGreek ->
            { model | translationOpen = False, selectedToken = Nothing, menuOpen = False }

        ToggleMenu ->
            { model | menuOpen = not model.menuOpen, selectedToken = Nothing }

        PreviousFixtureUnit ->
            moveUnit -1 model

        NextFixtureUnit ->
            moveUnit 1 model


resetPanels : Model -> Model
resetPanels model =
    { model | selectedToken = Nothing, translationOpen = False, menuOpen = False }


moveUnit : Int -> Model -> Model
moveUnit offset model =
    case model.screen of
        ReaderScreen workId unitId ->
            case findWork workId of
                Just work ->
                    let
                        units =
                            workUnits work

                        currentIndex =
                            findIndex (\unit -> unit.id == unitId) units
                    in
                    case currentIndex of
                        Just index ->
                            case getAt (index + offset) units of
                                Just unit ->
                                    resetPanels { model | screen = ReaderScreen workId unit.id }

                                Nothing ->
                                    model

                        Nothing ->
                            model

                Nothing ->
                    model

        _ ->
            model


view : Model -> Html Msg
view model =
    div [ class "app-shell" ]
        [ case model.screen of
            LibraryScreen ->
                viewLibrary

            ContentsScreen workId ->
                viewContents workId

            ReaderScreen workId unitId ->
                viewReader model workId unitId
        ]


viewLibrary : Html Msg
viewLibrary =
    div []
        [ header [ class "site-header" ]
            [ div [ class "brand" ]
                [ span [ class "brand-mark", attribute "aria-hidden" "true" ] [ text "Α" ]
                , span [] [ text "Aristos" ]
                ]
            , button [ class "quiet-button", type_ "button", attribute "aria-label" "Open settings" ] [ text "Aa" ]
            ]
        , main_ [ class "page library-page" ]
            [ section [ class "intro" ]
                [ p [ class "eyebrow" ] [ text "Your Greek library" ]
                , h1 [] [ text "Read without interruption." ]
                , p [ class "intro-copy" ] [ text "Connected Greek texts with help available only when you ask for it." ]
                ]
            , div [ class "work-grid" ] (List.map viewWorkCard works)
            ]
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
                    [ div [ class "reader-meta" ]
                        [ span [] [ text "Typography sample · Homer, Iliad 1.1–7" ]
                        , span [] [ text unit.progressLabel ]
                        ]
                    , section [ class "passage", attribute "aria-label" "Greek passage" ]
                        (List.map (viewToken model.selectedToken) unit.tokens)
                    , p [ class "sample-note" ] [ text "Original Homeric Greek is used as sample copy throughout this UI prototype." ]
                    , if model.translationOpen then
                        viewTranslation unit

                      else
                        text ""
                    ]
                , case selectedTokenInUnit model.selectedToken unit of
                    Just token ->
                        viewTokenHelp token

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
                    , button [ class "action-button translation-action", type_ "button", onClick ToggleTranslation ]
                        [ text
                            (if model.translationOpen then
                                "Hide translation"

                             else
                                "Check translation"
                            )
                        ]
                    , button
                        [ class "action-button next-action"
                        , type_ "button"
                        , disabled nextDisabled
                        , onClick NextFixtureUnit
                        ]
                        [ span [] [ text "Done & next" ]
                        , span [ attribute "aria-hidden" "true" ] [ text "→" ]
                        ]
                    ]
                ]

        _ ->
            viewNotFound


viewToken : Maybe TokenId -> Token -> Html Msg
viewToken selectedToken token =
    button
        [ classList
            [ ( "greek-token", True )
            , ( "is-selected", selectedToken == Just token.id )
            ]
        , type_ "button"
        , onClick (SelectToken token.id)
        , attribute "aria-pressed" (boolString (selectedToken == Just token.id))
        ]
        [ text token.form ]


viewTranslation : Unit -> Html Msg
viewTranslation unit =
    section [ class "translation-panel", attribute "aria-label" "Translation" ]
        [ div [ class "panel-heading" ]
            [ div []
                [ p [ class "eyebrow" ] [ text "Translation" ]
                , h2 [] [ text "A quick check" ]
                ]
            , button [ class "quiet-button", type_ "button", onClick ToggleTranslation, attribute "aria-label" "Close translation" ] [ text "×" ]
            ]
        , p [] [ text unit.translation ]
        , button [ class "secondary-button", type_ "button", onClick RereadGreek ] [ text "Reread Greek" ]
        ]


viewTokenHelp : Token -> Html Msg
viewTokenHelp token =
    aside
        [ class "token-sheet"
        , attribute "role" "dialog"
        , attribute "aria-labelledby" "token-sheet-title"
        ]
        [ div [ class "sheet-handle", attribute "aria-hidden" "true" ] []
        , div [ class "panel-heading" ]
            [ div []
                [ p [ class "eyebrow" ] [ text "Word help" ]
                , h2 [ id "token-sheet-title", class "sheet-token" ] [ text token.form ]
                ]
            , button [ class "quiet-button close-button", type_ "button", onClick CloseTokenHelp, attribute "aria-label" "Close word help" ] [ text "×" ]
            ]
        , div [ class "help-grid" ]
            [ div []
                [ span [ class "help-label" ] [ text "Gloss" ]
                , p [ class "help-primary" ] [ text token.gloss ]
                ]
            , div []
                [ span [ class "help-label" ] [ text "Lemma" ]
                , p [] [ text token.lemma ]
                ]
            , div [ class "morphology" ]
                [ span [ class "help-label" ] [ text "Morphology" ]
                , p [] [ text token.morphology ]
                ]
            ]
        ]


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
        ]


viewNotFound : Html Msg
viewNotFound =
    main_ [ class "page empty-state" ]
        [ h1 [] [ text "This fixture is missing." ]
        , button [ class "primary-button", type_ "button", onClick ShowLibrary ] [ text "Return to library" ]
        ]


selectedTokenInUnit : Maybe TokenId -> Unit -> Maybe Token
selectedTokenInUnit selectedToken unit =
    case selectedToken of
        Just tokenId ->
            List.filter (\token -> token.id == tokenId) unit.tokens |> List.head

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
      , tokens = unitOneTokens (prefix ++ "-1")
      , translation = "Sing, goddess, of the destructive anger of Achilles, which brought countless sorrows upon the Achaeans. Demo translation for layout only."
      , progressLabel = "1 of 3"
      }
    , { id = prefix ++ "-2"
      , reference = "Ἰλιάς 1.3–5"
      , tokens = unitTwoTokens (prefix ++ "-2")
      , translation = "It sent many mighty souls of heroes to Hades and made their bodies prey for dogs and birds. Demo translation for layout only."
      , progressLabel = "2 of 3"
      }
    , { id = prefix ++ "-3"
      , reference = "Ἰλιάς 1.6–7"
      , tokens = unitThreeTokens (prefix ++ "-3")
      , translation = "From the first moment when the son of Atreus and brilliant Achilles divided in strife. Demo translation for layout only."
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
