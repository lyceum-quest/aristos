port module Main exposing (main)

import Browser
import Browser.Dom as Dom
import Browser.Events
import Browser.Navigation as Nav
import Conllu
import Dict exposing (Dict)
import Html exposing (Html, a, article, aside, button, div, footer, h1, h2, h3, header, input, label, main_, nav, option, p, section, select, span, text, textarea)
import Html.Attributes exposing (attribute, checked, class, classList, disabled, href, id, placeholder, rel, rows, selected, style, target, type_, value)
import Html.Events exposing (on, onClick, onInput, stopPropagationOn)
import Http
import Passage
import Json.Decode as Decode
import Json.Encode as Encode
import Process
import Route exposing (Route)
import Set exposing (Set)
import Sources
import Fsrs
import Review
import Study
import Task
import Time
import Url exposing (Url)


type Screen
    = LibraryScreen
    | WorkspaceScreen
    | SettingsScreen
    | ReaderScreen


type Preset
    = ReadPreset
    | AssistedPreset
    | IntensivePreset
    | CustomPreset


type Theme
    = DarkTheme
    | LightTheme


{-| The study tools a passage offers: per-word glosses and the two translations.
-}
type ModuleId
    = GlossModule
    | LiteralModule
    | ProseModule


type ModuleMode
    = ModuleOff
    | OnDemand


type alias ModuleSettings =
    { gloss : ModuleMode
    , literal : ModuleMode
    , prose : ModuleMode
    }


type PopupTab
    = WordTab
    | SentenceTab


{-| Where the desktop word popup sits relative to its word, measured once it has rendered. Phones show it as a
bottom sheet instead, so this is ignored there.
-}
type alias PopupPlacement =
    { above : Bool
    , shift : Float
    , maxHeight : Float
    }


{-| A touch on the passage. It becomes a horizontal swipe only when it first moves mostly sideways soon after it
starts, so vertical scrolling and long-press text selection are left to the browser.
-}
type alias Swipe =
    { startX : Float
    , startY : Float
    , startTime : Float
    , dx : Float
    , axis : SwipeAxis
    }


type SwipeAxis
    = Undecided
    | Horizontal
    | Vertical


type alias Corpus =
    Conllu.Corpus


type alias CorpusSource =
    Conllu.CorpusSource


type alias Sentence =
    Conllu.Sentence


type alias CorpusToken =
    Conllu.CorpusToken


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
    , citation : Maybe Sources.Citation
    , unitsPath : String
    , passages : List String
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
    , preset : Preset
    , settings : ModuleSettings
    , activeModule : Maybe ModuleId
    , study : Study.Draft
    , attempts : List Study.Attempt
    , popupWord : Maybe Int
    , popupTab : PopupTab
    , popupPlacement : Maybe PopupPlacement
    , swipe : Maybe Swipe
    , historyOpen : Bool
    , historyAttempt : Maybe Int
    , zone : Time.Zone
    , routeQuery : Dict String String
    , clock : Int
    , confirmClear : Bool
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
    , positions : Dict String Int
    , readerGloss : Maybe ( Int, Int )
    , readerRevealed : Set Int
    , scrollGeneration : Int
    , reviews : Dict String Review.Entry
    , newPerDay : Int
    , queueMode : Bool
    , queueDone : Bool
    }


