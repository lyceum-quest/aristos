module Sync exposing
    ( Outgoing
    , Received
    , Response
    , State
    , Status(..)
    , decodeState
    , emptyState
    , encodeState
    , request
    , statusText
    )

{-| Cross-device sync through the Lyceum account (`POST /api/sync`; see "Sync contract" in the unified Lyceum plan).

History records (attempts and word reviews) never change, so devices exchange them and keep the union; cards are
replayed from the merged history. Settings (theme, reader layers, positions, review settings, today's scope) can
change: the newest edit wins. Drafts in progress stay on their device.

The state remembers which account it belongs to, the server cursor, the history records the server already has, and
the last synced value of each setting, so only new records and changed settings are sent.

-}

import Account
import Dict exposing (Dict)
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Set exposing (Set)


type alias State =
    { account : Int
    , cursor : Int
    , sent : Set String
    , settings : Dict String Setting
    }


{-| A setting as last synced: its encoded value and when it was edited.
-}
type alias Setting =
    { value : String
    , updatedAt : Int
    }


type Status
    = NotSyncing
    | Syncing
    | Synced Int
    | Offline
    | NeedsSupporter
    | Failed


emptyState : Int -> State
emptyState account =
    { account = account, cursor = 0, sent = Set.empty, settings = Dict.empty }


{-| A record to send: history records are immutable, settings (`meta:<key>`) mutable.
-}
type alias Outgoing =
    { id : String
    , kind : String
    , mutable : Bool
    , updatedAt : Int
    , body : Encode.Value
    }


type alias Received =
    { id : String
    , kind : String
    , updatedAt : Int
    , body : Decode.Value
    }


type alias Response =
    { records : List Received
    , cursor : Int
    , more : Bool
    }


{-| One round: send `outgoing`, receive everything newer than the cursor (at most a page; `more` asks for another).
-}
request : String -> State -> List Outgoing -> (Result Http.Error Response -> msg) -> Cmd msg
request origin state outgoing toMsg =
    Http.riskyRequest
        { method = "POST"
        , headers = [ Account.clientHeader ]
        , url = origin ++ "/api/sync"
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "app", Encode.string "aristos" )
                    , ( "since", Encode.int state.cursor )
                    , ( "records", Encode.list encodeOutgoing outgoing )
                    ]
                )
        , expect = Http.expectJson toMsg responseDecoder
        , timeout = Just 30000
        , tracker = Nothing
        }


encodeOutgoing : Outgoing -> Encode.Value
encodeOutgoing record =
    Encode.object
        [ ( "id", Encode.string record.id )
        , ( "type", Encode.string record.kind )
        , ( "mutable", Encode.bool record.mutable )
        , ( "updatedAt", Encode.int record.updatedAt )
        , ( "body", record.body )
        ]


responseDecoder : Decode.Decoder Response
responseDecoder =
    Decode.map3 Response
        (Decode.field "records"
            (Decode.list
                (Decode.map4 Received
                    (Decode.field "id" Decode.string)
                    (Decode.field "type" Decode.string)
                    (Decode.field "updatedAt" Decode.int)
                    (Decode.field "body" Decode.value)
                )
            )
        )
        (Decode.field "cursor" Decode.int)
        (Decode.oneOf [ Decode.field "more" Decode.bool, Decode.succeed False ])


encodeState : State -> Encode.Value
encodeState state =
    Encode.object
        [ ( "account", Encode.int state.account )
        , ( "cursor", Encode.int state.cursor )
        , ( "sent", Encode.list Encode.string (Set.toList state.sent) )
        , ( "settings"
          , Encode.dict identity
                (\setting -> Encode.object [ ( "value", Encode.string setting.value ), ( "updatedAt", Encode.int setting.updatedAt ) ])
                state.settings
          )
        ]


decodeState : Decode.Decoder State
decodeState =
    Decode.map4 State
        (Decode.field "account" Decode.int)
        (Decode.field "cursor" Decode.int)
        (Decode.field "sent" (Decode.list Decode.string |> Decode.map Set.fromList))
        (Decode.field "settings"
            (Decode.dict (Decode.map2 Setting (Decode.field "value" Decode.string) (Decode.field "updatedAt" Decode.int)))
        )


{-| The status line, given the current time.
-}
statusText : Int -> Status -> String
statusText now status =
    case status of
        NotSyncing ->
            "Not synced yet"

        Syncing ->
            "Syncing…"

        Synced at ->
            if now - at < 60000 then
                "Synced just now"

            else if now - at < 3600000 then
                "Synced " ++ String.fromInt ((now - at) // 60000) ++ " min ago"

            else
                "Synced over an hour ago"

        Offline ->
            "Offline: will sync when back online"

        NeedsSupporter ->
            "Sync is for Supporters"

        Failed ->
            "Couldn't sync: will try again"
