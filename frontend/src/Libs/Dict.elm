module Libs.Dict exposing (all, alter, any, count, filterMap, find, findMap, from, fromIndexedList, fromListBy, fromListIndexedMap, fromListMap, fuse, getOrElse, getResult, mapBoth, mapKeys, mapValues, nonEmpty, notMember, set, updateT, zip)

import Dict exposing (Dict)
import Libs.List as List


nonEmpty : Dict k a -> Bool
nonEmpty dict =
    not (Dict.isEmpty dict)


from : comparable -> a -> Dict comparable a
from key value =
    Dict.fromList [ ( key, value ) ]


fromIndexedList : List a -> Dict Int a
fromIndexedList list =
    list |> List.indexedMap (\i a -> ( i, a )) |> Dict.fromList


fromListBy : (a -> comparable) -> List a -> Dict comparable a
fromListBy getKey list =
    list |> List.map (\item -> ( getKey item, item )) |> Dict.fromList


fromListMap : (a -> ( comparable, b )) -> List a -> Dict comparable b
fromListMap toEntity list =
    list |> List.map toEntity |> Dict.fromList


fromListIndexedMap : (Int -> a -> ( comparable, b )) -> List a -> Dict comparable b
fromListIndexedMap toEntity list =
    list |> List.indexedMap toEntity |> Dict.fromList


getOrElse : comparable -> a -> Dict comparable a -> a
getOrElse key default dict =
    dict |> Dict.get key |> Maybe.withDefault default


getResult : String -> Dict String a -> Result String a
getResult key dict =
    dict |> Dict.get key |> Result.fromMaybe ("Missing key '" ++ key ++ "'")


notMember : comparable -> Dict comparable v -> Bool
notMember key dict =
    case Dict.get key dict of
        Just _ ->
            False

        Nothing ->
            True


mapKeys : (comparable -> comparable1) -> Dict comparable a -> Dict comparable1 a
mapKeys f dict =
    dict |> Dict.toList |> List.map (\( k, v ) -> ( f k, v )) |> Dict.fromList


mapValues : (a -> b) -> Dict comparable a -> Dict comparable b
mapValues f dict =
    dict |> Dict.toList |> List.map (\( k, v ) -> ( k, f v )) |> Dict.fromList


mapBoth : (comparable -> comparable1) -> (a -> b) -> Dict comparable a -> Dict comparable1 b
mapBoth f g dict =
    dict |> Dict.toList |> List.map (\( k, v ) -> ( f k, g v )) |> Dict.fromList


any : (comparable -> v -> Bool) -> Dict comparable v -> Bool
any predicate dict =
    find predicate dict /= Nothing


all : (comparable -> v -> Bool) -> Dict comparable v -> Bool
all predicate dict =
    find (\k v -> predicate k v |> not) dict /= Nothing


find : (comparable -> v -> Bool) -> Dict comparable v -> Maybe v
find predicate dict =
    Dict.foldl
        (\k v acc ->
            case acc of
                Just _ ->
                    acc

                Nothing ->
                    if predicate k v then
                        Just v

                    else
                        Nothing
        )
        Nothing
        dict


findMap : (comparable -> a -> Maybe b) -> Dict comparable a -> Maybe b
findMap f dict =
    dict |> Dict.toList |> List.findMap (\( k, a ) -> f k a)


filterMap : (comparable -> a -> Maybe b) -> Dict comparable a -> Dict comparable b
filterMap f dict =
    dict |> Dict.toList |> List.filterMap (\( k, a ) -> f k a |> Maybe.map (\b -> ( k, b ))) |> Dict.fromList


filterZip : (comparable -> a -> Maybe b) -> Dict comparable a -> Dict comparable ( a, b )
filterZip f dict =
    dict |> Dict.toList |> List.filterMap (\( k, a ) -> f k a |> Maybe.map (\b -> ( k, ( a, b ) ))) |> Dict.fromList


count : (comparable -> a -> Bool) -> Dict comparable a -> Int
count predicate dict =
    dict
        |> Dict.foldl
            (\k v cpt ->
                if predicate k v then
                    cpt + 1

                else
                    cpt
            )
            0


updateT : comparable -> (Maybe v -> ( Maybe v, a )) -> Dict comparable v -> ( Dict comparable v, a )
updateT key transform dict =
    case transform (dict |> Dict.get key) of
        ( Just value, a ) ->
            ( dict |> Dict.insert key value, a )

        ( Nothing, a ) ->
            ( dict |> Dict.remove key, a )


alter : comparable -> (v -> v) -> Dict comparable v -> Dict comparable v
alter key transform dict =
    -- similar to update but only when key is present
    Dict.update key (Maybe.map transform) dict


set : comparable -> Maybe v -> Dict comparable v -> Dict comparable v
set key value dict =
    value |> Maybe.map (\v -> dict |> Dict.insert key v) |> Maybe.withDefault (dict |> Dict.remove key)


zip : Dict comparable b -> Dict comparable a -> Dict comparable ( a, b )
zip dict2 dict1 =
    dict1 |> Dict.toList |> List.filterMap (\( k1, v1 ) -> dict2 |> Dict.get k1 |> Maybe.map (\v2 -> ( k1, ( v1, v2 ) ))) |> Dict.fromList


fuse : (a -> a -> a) -> Dict comparable a -> Dict comparable a -> Dict comparable a
fuse mergeValue d1 d2 =
    Dict.merge Dict.insert (\k a1 a2 acc -> Dict.insert k (mergeValue a1 a2) acc) Dict.insert d1 d2 Dict.empty
