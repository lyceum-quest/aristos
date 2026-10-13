module SyncTest exposing (suite)

import Dict
import Expect
import Json.Decode as Decode
import Set
import Sync
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Sync"
        [ test "the state survives storage" <|
            \_ ->
                let
                    state =
                        { account = 7
                        , cursor = 42
                        , sent = Set.fromList [ "attempt:a", "wordreview:b" ]
                        , settings = Dict.fromList [ ( "theme", { value = "\"dark\"", updatedAt = 5 } ) ]
                        }
                in
                Decode.decodeValue Sync.decodeState (Sync.encodeState state)
                    |> Expect.equal (Ok state)
        , test "a new account starts from nothing" <|
            \_ ->
                Sync.emptyState 3
                    |> Expect.equal { account = 3, cursor = 0, sent = Set.empty, settings = Dict.empty }
        , test "status lines" <|
            \_ ->
                List.map (Sync.statusText 1000000)
                    [ Sync.Synced 990000, Sync.Synced (1000000 - 5 * 60000), Sync.Offline, Sync.NeedsSupporter ]
                    |> Expect.equal [ "Synced just now", "Synced 5 min ago", "Offline: will sync when back online", "Sync is for Supporters" ]
        ]