type Msg
    = ShowLibrary
    | ShowWorkspace
    | ShowSettings
    | PreviousSentence
    | NextSentence
    | JumpToPassage String
    | JumpToCitation String
    | GoToCitation String
    | Navigate Route
    | UrlRequested Browser.UrlRequest
    | UrlChanged Url
    | KeyPressed String String
    | ReaderTokenTapped Int Int
    | ReaderToggleTranslation Int
    | ReaderStep Int
    | ReaderScrolled
    | ReaderSettled Int
    | ReaderMeasured Int (Result Dom.Error ( Dom.Element, List Dom.Element ))
    | NoOp
    | SelectPreset Preset
    | ToggleModule ModuleId
    | OpenModule ModuleId
    | CloseWorkbench
    | OpenWordPopup Int
    | ClosePopup
    | SetPopupTab PopupTab
    | PopupMeasured (Result Dom.Error PopupPlacement)
    | PopupResized
    | SwipeStart Float Float Float
    | SwipeMove Float Float Float
    | SwipeEnd
    | OpenHistory
    | CloseHistory
    | SelectHistoryAttempt Int
    | GotZone Time.Zone
    | StudyGloss Int String
    | StudyLiteral String
    | StudyProse String
    | RevealItem String
    | SubmitStudy
    | ReopenStudy
    | MarkItem String Bool
    | FinishGrading Fsrs.Rating
    | StudyToday ManifestEntry
    | ContinueReading
    | SetNewPerDay String
    | GradingFinished Fsrs.Rating Time.Posix
    | ClearSavedData
    | ConfirmClearSavedData
    | CancelClearSavedData
    | ShowNotice String
    | DismissNotice
    | ToggleTheme
    | Tick Time.Posix
    | GotManifest (Result Http.Error Manifest)
    | GotCorpus ManifestEntry (Result Http.Error ( String, String ))
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
                , preset = AssistedPreset
                , settings = assistedSettings
                , activeModule = Nothing
                , study = Study.emptyDraft
                , attempts = []
                , popupWord = Nothing
                , popupTab = WordTab
                , popupPlacement = Nothing
                , swipe = Nothing
                , historyOpen = False
                , historyAttempt = Nothing
                , zone = Time.utc
                , routeQuery = Route.query url
                , clock = 0
                , confirmClear = False
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
                , positions = Dict.empty
                , readerGloss = Nothing
                , readerRevealed = Set.empty
                , scrollGeneration = 0
                , reviews = Dict.empty
                , newPerDay = Review.newPerDayDefault
                , queueMode = False
                , queueDone = False
                }
    in
    ( model
    , Cmd.batch
        [ fetchManifest
        , routeCmd
        , Task.perform Tick Time.now
        , Task.perform GotZone Time.here
        , storageGet "theme" "metadata" "theme"
        , storageGet "positions" "metadata" "positions"
        , storageGet "review-settings" "metadata" "review-settings"
        , storageGetAll "attempts" "progress"
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
            "Study tools · Aristos"

        ( _, Just entry ) ->
            entry.title ++ " " ++ currentLabel model ++ " · Aristos"

        ( _, Nothing ) ->
            "Aristos"


{-| The route part of a URL in the same form `pathFor` produces, including the fragment's query.
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


readSettings : ModuleSettings
readSettings =
    { gloss = OnDemand, literal = ModuleOff, prose = ModuleOff }


assistedSettings : ModuleSettings
assistedSettings =
    { gloss = OnDemand, literal = ModuleOff, prose = OnDemand }


intensiveSettings : ModuleSettings
intensiveSettings =
    { gloss = OnDemand, literal = OnDemand, prose = OnDemand }


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ storageResponse GotStorage
        , Time.every 30000 Tick
        , if model.screen == WorkspaceScreen || model.screen == ReaderScreen then
            Browser.Events.onKeyDown keyDecoder

          else
            Sub.none
        , if model.popupWord /= Nothing && model.screen == WorkspaceScreen then
            Browser.Events.onResize (\_ _ -> PopupResized)

          else
            Sub.none
        ]


{-| Every update then follows the passage (loading its saved draft), saves an edited draft, and syncs the URL.
Changes that stay on the same page (popups, tools, reader scrolling) replace the history entry instead of adding one.
-}
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        ( updated, cmd ) =
            updateModel msg model

        ( followed, loadCmd ) =
            followPassage model updated

        ( next, placeCmd ) =
            followPopup (isPopupResize msg) model followed

        replace =
            isUrlChange msg
                || (model.screen == ReaderScreen && next.screen == ReaderScreen)
                || (basePath model == basePath next)
    in
    syncUrl replace next (Cmd.batch [ cmd, loadCmd, placeCmd, saveDraft model next ])


{-| A newly shown popup (another word, tab, or page) renders hidden in its natural place below the word, is measured,
and then shown where it fits.
-}
followPopup : Bool -> Model -> Model -> ( Model, Cmd Msg )
followPopup resized previous next =
    case next.popupWord of
        Just tokenId ->
            if resized || previous.popupWord /= next.popupWord || previous.popupTab /= next.popupTab || previous.screen /= next.screen then
                ( { next | popupPlacement = Nothing }, measurePopup tokenId )

            else
                ( next, Cmd.none )

        Nothing ->
            ( { next | popupPlacement = Nothing }, Cmd.none )


popupElementId : String
popupElementId =
    "word-popup"


tokenElementId : Int -> String
tokenElementId tokenId =
    "study-token-" ++ String.fromInt tokenId


{-| Opens below the word unless it fits better above, never taller than the room between the sticky header and the
fixed footer, and shifted sideways to stay inside the viewport.
-}
measurePopup : Int -> Cmd Msg
measurePopup tokenId =
    let
        heightOf elementId =
            Dom.getElement elementId
                |> Task.map (\found -> found.element.height)
                |> Task.onError (\_ -> Task.succeed 0)

        margin =
            12
    in
    Task.map4
        (\word popup headerHeight footerHeight ->
            let
                viewport =
                    popup.viewport

                spaceBelow =
                    viewport.y + viewport.height - footerHeight - margin - (word.element.y + word.element.height + 8)

                spaceAbove =
                    word.element.y - 8 - (viewport.y + headerHeight + margin)

                above =
                    popup.element.height > spaceBelow && spaceAbove > spaceBelow

                right =
                    word.element.x + popup.element.width

                leftShift =
                    min 0 (viewport.x + viewport.width - margin - right)
            in
            { above = above
            , shift = max leftShift (viewport.x + margin - word.element.x)
            , maxHeight =
                max 160
                    (if above then
                        spaceAbove

                     else
                        spaceBelow
                    )
            }
        )
        (Dom.getElement (tokenElementId tokenId))
        (Dom.getElement popupElementId)
        (heightOf appHeaderId)
        (heightOf studyFooterId)
        |> Task.attempt PopupMeasured


appHeaderId : String
appHeaderId =
    "app-header"


studyFooterId : String
studyFooterId =
    "study-footer"


isPopupResize : Msg -> Bool
isPopupResize msg =
    case msg of
        PopupResized ->
            True

        _ ->
            False


isUrlChange : Msg -> Bool
isUrlChange msg =
    case msg of
        UrlChanged _ ->
            True

        _ ->
            False


draftKey : Model -> Maybe String
draftKey model =
    if model.corpusReady then
        model.activeEntry |> Maybe.map (\entry -> "draft:" ++ entry.id ++ ":" ++ currentRef model)

    else
        Nothing


{-| A newly shown passage starts empty until its saved draft (if any) arrives from IndexedDB.
-}
followPassage : Model -> Model -> ( Model, Cmd Msg )
followPassage previous next =
    case draftKey next of
        Just key ->
            if draftKey previous == Just key then
                ( next, Cmd.none )

            else
                ( { next | study = Study.emptyDraft }, storageGet ("study-draft:" ++ key) "metadata" key )

        Nothing ->
            ( next, Cmd.none )


saveDraft : Model -> Model -> Cmd Msg
saveDraft previous next =
    case draftKey next of
        Just key ->
            if draftKey previous == Just key && previous.study /= next.study then
                storagePut "save-draft" "metadata" (Encode.object [ ( "key", Encode.string key ), ( "value", Study.encodeDraft next.study ) ])

            else
                Cmd.none

        Nothing ->
            Cmd.none


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
                applyRoute (Route.fromUrl url |> Maybe.withDefault Route.Library) { model | currentPath = urlPath url, routeQuery = Route.query url }

        JumpToCitation prefix ->
            jumpToCitation prefix model

        GoToCitation typed ->
            if String.isEmpty (normalizeCitation typed) then
                ( model, Cmd.none )

            else
                jumpToCitation (normalizeCitation typed) model

        JumpToPassage passage ->
            case String.toInt passage of
                Just number ->
                    ( moveToSentence (number - 1) (browsing model), Cmd.none )

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
            ( { model | sentenceIndex = target, readerGloss = Nothing, scrollGeneration = model.scrollGeneration + 1 }, scrollToSentence target )

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
                ( model, measureReader generation model )

        ReaderMeasured generation (Ok ( container, sentences )) ->
            -- Measuring takes a frame per passage; a step or scroll since it began makes the result stale.
            if generation /= model.scrollGeneration then
                ( model, Cmd.none )

            else
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

        ReaderMeasured _ (Err _) ->
            ( model, Cmd.none )

        NoOp ->
            ( model, Cmd.none )

        ShowLibrary ->
            ( { model | screen = LibraryScreen, notice = Nothing, popupWord = Nothing }, Cmd.none )

        ShowWorkspace ->
            if model.corpusReady then
                ( { model | screen = WorkspaceScreen, notice = Nothing }, Cmd.none )

            else
                ( { model | notice = Just "The local corpus is still loading." }, Cmd.none )

        ShowSettings ->
            ( { model | screen = SettingsScreen, notice = Nothing, popupWord = Nothing, confirmClear = False }, Cmd.none )

        PreviousSentence ->
            ( moveToSentence (model.sentenceIndex - 1) (browsing model), Cmd.none )

        NextSentence ->
            ( moveToSentence (model.sentenceIndex + 1) (browsing model), Cmd.none )

        SelectPreset preset ->
            ( { model | preset = preset, settings = settingsForPreset preset model.settings, activeModule = Nothing }, Cmd.none )

        ToggleModule moduleId ->
            let
                settings =
                    setModuleMode moduleId
                        (if moduleMode moduleId model.settings == ModuleOff then
                            OnDemand

                         else
                            ModuleOff
                        )
                        model.settings
            in
            ( { model
                | preset = CustomPreset
                , settings = settings
                , activeModule =
                    if model.activeModule == Just moduleId && moduleMode moduleId settings == ModuleOff then
                        Nothing

                    else
                        model.activeModule
              }
            , Cmd.none
            )

        OpenModule moduleId ->
            ( { model | activeModule = Just moduleId, popupWord = Nothing }, Cmd.none )

        CloseWorkbench ->
            ( { model | activeModule = Nothing }, Cmd.none )

        OpenWordPopup tokenId ->
            ( { model
                | popupWord = Just tokenId
                , popupTab =
                    if model.popupWord == Just tokenId then
                        model.popupTab

                    else
                        WordTab
              }
            , Cmd.none
            )

        ClosePopup ->
            ( { model | popupWord = Nothing }, Cmd.none )

        SetPopupTab tab ->
            ( { model | popupTab = tab }, Cmd.none )

        PopupMeasured result ->
            ( { model | popupPlacement = Just (Result.withDefault { above = False, shift = 0, maxHeight = 0 } result) }, Cmd.none )

        PopupResized ->
            ( model, Cmd.none )

        SwipeStart x y time ->
            ( { model | swipe = Just { startX = x, startY = y, startTime = time, dx = 0, axis = Undecided } }, Cmd.none )

        SwipeMove x y time ->
            ( { model | swipe = Maybe.map (followSwipe x y time) model.swipe }, Cmd.none )

        SwipeEnd ->
            let
                settled =
                    { model | swipe = Nothing }
            in
            case model.swipe of
                Just swipe ->
                    if swipe.axis == Horizontal && abs swipe.dx > swipeThreshold then
                        let
                            delta =
                                if swipe.dx < 0 then
                                    1

                                else
                                    -1
                        in
                        if model.screen == ReaderScreen then
                            updateModel (ReaderStep delta) settled

                        else
                            ( moveToSentence (model.sentenceIndex + delta) (browsing settled), Cmd.none )

                    else
                        ( settled, Cmd.none )

                Nothing ->
                    ( settled, Cmd.none )

        OpenHistory ->
            ( { model | historyOpen = True, historyAttempt = Nothing, popupWord = Nothing, activeModule = Nothing }, Cmd.none )

        CloseHistory ->
            ( { model | historyOpen = False, historyAttempt = Nothing }, Cmd.none )

        SelectHistoryAttempt finishedAt ->
            ( { model
                | historyAttempt =
                    if model.historyAttempt == Just finishedAt then
                        Nothing

                    else
                        Just finishedAt
              }
            , Cmd.none
            )

        GotZone zone ->
            ( { model | zone = zone }, Cmd.none )

        StudyGloss tokenId gloss ->
            ( editStudy (\draft -> { draft | glosses = Dict.insert tokenId gloss draft.glosses }) model, Cmd.none )

        StudyLiteral literal ->
            ( editStudy (\draft -> { draft | literal = literal }) model, Cmd.none )

        StudyProse prose ->
            ( editStudy (\draft -> { draft | prose = prose }) model, Cmd.none )

        RevealItem key ->
            ( editStudy (\draft -> { draft | revealed = Set.insert key draft.revealed }) model, Cmd.none )

        SubmitStudy ->
            let
                study =
                    model.study
            in
            ( { model | study = { study | submitted = True, updatedAt = model.clock }, popupWord = Nothing, activeModule = Nothing }, Cmd.none )

        ReopenStudy ->
            let
                study =
                    model.study
            in
            ( { model | study = { study | submitted = False, marks = Dict.empty } }, Cmd.none )

        MarkItem key right ->
            let
                study =
                    model.study

                marks =
                    if Dict.get key study.marks == Just right then
                        Dict.remove key study.marks

                    else
                        Dict.insert key right study.marks
            in
            ( { model | study = { study | marks = marks, updatedAt = model.clock } }, Cmd.none )

        FinishGrading rating ->
            ( model, Task.perform (GradingFinished rating) Time.now )

        GradingFinished rating time ->
            let
                now =
                    Time.posixToMillis time
            in
            case ( buildAttempt now model, model.activeEntry ) of
                ( Just attempt, Just entry ) ->
                    let
                        passage =
                            currentRef model

                        scheduled =
                            Review.schedule now rating entry.id passage model.reviews

                        recorded =
                            { model
                                | attempts = attempt :: model.attempts
                                , reviews =
                                    scheduled
                                        |> Maybe.map (\review -> Dict.insert (Review.entryKey entry.id passage) review model.reviews)
                                        |> Maybe.withDefault model.reviews
                                , study = Study.emptyDraft
                                , clock = now
                            }

                        advanced =
                            advance recorded
                    in
                    ( { advanced
                        | notice =
                            scheduled
                                |> Maybe.map (\review -> "Saved. " ++ workTitle model ++ " " ++ currentLabel model ++ " comes back in " ++ Review.intervalLabel now review.card.due ++ ".")
                      }
                    , Cmd.batch
                        [ storagePut "save-attempt" "progress" (Study.encodeAttempt attempt)
                        , scheduled |> Maybe.map (Review.encodeEntry >> storagePut "save-card" "progress") |> Maybe.withDefault Cmd.none
                        , draftKey model
                            |> Maybe.map (\key -> storagePut "save-draft" "metadata" (Encode.object [ ( "key", Encode.string key ), ( "value", Study.encodeDraft Study.emptyDraft ) ]))
                            |> Maybe.withDefault Cmd.none
                        ]
                    )

                _ ->
                    ( model, Cmd.none )

        StudyToday entry ->
            let
                today =
                    Review.queue model.clock model.newPerDay entry.id entry.passages model.reviews

                first =
                    List.head (today.due ++ today.new)

                -- With nothing queued, reopen where the learner last was.
                passage =
                    first |> Maybe.withDefault (savedRef entry model)
            in
            ( { model | queueMode = True, queueDone = first == Nothing }
            , Nav.pushUrl model.key (Route.toPath (Route.Study entry.id passage) ++ "?queue=1")
            )

        ContinueReading ->
            ( moveToSentence (model.sentenceIndex + 1) (browsing model), Cmd.none )

        SetNewPerDay value ->
            case String.toInt value of
                Just newPerDay ->
                    ( { model | newPerDay = newPerDay }
                    , storagePut "save-review-settings" "metadata" (Encode.object [ ( "key", Encode.string "review-settings" ), ( "value", Encode.object [ ( "newPerDay", Encode.int newPerDay ) ] ) ])
                    )

                Nothing ->
                    ( model, Cmd.none )

        ClearSavedData ->
            ( { model | confirmClear = True }, Cmd.none )

        CancelClearSavedData ->
            ( { model | confirmClear = False }, Cmd.none )

        ConfirmClearSavedData ->
            ( { model
                | attempts = []
                , reviews = Dict.empty
                , study = Study.emptyDraft
                , positions = Dict.empty
                , confirmClear = False
                , notice = Just "Saved study data cleared from this device."
              }
            , Cmd.batch [ storageClear "clear-progress" "progress", storageClear "clear-metadata" "metadata" ]
            )

        ShowNotice notice ->
            ( { model | notice = Just notice }, Cmd.none )

        DismissNotice ->
            ( { model | notice = Nothing }, Cmd.none )

        ToggleTheme ->
            let
                theme =
                    if model.theme == DarkTheme then
                        LightTheme

                    else
                        DarkTheme
            in
            ( { model | theme = theme }
            , storagePut "theme" "metadata"
                (Encode.object
                    [ ( "key", Encode.string "theme" )
                    , ( "value"
                      , Encode.string
                            (if theme == DarkTheme then
                                "dark"

                             else
                                "light"
                            )
                      )
                    ]
                )
            )

        Tick time ->
            ( { model | clock = Time.posixToMillis time }, Cmd.none )


{-| Answers can change only before the checkpoint; the first edit stamps when work on the passage began.
-}
editStudy : (Study.Draft -> Study.Draft) -> Model -> Model
editStudy change model =
    if model.study.submitted then
        model

    else
        let
            changed =
                change model.study
        in
        { model
            | study =
                if changed.startedAt == 0 then
                    { changed | startedAt = model.clock, updatedAt = model.clock }

                else
                    { changed | updatedAt = model.clock }
        }


{-| A saved draft resumes grading only if it was touched in the last 30 minutes (a refresh mid-grading). An older
submitted draft is an abandoned checkpoint: it reopens for answering with the answers kept and the marks cleared, so
opening a passage always starts with reading and attempting.
-}
resumable : Int -> Study.Draft -> Study.Draft
resumable now draft =
    if draft.submitted && now - draft.updatedAt > 30 * 60 * 1000 then
        { draft | submitted = False, marks = Dict.empty }

    else
        draft


{-| The items of the current passage in grading order: each word (punctuation excluded), then the translations the learner worked on or has enabled.
-}
studyItems : Model -> List Study.Item
studyItems model =
    let
        sentence =
            currentSentence model

        study =
            model.study

        item key kind form lemma guess reference =
            { key = key
            , kind = kind
            , form = form
            , lemma = lemma
            , guess = guess
            , reference = reference
            , revealedEarly = Set.member key study.revealed
            , mark = Dict.get key study.marks
            }

        words =
            if moduleMode GlossModule model.settings /= ModuleOff || not (Dict.isEmpty study.glosses) then
                sentence.tokens
                    |> List.filter Study.isWordToken
                    |> List.map (\token -> item (Study.wordKey token.id) Study.WordItem token.form token.lemma (Dict.get token.id study.glosses |> Maybe.withDefault "") token.gloss)

            else
                []

        literal =
            if moduleMode LiteralModule model.settings /= ModuleOff || not (String.isEmpty study.literal) then
                [ item Study.literalKey Study.LiteralItem "" "" study.literal sentence.literalTranslation ]

            else
                []

        prose =
            if moduleMode ProseModule model.settings /= ModuleOff || not (String.isEmpty study.prose) then
                [ item Study.proseKey Study.ProseItem "" "" study.prose sentence.proseTranslation ]

            else
                []
    in
    words ++ literal ++ prose


buildAttempt : Int -> Model -> Maybe Study.Attempt
buildAttempt now model =
    model.activeEntry
        |> Maybe.map
            (\entry ->
                let
                    sentence =
                        currentSentence model

                    passage =
                        currentRef model
                in
                { id = "attempt:" ++ entry.id ++ ":" ++ passage ++ ":" ++ String.fromInt now
                , work = entry.id
                , passage = passage
                , sentenceId = sentence.id
                , sentenceText = sentence.text
                , startedAt =
                    if model.study.startedAt == 0 then
                        now

                    else
                        model.study.startedAt
                , finishedAt = now
                , items = studyItems model
                }
            )



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
            ( model
            , Nav.replaceUrl model.key
                (Route.toPath
                    (Route.Study work
                        (List.filter (\entry -> entry.id == work) model.library |> List.head |> Maybe.map (\entry -> savedRef entry model) |> Maybe.withDefault "")
                    )
                )
            )

        _ ->
            case routeWork route of
                Just work ->
                    if model.corpusReady && Maybe.map .id model.activeEntry == Just work then
                        showRoute route model

                    else
                        requestWork work route model

                Nothing ->
                    ( model, Cmd.none )


showRoute : Route -> Model -> ( Model, Cmd Msg )
showRoute route model =
    let
        settled =
            { model | pendingRoute = Nothing }

        -- A citation that is not a passage of this work (e.g. an old bookmark) opens the saved position.
        indexFor work ref =
            indexOfRef ref model
                |> Maybe.withDefault (clamp 0 (List.length model.corpus.sentences - 1) ((Dict.get work model.positions |> Maybe.withDefault 1) - 1))
    in
    case route of
        Route.Study work passage ->
            let
                index =
                    indexFor work passage

                moved =
                    if index == settled.sentenceIndex then
                        settled

                    else
                        moveToSentence index settled
            in
            ( applyQuery { moved | screen = WorkspaceScreen }, Cmd.none )

        Route.Reader work passage ->
            let
                index =
                    indexFor work (passage |> Maybe.withDefault "")
            in
            ( { settled | screen = ReaderScreen, sentenceIndex = index, readerGloss = Nothing }, scrollToSentence index )

        _ ->
            ( settled, Cmd.none )


{-| Restores the popup, its tab, and the open tool from the URL's query.
-}
applyQuery : Model -> Model
applyQuery model =
    let
        query =
            model.routeQuery
    in
    { model
        | popupWord = Dict.get "word" query |> Maybe.andThen String.toInt
        , popupTab =
            if Dict.get "tab" query == Just "sentence" then
                SentenceTab

            else
                WordTab
        , activeModule = Dict.get "tool" query |> Maybe.andThen moduleFromKey
        , historyOpen = Dict.get "history" query == Just "1"
        , historyAttempt = Dict.get "attempt" query |> Maybe.andThen String.toInt
        , queueMode = Dict.get "queue" query == Just "1"
    }


queryFor : Model -> String
queryFor model =
    let
        pairs =
            List.filterMap identity
                [ model.popupWord |> Maybe.map (\word -> "word=" ++ String.fromInt word)
                , model.popupWord
                    |> Maybe.andThen
                        (\_ ->
                            if model.popupTab == SentenceTab then
                                Just "tab=sentence"

                            else
                                Nothing
                        )
                , model.activeModule |> Maybe.map (\moduleId -> "tool=" ++ moduleKey moduleId)
                , if model.historyOpen then
                    Just "history=1"

                  else
                    Nothing
                , model.historyAttempt |> Maybe.map (\finishedAt -> "attempt=" ++ String.fromInt finishedAt)
                , if model.queueMode then
                    Just "queue=1"

                  else
                    Nothing
                ]
    in
    if List.isEmpty pairs then
        ""

    else
        "?" ++ String.join "&" pairs


{-| The URL follows the model; `replace` avoids a history entry for same-page changes.
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


basePath : Model -> Maybe String
basePath model =
    let
        passage =
            currentRef model

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


pathFor : Model -> Maybe String
pathFor model =
    if model.screen == WorkspaceScreen then
        basePath model |> Maybe.map (\path -> path ++ queryFor model)

    else
        basePath model


handleStorageResponse : Decode.Value -> Model -> Model
handleStorageResponse value model =
    case Decode.decodeValue storageResponseDecoder value of
        Ok response ->
            if not response.ok then
                model

            else if String.startsWith "study-draft:" response.id then
                if Just (String.dropLeft 12 response.id) == draftKey model then
                    case Decode.decodeValue (Decode.field "value" Study.draftDecoder) response.value of
                        Ok draft ->
                            { model | study = resumable model.clock draft }

                        Err _ ->
                            model

                else
                    model

            else if response.id == "attempts" then
                -- The progress store holds both finished attempts and review cards.
                case Decode.decodeValue (Decode.list (Decode.oneOf [ Decode.map Just Study.attemptDecoder, Decode.succeed Nothing ])) response.value of
                    Ok attempts ->
                        { model
                            | attempts = List.filterMap identity attempts
                            , reviews =
                                Decode.decodeValue (Decode.list (Decode.oneOf [ Decode.map Just Review.entryDecoder, Decode.succeed Nothing ])) response.value
                                    |> Result.withDefault []
                                    |> List.filterMap identity
                                    |> List.map (\entry -> ( Review.entryKey entry.work entry.passage, entry ))
                                    |> Dict.fromList
                        }

                    Err _ ->
                        model

            else if response.id == "review-settings" then
                case Decode.decodeValue (Decode.at [ "value", "newPerDay" ] Decode.int) response.value of
                    Ok newPerDay ->
                        { model | newPerDay = newPerDay }

                    Err _ ->
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
                    Ok ( entry, raw, units ) ->
                        useCachedCorpus entry raw units model

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


installCorpus : Bool -> ManifestEntry -> Corpus -> Model -> Model
installCorpus loadedFromNetwork entry corpus model =
    { model
        | notice = Nothing
        , activeEntry = Just entry
        , corpus = corpus
        , corpusReady = True
        , corpusLoadedFromNetwork = model.corpusLoadedFromNetwork || loadedFromNetwork
        , sentenceIndex = 0
        , study = Study.emptyDraft
        , popupWord = Nothing
        , readerGloss = Nothing
        , readerRevealed = Set.empty
    }


{-| Opens the first passage whose citation starts with `prefix` (`1` = chapter 1, `1.2` = 1:2), in the reader or
study view, whichever is showing.
-}
jumpToCitation : String -> Model -> ( Model, Cmd Msg )
jumpToCitation prefix model =
    let
        wanted =
            Passage.parts prefix

        target =
            model.corpus.sentences
                |> List.indexedMap Tuple.pair
                |> List.filter (\( _, passage ) -> List.take (List.length wanted) (Passage.parts passage.id) == wanted)
                |> List.head
                |> Maybe.map Tuple.first
    in
    case target of
        Just index ->
            if model.screen == ReaderScreen then
                ( { model | sentenceIndex = index, readerGloss = Nothing }, scrollToSentence index )

            else
                ( moveToSentence index (browsing model), Cmd.none )

        Nothing ->
            ( { model | notice = Just ("No passage " ++ prefix ++ " in " ++ workTitle model ++ ".") }, Cmd.none )


{-| `1:2`, `1 2`, or `1,2` typed into the go-to box -> `1.2`.
-}
normalizeCitation : String -> String
normalizeCitation typed =
    typed
        |> String.trim
        |> String.map
            (\char ->
                if char == ':' || char == ' ' || char == ',' then
                    '.'

                else
                    char
            )
        |> String.split "."
        |> List.filter (not << String.isEmpty)
        |> String.join "."


{-| The current passage's citation (`1.2`), which keys drafts, attempts, review cards, and URLs.
-}
currentRef : Model -> String
currentRef model =
    (currentSentence model).id


{-| The current passage's display citation (`1:2`, `1.1.1`).
-}
currentLabel : Model -> String
currentLabel model =
    (currentSentence model).verse


indexOfRef : String -> Model -> Maybe Int
indexOfRef ref model =
    model.corpus.sentences
        |> List.indexedMap Tuple.pair
        |> List.filter (\( _, passage ) -> passage.id == ref)
        |> List.head
        |> Maybe.map Tuple.first


{-| Choosing a passage by hand leaves today's review queue.
-}
browsing : Model -> Model
browsing model =
    { model | queueMode = False, queueDone = False }


{-| After a graded passage: the next sentence in today's queue, or in text order when browsing.
-}
advance : Model -> Model
advance model =
    if model.queueMode then
        case todayQueue model |> Maybe.andThen (\today -> List.head (today.due ++ today.new)) of
            Just passage ->
                moveToSentence (indexOfRef passage model |> Maybe.withDefault model.sentenceIndex) { model | queueDone = False }

            Nothing ->
                { model | queueDone = True, popupWord = Nothing, activeModule = Nothing }

    else if model.sentenceIndex < List.length model.corpus.sentences - 1 then
        moveToSentence (model.sentenceIndex + 1) model

    else
        model


todayQueue : Model -> Maybe Review.Queue
todayQueue model =
    model.activeEntry
        |> Maybe.map (\entry -> Review.queue model.clock model.newPerDay entry.id (List.map .id model.corpus.sentences) model.reviews)


moveToSentence : Int -> Model -> Model
moveToSentence sentenceIndex model =
    if sentenceIndex < 0 || sentenceIndex >= List.length model.corpus.sentences then
        model

    else
        { model
            | screen = WorkspaceScreen
            , sentenceIndex = sentenceIndex
            , popupWord = Nothing
            , historyOpen = False
            , historyAttempt = Nothing
            , notice = Nothing
        }


storageGetAll : String -> String -> Cmd msg
storageGetAll requestId store =
    storageRequest
        (Encode.object
            [ ( "id", Encode.string requestId )
            , ( "operation", Encode.string "getAll" )
            , ( "store", Encode.string store )
            ]
        )


storageClear : String -> String -> Cmd msg
storageClear requestId store =
    storageRequest
        (Encode.object
            [ ( "id", Encode.string requestId )
            , ( "operation", Encode.string "clear" )
            , ( "store", Encode.string store )
            ]
        )


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


moduleMode : ModuleId -> ModuleSettings -> ModuleMode
moduleMode moduleId settings =
    case moduleId of
        GlossModule ->
            settings.gloss

        LiteralModule ->
            settings.literal

        ProseModule ->
            settings.prose


setModuleMode : ModuleId -> ModuleMode -> ModuleSettings -> ModuleSettings
setModuleMode moduleId mode settings =
    case moduleId of
        GlossModule ->
            { settings | gloss = mode }

        LiteralModule ->
            { settings | literal = mode }

        ProseModule ->
            { settings | prose = mode }


enabledModules : ModuleSettings -> List ModuleId
enabledModules settings =
    [ GlossModule, LiteralModule, ProseModule ]
        |> List.filter (\moduleId -> moduleMode moduleId settings /= ModuleOff)


moduleKey : ModuleId -> String
moduleKey moduleId =
    case moduleId of
        GlossModule ->
            "gloss"

        LiteralModule ->
            "literal"

        ProseModule ->
            "prose"


moduleFromKey : String -> Maybe ModuleId
moduleFromKey key =
    case key of
        "gloss" ->
            Just GlossModule

        "literal" ->
            Just LiteralModule

        "prose" ->
            Just ProseModule

        _ ->
            Nothing


moduleName : ModuleId -> String
moduleName moduleId =
    case moduleId of
        GlossModule ->
            "Glosses"

        LiteralModule ->
            "Literal translation"

        ProseModule ->
            "Prose translation"


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
    -- Title, counts, citation, and passages default so entries cached by earlier builds still decode.
    Decode.map3 (\entry unitsPath passages -> entry unitsPath passages)
        (Decode.map7 ManifestEntry
        (Decode.field "id" Decode.string)
        (Decode.oneOf [ Decode.field "title" Decode.string, Decode.field "id" Decode.string ])
        (Decode.field "path" Decode.string)
        (Decode.oneOf [ Decode.field "sentenceCount" Decode.int, Decode.succeed 0 ])
        (Decode.oneOf [ Decode.field "tokenCount" Decode.int, Decode.succeed 0 ])
        (Decode.field "source" corpusSourceDecoder)
            (Decode.oneOf [ Decode.field "citation" (Decode.map Just Sources.decoder), Decode.succeed Nothing ])
        )
        (Decode.oneOf [ Decode.field "unitsPath" Decode.string, Decode.succeed "" ])
        (Decode.oneOf [ Decode.field "passages" (Decode.list Decode.string), Decode.succeed [] ])


storageResponseDecoder : Decode.Decoder StorageResponse
storageResponseDecoder =
    Decode.map3 StorageResponse
        (Decode.field "id" Decode.string)
        (Decode.field "ok" Decode.bool)
        (Decode.field "value" Decode.value)


cachedCorpusDecoder : Decode.Decoder ( ManifestEntry, String, String )
cachedCorpusDecoder =
    Decode.map3 (\entry raw units -> ( entry, raw, units ))
        (Decode.field "entry" manifestEntryDecoder)
        (Decode.field "raw" Decode.string)
        (Decode.oneOf [ Decode.field "units" Decode.string, Decode.succeed "" ])


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
          , placeholders = []
          }
        ]
    }


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


handleShortcut : String -> Model -> ( Model, Cmd Msg )
handleShortcut key model =
    case ( model.screen, key ) of
        ( WorkspaceScreen, "ArrowLeft" ) ->
            ( moveToSentence (model.sentenceIndex - 1) (browsing model), Cmd.none )

        ( WorkspaceScreen, "k" ) ->
            ( moveToSentence (model.sentenceIndex - 1) (browsing model), Cmd.none )

        ( WorkspaceScreen, "ArrowRight" ) ->
            ( moveToSentence (model.sentenceIndex + 1) (browsing model), Cmd.none )

        ( WorkspaceScreen, "j" ) ->
            ( moveToSentence (model.sentenceIndex + 1) (browsing model), Cmd.none )

        ( ReaderScreen, "j" ) ->
            updateModel (ReaderStep 1) model

        ( ReaderScreen, "ArrowRight" ) ->
            updateModel (ReaderStep 1) model

        ( ReaderScreen, "k" ) ->
            updateModel (ReaderStep -1) model

        ( ReaderScreen, "ArrowLeft" ) ->
            updateModel (ReaderStep -1) model

        ( WorkspaceScreen, "Escape" ) ->
            if model.historyOpen then
                ( { model | historyOpen = False, historyAttempt = Nothing }, Cmd.none )

            else if model.popupWord /= Nothing then
                ( { model | popupWord = Nothing }, Cmd.none )

            else
                ( { model | activeModule = Nothing }, Cmd.none )

        ( ReaderScreen, "Escape" ) ->
            if model.readerGloss /= Nothing then
                ( { model | readerGloss = Nothing }, Cmd.none )

            else
                ( { model | screen = WorkspaceScreen }, Cmd.none )

        _ ->
            ( model, Cmd.none )



-- ROUTING


routeWork : Route -> Maybe String
routeWork route =
    case route of
        Route.Study work _ ->
            Just work

        Route.Reader work _ ->
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



-- SWIPING


swipeThreshold : Float
swipeThreshold =
    60


followSwipe : Float -> Float -> Float -> Swipe -> Swipe
followSwipe x y time swipe =
    let
        dx =
            x - swipe.startX

        dy =
            y - swipe.startY
    in
    case swipe.axis of
        Undecided ->
            if max (abs dx) (abs dy) < 10 then
                swipe

            else if time - swipe.startTime > 500 || abs dx < abs dy * 1.2 then
                -- A slow start is a long press selecting text; a steep one is a scroll.
                { swipe | axis = Vertical }

            else
                { swipe | axis = Horizontal, dx = dx }

        Horizontal ->
            { swipe | dx = dx }

        Vertical ->
            swipe


{-| Touch handlers and the finger-following offset for a swipeable passage. `atStart` and `atEnd` damp the offset
when there is no passage in that direction.
-}
swipeAttributes : Model -> Bool -> Bool -> List (Html.Attribute Msg)
swipeAttributes model atStart atEnd =
    let
        touchAt field =
            Decode.at [ "touches", "0", field ] Decode.float

        single toMsg =
            Decode.at [ "touches", "length" ] Decode.int
                |> Decode.andThen
                    (\count ->
                        if count == 1 then
                            Decode.map3 toMsg (touchAt "clientX") (touchAt "clientY") (Decode.field "timeStamp" Decode.float)

                        else
                            Decode.succeed SwipeEnd
                    )

        offset =
            case model.swipe of
                Just swipe ->
                    if swipe.axis == Horizontal then
                        if (swipe.dx > 0 && atStart) || (swipe.dx < 0 && atEnd) then
                            swipe.dx * 0.12

                        else
                            swipe.dx * 0.4

                    else
                        0

                Nothing ->
                    0
    in
    [ class "is-swipeable"
    , classList [ ( "is-swiping", offset /= 0 ) ]
    , on "touchstart" (single SwipeStart)
    , on "touchmove" (single SwipeMove)
    , on "touchend" (Decode.succeed SwipeEnd)
    , on "touchcancel" (Decode.succeed SwipeEnd)
    ]
        ++ (if offset == 0 then
                []

            else
                [ style "transform" ("translateX(" ++ String.fromFloat offset ++ "px)") ]
           )



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


measureReader : Int -> Model -> Cmd Msg
measureReader generation model =
    Task.map2 Tuple.pair
        (Dom.getElement readerScrollId)
        (model.corpus.sentences |> List.indexedMap (\index _ -> Dom.getElement (sentenceElementId index)) |> Task.sequence)
        |> Task.attempt (ReaderMeasured generation)


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
    Task.map2 Tuple.pair
        (fetchText entry.path)
        (if String.isEmpty entry.unitsPath then
            Task.succeed ""

         else
            fetchText entry.unitsPath
        )
        |> Task.attempt (GotCorpus entry)


fetchText : String -> Task.Task Http.Error String
fetchText path =
    Http.task
        { method = "GET"
        , headers = [ Http.header "Cache-Control" "no-cache" ]
        , url = "/preload/" ++ path
        , body = Http.emptyBody
        , resolver =
            Http.stringResolver
                (\response ->
                    case response of
                        Http.GoodStatus_ _ body ->
                            Ok body

                        Http.BadStatus_ metadata _ ->
                            Err (Http.BadStatus metadata.statusCode)

                        Http.BadUrl_ url ->
                            Err (Http.BadUrl url)

                        Http.Timeout_ ->
                            Err Http.Timeout

                        Http.NetworkError_ ->
                            Err Http.NetworkError
                )
        , timeout = Nothing
        }


{-| A work's sentences regrouped into its canonical passages; works without a passages file keep their sentences.
-}
parseWork : ManifestEntry -> String -> String -> Result String Corpus
parseWork entry raw units =
    Conllu.parse entry.source raw
        |> Result.andThen
            (\corpus ->
                if String.isEmpty units then
                    Ok corpus

                else
                    Decode.decodeString Passage.unitsDecoder units
                        |> Result.mapError Decode.errorToString
                        |> Result.map (\decoded -> Passage.fromUnits decoded corpus)
            )


handleFetchedCorpus : ManifestEntry -> Result Http.Error ( String, String ) -> Model -> ( Model, Cmd Msg )
handleFetchedCorpus entry result model =
    case result of
        Ok ( raw, units ) ->
            case parseWork entry raw units of
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
                                            , ( "units", Encode.string units )
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


useCachedCorpus : ManifestEntry -> String -> String -> Model -> Model
useCachedCorpus entry raw units model =
    case ( model.requestedWork == Just entry.id && not model.corpusReady, parseWork entry raw units ) of
        ( True, Ok corpus ) ->
            installCorpus False entry corpus model

        _ ->
            model


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
                useCachedCorpus entry raw "" model

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
        , ( "citation", entry.citation |> Maybe.map Sources.encode |> Maybe.withDefault Encode.null )
        , ( "unitsPath", Encode.string entry.unitsPath )
        , ( "passages", Encode.list Encode.string entry.passages )
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
                , span [ class "reader-position" ] [ text (currentLabel model ++ " · " ++ String.fromInt (model.sentenceIndex + 1) ++ " / " ++ String.fromInt total) ]
                ]
            , viewCitationPicker model
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
            [ article ([ class "reader-text", attribute "lang" "grc" ] ++ swipeAttributes model (model.sentenceIndex == 0) (model.sentenceIndex >= total - 1))
                (List.indexedMap (viewReaderSentence model) model.corpus.sentences)
            , div [ class "reader-end" ] [ text ("End of " ++ workTitle model ++ " in this edition."), activeSources model ]
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
            , attribute "aria-label" (sentence.verse ++ ": " ++ (if revealed then "hide" else "show") ++ " translation")
            , attribute "aria-expanded" (boolString revealed)
            ]
            [ text sentence.verse ]
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
    header [ id appHeaderId, class "app-header" ]
        [ button [ class "brand-button", type_ "button", onClick ShowLibrary, attribute "aria-label" "Aristos library" ]
            [ span [ class "brand-mark", attribute "aria-hidden" "true" ] [ text "Α" ]
            , span [ class "brand-word" ] [ text "Aristos" ]
            ]
        , nav [ class "global-nav", attribute "aria-label" "Primary navigation" ]
            (navButton "Library" ShowLibrary (model.screen == LibraryScreen)
                :: (case model.activeEntry of
                        Just entry ->
                            [ navButton "Read" (Navigate (Route.Reader entry.id (Just (currentRef model)))) False
                            , navButton "Study" (StudyToday entry) (List.member model.screen [ WorkspaceScreen, SettingsScreen ])
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

        details =
            [ entry.source.name, entry.source.license ]
                |> List.filter (not << String.isEmpty)
                |> String.join " · "

        today =
            Review.queue model.clock model.newPerDay entry.id entry.passages model.reviews
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
            , Sources.view entry.citation
            , div [ class "pack-footer" ]
                [ div [ class "pack-counts" ]
                    [ span [ class "queue-counts" ]
                        [ strongText (String.fromInt (List.length today.due) ++ " due")
                        , text (" · " ++ String.fromInt (List.length today.new) ++ " new today")
                        ]
                    , span [ class "muted" ] [ text (String.fromInt (List.length entry.passages) ++ " " ++ plural (List.length entry.passages) "passage" "passages" ++ " · " ++ String.fromInt entry.tokenCount ++ " tokens") ]
                    ]
                , div [ class "button-row" ]
                    [ button [ class "secondary-button", type_ "button", disabled isLoading, onClick (Navigate (Route.Reader entry.id Nothing)) ] [ text "Read" ]
                    , button [ class "primary-button", type_ "button", disabled isLoading, onClick (StudyToday entry) ]
                        [ text
                            (if isLoading then
                                "Loading…"

                             else
                                "Study today →"
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


activeSources : Model -> Html Msg
activeSources model =
    Sources.view (Maybe.andThen .citation model.activeEntry)


workTitle : Model -> String
workTitle model =
    model.activeEntry
        |> Maybe.map .title
        |> Maybe.withDefault model.corpus.source.name


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


strongText : String -> Html msg
strongText content =
    Html.strong [] [ text content ]


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
            , placeholders = []
            }


sentenceReference : Sentence -> String
sentenceReference sentence =
    sentence.verse


getAt : Int -> List a -> Maybe a
getAt index items =
    if index < 0 then
        Nothing

    else
        items |> List.drop index |> List.head


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


boolString : Bool -> String
boolString value =
    if value then
        "true"

    else
        "false"


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

            ReaderScreen ->
                viewReader model
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
                [ viewPresetCard model.preset ReadPreset "Read" "Glosses only, one word at a time." "≈ 4 min / passage"
                , viewPresetCard model.preset AssistedPreset "Assisted" "Glosses and a prose translation." "≈ 8 min / passage"
                , viewPresetCard model.preset IntensivePreset "Intensive" "Glosses and both translations." "≈ 12 min / passage"
                , viewPresetCard model.preset CustomPreset "Custom" "Your own choice of tools." "Variable"
                ]
            ]
        , section [ class "module-settings" ]
            [ viewModuleSetting model GlossModule "Glosses" "Gloss words one at a time from the word popup, then compare with the imported gloss." (String.fromInt coverage.glossed ++ " of " ++ String.fromInt coverage.tokens ++ " words") (provenance ++ " · imported")
            , viewModuleSetting model LiteralModule "Literal translation" "Expose the structure in your own words, then compare." (String.fromInt coverage.literal ++ " of " ++ String.fromInt coverage.sentences ++ " sentences") (provenance ++ " · aligned reference")
            , viewModuleSetting model ProseModule "Prose translation" "State the meaning naturally, then compare." (String.fromInt coverage.prose ++ " of " ++ String.fromInt coverage.sentences ++ " sentences") (provenance ++ " · aligned reference")
            ]
        , viewProgress model
        ]


viewProgress : Model -> Html Msg
viewProgress model =
    let
        summary =
            Study.stats model.attempts
    in
    section [ class "progress-settings" ]
        [ label [ class "new-per-day" ]
            [ span [] [ text "New passages per day" ]
            , select [ onInput SetNewPerDay ]
                (List.map
                    (\count -> option [ value (String.fromInt count), selected (count == model.newPerDay) ] [ text (String.fromInt count) ])
                    [ 3, 5, 10, 15, 20, 30 ]
                )
            , span [ class "muted" ] [ text "Reviews that are due are never capped." ]
            ]
        , div [ class "progress-heading" ]
            [ h2 [] [ text "Your progress" ]
            , span [ class "muted" ] [ text "Saved only in this browser." ]
            ]
        , div [ class "progress-stats" ]
            [ viewStat (String.fromInt summary.attempts) "graded attempts"
            , viewStat (String.fromInt summary.judged) "answers marked"
            , viewStat (percent summary.right summary.judged) "marked right"
            , viewStat (percent summary.unassistedRight summary.unassistedJudged) "right without reveals"
            ]
        , if List.isEmpty summary.struggles then
            p [ class "muted" ] [ text "Words you mark wrong will be listed here." ]

          else
            div [ class "struggles" ]
                [ h3 [] [ text "Words you miss most" ]
                , div [ class "struggle-list", attribute "lang" "grc" ]
                    (List.map
                        (\stat ->
                            span [ class "struggle" ]
                                [ text stat.lemma
                                , span [ class "struggle-count", attribute "lang" "en" ] [ text (String.fromInt stat.wrong ++ " / " ++ String.fromInt stat.judged ++ " wrong") ]
                                ]
                        )
                        summary.struggles
                    )
                ]
        , div [ class "clear-data" ]
            (if model.confirmClear then
                [ span [] [ text "Delete all attempts, drafts, and reading positions saved in this browser?" ]
                , button [ class "danger-button", type_ "button", onClick ConfirmClearSavedData ] [ text "Delete saved data" ]
                , button [ class "secondary-button", type_ "button", onClick CancelClearSavedData ] [ text "Cancel" ]
                ]

             else
                [ button [ class "secondary-button", type_ "button", onClick ClearSavedData ] [ text "Clear saved data…" ] ]
            )
        ]


viewStat : String -> String -> Html Msg
viewStat value label =
    div [ class "progress-stat" ]
        [ span [ class "progress-value" ] [ text value ]
        , span [ class "muted" ] [ text label ]
        ]


percent : Int -> Int -> String
percent part whole =
    if whole == 0 then
        "—"

    else
        String.fromInt (round (toFloat part * 100 / toFloat whole)) ++ "%"


viewWorkspace : Model -> Html Msg
viewWorkspace model =
    let
        total =
            List.length model.corpus.sentences

        showTool =
            not model.study.submitted && not model.historyOpen && model.activeModule /= Nothing
    in
    main_ [ class "workspace-page" ]
        [ div [ class "work-context-bar" ]
            [ div [ class "context-title" ]
                [ button [ class "icon-button", type_ "button", onClick ShowLibrary, attribute "aria-label" "Back to library" ] [ text "←" ]
                , div [] [ span [ class "context-work" ] [ text (workTitle model) ] ]
                ]
            , viewQueueStatus model
            , div [ class "context-actions" ]
                [ div [ class "passage-nav" ]
                    [ button [ class "icon-button", type_ "button", onClick PreviousSentence, disabled (model.sentenceIndex == 0), attribute "aria-label" "Previous passage (← or k)" ] [ text "‹" ]
                    , viewCitationPicker model
                    , button [ class "icon-button", type_ "button", onClick NextSentence, disabled (model.sentenceIndex >= total - 1), attribute "aria-label" "Next passage (→ or j)" ] [ text "›" ]
                    ]
                ]
            ]
        , div [ classList [ ( "workspace-grid", True ), ( "has-workbench", showTool ) ] ]
            [ if model.queueDone then
                viewQueueDone model

              else if model.historyOpen then
                viewHistory model

              else if model.study.submitted then
                viewGrading model

              else
                viewStudyStage model
            , if showTool then
                viewToolPanel model

              else
                text ""
            ]
        , if model.queueDone then
            text ""

          else
            viewStudyFooter model
        ]


currentAttempts : Model -> List Study.Attempt
currentAttempts model =
    case model.activeEntry of
        Just entry ->
            Study.passageAttempts entry.id (currentRef model) model.attempts

        Nothing ->
            []


{-| The way into the passage's history; absent until the passage has been graded once.
-}
viewHistoryLink : Model -> Html Msg
viewHistoryLink model =
    let
        count =
            List.length (currentAttempts model)
    in
    if count == 0 then
        text ""

    else
        button [ class "history-link", type_ "button", onClick OpenHistory ]
            [ text (String.fromInt count ++ " past " ++ plural count "attempt" "attempts" ++ " →") ]


{-| Every finished attempt at the passage, newest first, each compared with the one before it.
-}
viewHistory : Model -> Html Msg
viewHistory model =
    let
        attempts =
            currentAttempts model

        olderOf =
            List.drop 1 (List.map Just attempts) ++ [ Nothing ]

        oldestFirst =
            List.reverse attempts

        missedEveryTime =
            if List.length attempts < 2 then
                []

            else
                attempts
                    |> List.head
                    |> Maybe.map Study.missed
                    |> Maybe.withDefault []
                    |> List.filter (\item -> List.all (\attempt -> List.any (\other -> other.key == item.key) (Study.missed attempt)) attempts)
    in
    section [ class "reading-stage history-stage" ]
        [ div [ class "history-heading" ]
            [ div []
                [ p [ class "eyebrow" ] [ text (workTitle model ++ " " ++ currentLabel model) ]
                , h2 [] [ text "Past attempts" ]
                ]
            , button [ class "secondary-button", type_ "button", onClick CloseHistory ] [ text "← Back to current attempt" ]
            ]
        , if List.isEmpty attempts then
            p [ class "muted" ] [ text "No past attempts at this passage yet." ]

          else
            text ""
        , if List.length attempts < 2 then
            text ""

          else
            div [ class "history-trend" ]
                [ p []
                    [ span [ class "muted" ] [ text "Right, oldest to newest: " ]
                    , strongText (oldestFirst |> List.map (Study.tally >> .right >> String.fromInt) |> String.join " → ")
                    ]
                , p []
                    [ span [ class "muted" ] [ text "Wrong, oldest to newest: " ]
                    , strongText (oldestFirst |> List.map (Study.tally >> .wrong >> String.fromInt) |> String.join " → ")
                    ]
                , if List.isEmpty missedEveryTime then
                    text ""

                  else
                    p [] [ span [ class "muted" ] [ text "Missed every time: " ], viewItemChips False missedEveryTime ]
                ]
        , Html.ol [ class "history-list" ] (List.map2 (viewHistoryEntry model) attempts olderOf)
        ]


viewHistoryEntry : Model -> Study.Attempt -> Maybe Study.Attempt -> Html Msg
viewHistoryEntry model attempt older =
    let
        counts =
            Study.tally attempt

        missed =
            Study.missed attempt

        selected =
            model.historyAttempt == Just attempt.finishedAt

        change label now before =
            if now == before then
                Nothing

            else if now > before then
                Just ("+" ++ String.fromInt (now - before) ++ " " ++ label)

            else
                Just ("−" ++ String.fromInt (before - now) ++ " " ++ label)

        missedKeys =
            List.map .key missed
    in
    Html.li [ classList [ ( "history-entry", True ), ( "is-selected", selected ) ] ]
        [ button [ class "history-summary", type_ "button", onClick (SelectHistoryAttempt attempt.finishedAt), attribute "aria-expanded" (boolString selected) ]
            [ span [ class "history-date" ] [ text (formatDate model.zone attempt.finishedAt) ]
            , span [ class "history-counts" ]
                [ span [ class "count-right" ] [ text (String.fromInt counts.right ++ " right") ]
                , span [ class "count-wrong" ] [ text (String.fromInt counts.wrong ++ " wrong") ]
                , if counts.unmarked == 0 then
                    text ""

                  else
                    span [ class "muted" ] [ text (String.fromInt counts.unmarked ++ " unmarked") ]
                ]
            , case older of
                Just previous ->
                    let
                        before =
                            Study.tally previous
                    in
                    span [ class "history-change" ]
                        [ text
                            (case List.filterMap identity [ change "right" counts.right before.right, change "wrong" counts.wrong before.wrong ] of
                                [] ->
                                    "Same as the attempt before"

                                changes ->
                                    String.join ", " changes ++ " since the attempt before"
                            )
                        ]

                Nothing ->
                    span [ class "history-change" ] [ text "First attempt" ]
            ]
        , div [ class "history-missed" ]
            (if List.isEmpty missed then
                [ span [ class "muted" ] [ text "Nothing marked wrong." ] ]

             else
                [ span [ class "muted" ] [ text "Missed: " ], viewItemChips False missed ]
            )
        , case older of
            Just previous ->
                let
                    previousMissed =
                        Study.missed previous

                    newlyMissed =
                        List.filter (\item -> not (List.any (\other -> other.key == item.key) previousMissed)) missed

                    recovered =
                        List.filter (\item -> not (List.member item.key missedKeys)) previousMissed
                in
                div [ class "history-missed" ]
                    [ if List.isEmpty newlyMissed then
                        text ""

                      else
                        span [] [ span [ class "muted" ] [ text "Newly missed: " ], viewItemChips False newlyMissed ]
                    , if List.isEmpty recovered then
                        text ""

                      else
                        span [] [ span [ class "muted" ] [ text "No longer missed: " ], viewItemChips True recovered ]
                    ]

            Nothing ->
                text ""
        , if selected then
            div [ class "history-detail" ] (List.map viewHistoryItem attempt.items)

          else
            text ""
        ]


viewItemChips : Bool -> List Study.Item -> Html Msg
viewItemChips recovered items =
    span [ classList [ ( "history-chips", True ), ( "is-recovered", recovered ) ] ] (List.map (\item -> span [ class "history-chip", attribute "lang" (itemLang item) ] [ text (itemLabel item) ]) items)


viewHistoryItem : Study.Item -> Html Msg
viewHistoryItem item =
    div [ classList [ ( "history-item", True ), ( "is-right", item.mark == Just True ), ( "is-wrong", item.mark == Just False ) ] ]
        [ span [ class "history-item-label", attribute "lang" (itemLang item) ] [ text (itemLabel item) ]
        , span [ class "interlinear-reference" ]
            [ text
                (if item.kind == Study.WordItem then
                    displayGloss item.reference

                 else
                    item.reference
                )
            ]
        , span [ classList [ ( "interlinear-guess", True ), ( "is-empty", String.isEmpty (String.trim item.guess) ) ] ]
            [ text
                (if String.isEmpty (String.trim item.guess) then
                    "—"

                 else
                    item.guess
                )
            ]
        , span [ class "history-mark" ]
            [ text
                (case item.mark of
                    Just True ->
                        "✓ right"

                    Just False ->
                        "✗ wrong"

                    Nothing ->
                        "unmarked"
                )
            , if item.revealedEarly then
                span [ class "item-note" ] [ text "revealed" ]

              else
                text ""
            ]
        ]


itemLabel : Study.Item -> String
itemLabel item =
    case item.kind of
        Study.WordItem ->
            item.form

        Study.LiteralItem ->
            "Literal translation"

        Study.ProseItem ->
            "Prose translation"


itemLang : Study.Item -> String
itemLang item =
    if item.kind == Study.WordItem then
        "grc"

    else
        "en"


formatDate : Time.Zone -> Int -> String
formatDate zone millis =
    let
        time =
            Time.millisToPosix millis

        twoDigits number =
            String.padLeft 2 '0' (String.fromInt number)

        month =
            case Time.toMonth zone time of
                Time.Jan ->
                    "Jan"

                Time.Feb ->
                    "Feb"

                Time.Mar ->
                    "Mar"

                Time.Apr ->
                    "Apr"

                Time.May ->
                    "May"

                Time.Jun ->
                    "Jun"

                Time.Jul ->
                    "Jul"

                Time.Aug ->
                    "Aug"

                Time.Sep ->
                    "Sep"

                Time.Oct ->
                    "Oct"

                Time.Nov ->
                    "Nov"

                Time.Dec ->
                    "Dec"
    in
    String.fromInt (Time.toDay zone time)
        ++ " "
        ++ month
        ++ " "
        ++ String.fromInt (Time.toYear zone time)
        ++ ", "
        ++ twoDigits (Time.toHour zone time)
        ++ ":"
        ++ twoDigits (Time.toMinute zone time)


{-| Swiping is off while a word popup is open, so gestures inside it (or on its backdrop) never change passage.
-}
passageSwipe : Model -> List (Html.Attribute Msg)
passageSwipe model =
    if model.popupWord == Nothing then
        swipeAttributes model (model.sentenceIndex == 0) (model.sentenceIndex >= List.length model.corpus.sentences - 1)

    else
        []


viewStudyStage : Model -> Html Msg
viewStudyStage model =
    let
        sentence =
            currentSentence model
    in
    section [ class "reading-stage" ]
        [ viewHistoryLink model
        , p [ class "reading-instruction" ]
            [ text "Tap a word to gloss it. "
            , span [] [ text "Answers stay hidden until you reveal them or submit." ]
            ]
        , div ([ class "greek-passage study-passage", attribute "lang" "grc" ] ++ passageSwipe model)
            (List.concat (List.indexedMap (viewStudyToken model) sentence.tokens))
        , div [ class "source-line" ]
            [ span [] [ text model.corpus.source.edition ]
            , span [] [ text (String.fromInt (List.length (List.filter Study.isWordToken sentence.tokens)) ++ " words") ]
            ]
        , activeSources model
        , viewToolTray model
        ]


{-| Punctuation is shown attached to the preceding word and is never a study target.
-}
viewStudyToken : Model -> Int -> CorpusToken -> List (Html Msg)
viewStudyToken model position token =
    if not (Study.isWordToken token) then
        [ span [ class "study-punctuation" ] [ text token.form ] ]

    else
        let
            key =
                Study.wordKey token.id

            guessed =
                Dict.get token.id model.study.glosses |> Maybe.map (not << String.isEmpty << String.trim) |> Maybe.withDefault False

            open =
                model.popupWord == Just token.id
        in
        [ if position == 0 then
            text ""

          else
            text " "
        , span [ id (tokenElementId token.id), class "study-token-wrap" ]
            [ button
                [ classList
                    [ ( "study-token", True )
                    , ( "has-guess", guessed )
                    , ( "is-revealed", Set.member key model.study.revealed )
                    , ( "is-open", open )
                    ]
                , type_ "button"
                , onClick
                    (if open then
                        ClosePopup

                     else
                        OpenWordPopup token.id
                    )
                , attribute "aria-expanded" (boolString open)
                ]
                [ text token.form ]
            , if open then
                -- The backdrop only shows on phones, where the popup is a sheet over the footer and navigation.
                span [ class "popup-backdrop", onClick ClosePopup, attribute "aria-hidden" "true" ] []

              else
                text ""
            , if open then
                viewWordPopup model token

              else
                text ""
            ]
        ]


viewWordPopup : Model -> CorpusToken -> Html Msg
viewWordPopup model token =
    let
        placement =
            Maybe.withDefault { above = False, shift = 0, maxHeight = 0 } model.popupPlacement

        -- Custom properties need a style attribute; Elm's `style` cannot set them.
        placementStyle =
            "--popup-shift: "
                ++ String.fromFloat placement.shift
                ++ "px;"
                ++ (if placement.maxHeight > 0 then
                        " --popup-max-height: " ++ String.fromFloat placement.maxHeight ++ "px;"

                    else
                        ""
                   )
    in
    div
        [ id popupElementId
        , classList
            [ ( "word-popup", True )
            , ( "is-above", placement.above )
            , ( "is-measuring", model.popupPlacement == Nothing )
            ]
        , attribute "style" placementStyle
        , attribute "role" "dialog"
        , attribute "lang" "en"
        , stopPropagationOn "click" (Decode.succeed ( NoOp, True ))
        ]
        [ div [ class "popup-tabs" ]
            [ popupTabButton model WordTab "Word"
            , popupTabButton model SentenceTab "Sentence"
            , button [ class "popup-close", type_ "button", onClick ClosePopup, attribute "aria-label" "Close" ] [ text "×" ]
            ]
        , case model.popupTab of
            WordTab ->
                viewGlossField model token True

            SentenceTab ->
                div [ class "popup-sentence" ]
                    (List.map (viewTranslationField model) (translationModules model))
        ]


popupTabButton : Model -> PopupTab -> String -> Html Msg
popupTabButton model tab label =
    button [ classList [ ( "popup-tab", True ), ( "is-active", model.popupTab == tab ) ], type_ "button", onClick (SetPopupTab tab) ] [ text label ]


{-| Prose is always available in the popup; literal only when that tool is on.
-}
translationModules : Model -> List ModuleId
translationModules model =
    List.filter (\moduleId -> moduleId == ProseModule || moduleMode moduleId model.settings /= ModuleOff) [ LiteralModule, ProseModule ]


{-| One word's gloss: the learner's guess and a deliberate reveal of the reference beside it.
-}
viewGlossField : Model -> CorpusToken -> Bool -> Html Msg
viewGlossField model token showHeading =
    let
        key =
            Study.wordKey token.id

        revealed =
            Set.member key model.study.revealed
    in
    div [ class "gloss-field" ]
        [ if showHeading then
            p [ class "popup-form" ] [ span [ attribute "lang" "grc" ] [ text token.form ], span [ class "muted", attribute "lang" "grc" ] [ text token.lemma ] ]

          else
            span [ class "gloss-row-form", attribute "lang" "grc" ] [ text token.form ]
        , input
            [ class "gloss-input"
            , value (Dict.get token.id model.study.glosses |> Maybe.withDefault "")
            , onInput (StudyGloss token.id)
            , placeholder "Your gloss"
            , attribute "aria-label" ("Your gloss for " ++ token.form)
            ]
            []
        , if revealed then
            span [ class "reference-answer" ] [ text (displayGloss token.gloss) ]

          else
            button [ class "reveal-button", type_ "button", onClick (RevealItem key), attribute "title" "Revealing before submitting marks this word as assisted" ] [ text "Reveal" ]
        ]


viewTranslationField : Model -> ModuleId -> Html Msg
viewTranslationField model moduleId =
    let
        ( key, current, onChange ) =
            if moduleId == LiteralModule then
                ( Study.literalKey, model.study.literal, StudyLiteral )

            else
                ( Study.proseKey, model.study.prose, StudyProse )

        sentence =
            currentSentence model

        reference =
            if moduleId == LiteralModule then
                sentence.literalTranslation

            else
                sentence.proseTranslation
    in
    div [ class "translation-field" ]
        [ label [ class "field-label" ] [ text (moduleName moduleId) ]
        , textarea [ rows 3, value current, onInput onChange, placeholder ("Your " ++ String.toLower (moduleName moduleId)) ] []
        , if Set.member key model.study.revealed then
            p [ class "reference-answer" ] [ text reference ]

          else
            button [ class "reveal-button", type_ "button", onClick (RevealItem key), attribute "title" "Revealing before submitting marks this answer as assisted" ] [ text "Reveal" ]
        ]


displayGloss : String -> String
displayGloss gloss =
    if String.isEmpty gloss then
        "—"

    else
        String.replace "-" " " gloss


viewToolTray : Model -> Html Msg
viewToolTray model =
    let
        sentence =
            currentSentence model

        words =
            List.filter Study.isWordToken sentence.tokens

        glossed =
            List.length (List.filter (\token -> Dict.get token.id model.study.glosses |> Maybe.map (not << String.isEmpty << String.trim) |> Maybe.withDefault False) words)

        status moduleId =
            case moduleId of
                GlossModule ->
                    String.fromInt glossed ++ " of " ++ String.fromInt (List.length words) ++ " words"

                LiteralModule ->
                    draftStatus model.study.literal

                ProseModule ->
                    draftStatus model.study.prose
    in
    section [ class "activity-area" ]
        [ div [ class "activity-heading" ]
            [ p [ class "eyebrow" ] [ text "Tools" ]
            , button [ class "text-button", type_ "button", onClick ShowSettings ] [ text "Choose tools" ]
            ]
        , div [ class "activity-tray" ]
            (List.map
                (\moduleId ->
                    button
                        [ classList [ ( "activity-chip", True ), ( "is-active", model.activeModule == Just moduleId ) ]
                        , type_ "button"
                        , onClick
                            (if model.activeModule == Just moduleId then
                                CloseWorkbench

                             else
                                OpenModule moduleId
                            )
                        ]
                        [ span [ class "chip-copy" ]
                            [ strongText (moduleName moduleId)
                            , span [] [ text (status moduleId) ]
                            ]
                        ]
                )
                (enabledModules model.settings)
            )
        ]


draftStatus : String -> String
draftStatus draft =
    if String.isEmpty (String.trim draft) then
        "Not started"

    else
        "Saved"


viewToolPanel : Model -> Html Msg
viewToolPanel model =
    case model.activeModule of
        Just moduleId ->
            aside [ class "workbench" ]
                [ div [ class "workbench-heading" ]
                    [ h2 [] [ text (moduleName moduleId) ]
                    , button [ class "close-workbench", type_ "button", onClick CloseWorkbench, attribute "aria-label" "Close tool" ] [ text "×" ]
                    ]
                , case moduleId of
                    GlossModule ->
                        div [ class "gloss-list" ]
                            (List.map (\token -> viewGlossField model token False) (List.filter Study.isWordToken (currentSentence model).tokens))

                    _ ->
                        viewTranslationField model moduleId
                ]

        Nothing ->
            text ""


{-| After the checkpoint: the reference gloss above the learner's latest answer under every word, with self-marking.
-}
viewGrading : Model -> Html Msg
viewGrading model =
    let
        sentence =
            currentSentence model

        items =
            studyItems model

        itemFor key =
            List.filter (\item -> item.key == key) items |> List.head

        missed =
            model.activeEntry
                |> Maybe.map (\entry -> Study.missedLastTime entry.id (currentRef model) model.attempts)
                |> Maybe.withDefault Dict.empty

        words =
            groupWords sentence.tokens
                |> List.filterMap (\( token, suffix ) -> itemFor (Study.wordKey token.id) |> Maybe.map (\item -> ( token, suffix, item )))

        translations =
            List.filter (\item -> item.kind /= Study.WordItem) items
    in
    section [ class "reading-stage grading-stage" ]
        [ viewHistoryLink model
        , p [ class "reading-instruction" ]
            [ text "Compare each answer with the reference and mark it yourself. "
            , span [] [ text "Different wording can still be right." ]
            ]
        , div [ class "grading-legend" ]
            [ span [ class "legend-reference" ] [ text "Reference" ]
            , span [ class "legend-guess" ] [ text "Your answer" ]
            , if Dict.isEmpty missed then
                text ""

              else
                span [ class "legend-missed" ] [ text "Missed last time" ]
            ]
        , if List.isEmpty words then
            text ""

          else
            div [ class "interlinear" ]
                (List.map
                    (\( token, suffix, item ) ->
                        div [ classList [ ( "interlinear-word", True ), ( "was-missed", Dict.member item.key missed ) ] ]
                            [ span [ class "interlinear-greek", attribute "lang" "grc" ] [ text (token.form ++ suffix) ]
                            , span [ class "interlinear-reference" ] [ text (displayGloss item.reference) ]
                            , span [ classList [ ( "interlinear-guess", True ), ( "is-empty", String.isEmpty (String.trim item.guess) ) ] ]
                                [ text
                                    (if String.isEmpty (String.trim item.guess) then
                                        "—"

                                     else
                                        item.guess
                                    )
                                ]
                            , viewMarkButtons item
                            , viewItemNotes item missed
                            ]
                    )
                    words
                )
        , div [ class "grading-translations" ]
            (List.map
                (\item ->
                    div [ classList [ ( "grading-card", True ), ( "was-missed", Dict.member item.key missed ) ] ]
                        [ h3 []
                            [ text
                                (if item.kind == Study.LiteralItem then
                                    "Literal translation"

                                 else
                                    "Prose translation"
                                )
                            ]
                        , p [ class "interlinear-reference" ] [ text item.reference ]
                        , p [ classList [ ( "interlinear-guess", True ), ( "is-empty", String.isEmpty (String.trim item.guess) ) ] ]
                            [ text
                                (if String.isEmpty (String.trim item.guess) then
                                    "No answer"

                                 else
                                    item.guess
                                )
                            ]
                        , div [ class "grading-card-actions" ] [ viewMarkButtons item, viewItemNotes item missed ]
                        ]
                )
                translations
            )
        ]


viewMarkButtons : Study.Item -> Html Msg
viewMarkButtons item =
    div [ class "mark-buttons" ]
        [ button [ classList [ ( "mark-button", True ), ( "is-right", item.mark == Just True ) ], type_ "button", onClick (MarkItem item.key True), attribute "aria-label" "Mark right" ] [ text "✓" ]
        , button [ classList [ ( "mark-button", True ), ( "is-wrong", item.mark == Just False ) ], type_ "button", onClick (MarkItem item.key False), attribute "aria-label" "Mark wrong" ] [ text "✗" ]
        ]


viewItemNotes : Study.Item -> Dict String String -> Html Msg
viewItemNotes item missed =
    span [ class "item-notes" ]
        [ if item.revealedEarly then
            span [ class "item-note" ] [ text "revealed" ]

          else
            text ""
        , case Dict.get item.key missed of
            Just previous ->
                span [ class "item-note missed-note", attribute "title" ("Last time: " ++ previous) ]
                    [ text
                        ("last: "
                            ++ (if String.isEmpty (String.trim previous) then
                                    "—"

                                else
                                    previous
                               )
                        )
                    ]

            Nothing ->
                text ""
        ]


{-| Pairs each word with the punctuation that follows it.
-}
groupWords : List CorpusToken -> List ( CorpusToken, String )
groupWords tokens =
    tokens
        |> List.foldl
            (\token groups ->
                if Study.isWordToken token then
                    ( token, "" ) :: groups

                else
                    case groups of
                        ( word, suffix ) :: rest ->
                            ( word, suffix ++ token.form ) :: rest

                        [] ->
                            groups
            )
            []
        |> List.reverse


{-| In today's queue: whether this passage is a review or new, and how many passages remain.
-}
viewQueueStatus : Model -> Html Msg
viewQueueStatus model =
    case ( model.queueMode && not model.queueDone, todayQueue model ) of
        ( True, Just today ) ->
            let
                current =
                    currentRef model

                kind =
                    if List.member current today.due then
                        "Review"

                    else
                        "New"
            in
            span [ class "queue-status" ]
                [ span [ class "queue-kind" ] [ text kind ]
                , text (String.fromInt (List.length today.due + List.length today.new) ++ " left today")
                ]

        _ ->
            text ""


viewQueueDone : Model -> Html Msg
viewQueueDone model =
    let
        work =
            model.activeEntry |> Maybe.map .id |> Maybe.withDefault ""

        today =
            List.filter (\attempt -> attempt.work == work && attempt.finishedAt >= Review.startOfDay model.clock) model.attempts

        summary =
            Study.stats today

        nextDue =
            Review.dueLater model.clock work model.reviews

        -- Short relearning steps fall due while this panel is open.
        dueNow =
            todayQueue model |> Maybe.map (.due >> List.length) |> Maybe.withDefault 0
    in
    section [ class "reading-stage queue-done" ]
        [ p [ class "eyebrow" ] [ text (workTitle model) ]
        , h2 [] [ text "Done for today" ]
        , p []
            [ text
                (String.fromInt (List.length today)
                    ++ plural (List.length today) " passage" " passages"
                    ++ " graded today"
                    ++ (if summary.judged > 0 then
                            ", " ++ percent summary.right summary.judged ++ " of marked answers right."

                        else
                            "."
                       )
                )
            ]
        , p [ class "muted" ]
            [ text
                (case ( dueNow, nextDue ) of
                    ( 0, Just due ) ->
                        "Next review due in " ++ Review.intervalLabel model.clock due ++ ". New passages: up to " ++ String.fromInt model.newPerDay ++ " a day."

                    ( 0, Nothing ) ->
                        "No reviews scheduled yet. New passages: up to " ++ String.fromInt model.newPerDay ++ " a day."

                    _ ->
                        String.fromInt dueNow ++ plural dueNow " review is" " reviews are" ++ " due now."
                )
            ]
        , div [ class "button-row" ]
            (List.filterMap identity
                [ if dueNow > 0 then
                    model.activeEntry |> Maybe.map (\entry -> button [ class "primary-button", type_ "button", onClick (StudyToday entry) ] [ text "Review now →" ])

                  else
                    Nothing
                , Just (button [ class "secondary-button", type_ "button", onClick ContinueReading ] [ text "Keep going in order" ])
                , Just (button [ class "secondary-button", type_ "button", onClick ShowLibrary ] [ text "Back to library" ])
                ]
            )
        ]


{-| Finishing is choosing a rating: FSRS schedules the passage and the next one opens. Each button shows when the
passage would come back with that rating.
-}
viewRatingButtons : Model -> List Study.Item -> Html Msg
viewRatingButtons model items =
    let
        suggested =
            Review.suggestRating items

        card =
            model.activeEntry
                |> Maybe.andThen (\entry -> Dict.get (Review.entryKey entry.id (currentRef model)) model.reviews)
                |> Maybe.map .card
                |> Maybe.withDefault (Fsrs.newCard model.clock)

        outcomes =
            Review.scheduler |> Maybe.andThen (\fsrs -> Fsrs.preview fsrs model.clock card |> Result.toMaybe)

        ratingButton rating label pick =
            button
                [ classList [ ( "rating-button", True ), ( "is-suggested", rating == suggested ) ]
                , type_ "button"
                , onClick (FinishGrading rating)
                ]
                [ strongText label
                , span [ class "rating-interval" ]
                    [ text (outcomes |> Maybe.map (\all -> Review.intervalLabel model.clock (pick all).card.due) |> Maybe.withDefault "") ]
                ]
    in
    div [ class "rating-buttons" ]
        [ ratingButton Fsrs.Again "Again" .again
        , ratingButton Fsrs.Hard "Hard" .hard
        , ratingButton Fsrs.Good "Good" .good
        , ratingButton Fsrs.Easy "Easy" .easy
        ]


viewStudyFooter : Model -> Html Msg
viewStudyFooter model =
    let
        items =
            studyItems model

        marked =
            List.length (List.filter (\item -> item.mark /= Nothing) items)
    in
    footer [ id studyFooterId, class "workspace-footer" ]
        (if model.historyOpen then
            [ span [] []
            , div [ class "checkpoint-copy" ]
                [ strongText "Reviewing past attempts"
                , span [] [ text "Your current work on this passage is kept." ]
                ]
            , button [ class "checkpoint-button", type_ "button", onClick CloseHistory ] [ text "Back to current attempt →" ]
            ]

         else if model.study.submitted then
            [ button [ class "footer-side-button", type_ "button", onClick ReopenStudy ] [ text "← Keep working" ]
            , div [ class "checkpoint-copy" ]
                [ strongText (String.fromInt marked ++ " of " ++ String.fromInt (List.length items) ++ " marked")
                , span [] [ text "How well did you know it? The suggestion follows your marks." ]
                ]
            , viewRatingButtons model items
            ]

         else
            [ button [ class "footer-side-button", type_ "button", disabled (model.sentenceIndex == 0), onClick PreviousSentence ] [ text "← Previous" ]
            , div [ class "checkpoint-copy" ]
                [ strongText "Work on any section, in any order"
                , span [] [ text "Answers save automatically in this browser." ]
                ]
            , button [ class "checkpoint-button", type_ "button", onClick SubmitStudy ] [ text "Submit checkpoint →" ]
            ]
        )




{-| The passage the learner last had open in a work (positions are saved as 1-based passage indexes), or its first.
-}
savedRef : ManifestEntry -> Model -> String
savedRef entry model =
    Dict.get entry.id model.positions
        |> Maybe.andThen (\position -> getAt (position - 1) entry.passages)
        |> Maybe.withDefault (List.head entry.passages |> Maybe.withDefault "1")


{-| One select per citation level (Chapter/Verse, Book/Chapter/Section, …) and a go-to box accepting `1:2` or `1.2`.
-}
viewCitationPicker : Model -> Html Msg
viewCitationPicker model =
    let
        refs =
            List.map (.id >> Passage.parts) model.corpus.sentences

        current =
            Passage.parts (currentRef model)

        names =
            Passage.levelNames (String.contains ":" (currentLabel model)) (Passage.levels model.corpus.sentences)

        choices level =
            refs
                |> List.filter (\parts -> List.take level parts == List.take level current)
                |> List.filterMap (getAt level)
                |> List.foldl
                    (\value found ->
                        if List.member value found then
                            found

                        else
                            found ++ [ value ]
                    )
                    []

        levelSelect level name =
            label [ class "chapter-jump" ]
                [ span [] [ text name ]
                , select [ onInput (\value -> JumpToCitation (String.join "." (List.take level current ++ [ value ]))) ]
                    (List.map (\value -> option [ Html.Attributes.value value, selected (getAt level current == Just value) ] [ text value ]) (choices level))
                ]
    in
    div [ class "citation-picker" ]
        (List.indexedMap levelSelect names
            ++ [ input
                    [ class "citation-go"
                    , placeholder (if String.contains ":" (currentLabel model) then "Go to 1:2" else "Go to 1.2")
                    , attribute "aria-label" "Go to citation"
                    , on "change" (Decode.map GoToCitation (Decode.at [ "target", "value" ] Decode.string))
                    ]
                    []
               ]
        )
