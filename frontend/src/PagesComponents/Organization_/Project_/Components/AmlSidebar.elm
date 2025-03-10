module PagesComponents.Organization_.Project_.Components.AmlSidebar exposing (Model, init, setOtherSourcesTableIdsCache, setSource, update, view)

import Components.Atoms.Icon as Icon
import Components.Molecules.Editor as Editor
import Components.Slices.PlanDialog as PlanDialog
import Conf
import DataSources.JsonMiner.JsonAdapter as JsonAdapter
import DataSources.JsonMiner.JsonSchema exposing (JsonSchema)
import DataSources.JsonMiner.Models.JsonTable as JsonTable
import Dict exposing (Dict)
import Html exposing (Html, br, button, div, h3, label, option, p, select, text)
import Html.Attributes exposing (class, disabled, for, id, name, selected, value)
import Html.Events exposing (onClick, onInput)
import Libs.Bool as Bool
import Libs.Dict as Dict
import Libs.Html exposing (extLink)
import Libs.Html.Attributes exposing (css)
import Libs.List as List
import Libs.Maybe as Maybe
import Libs.Models.HtmlId exposing (HtmlId)
import Libs.Tailwind as Tw exposing (focus)
import Libs.Tuple as Tuple
import Models.Feature as Feature
import Models.Organization as Organization
import Models.ParserError as ParserError exposing (ParserError)
import Models.Position as Position
import Models.Project.Source as Source exposing (Source)
import Models.Project.SourceId as SourceId exposing (SourceId)
import Models.Project.SourceKind as SourceKind
import Models.Project.Table exposing (Table)
import Models.Project.TableId exposing (TableId)
import Models.ProjectRef exposing (ProjectRef)
import PagesComponents.Organization_.Project_.Models exposing (AmlSidebar, AmlSidebarMsg(..), Msg(..), simplePrompt)
import PagesComponents.Organization_.Project_.Models.CursorMode exposing (CursorMode)
import PagesComponents.Organization_.Project_.Models.Erd as Erd exposing (Erd)
import PagesComponents.Organization_.Project_.Models.ErdConf exposing (ErdConf)
import PagesComponents.Organization_.Project_.Models.ErdTableLayout exposing (ErdTableLayout)
import PagesComponents.Organization_.Project_.Models.PositionHint exposing (PositionHint(..))
import PagesComponents.Organization_.Project_.Models.ShowColumns as ShowColumns
import PagesComponents.Organization_.Project_.Updates.Extra as Extra exposing (Extra)
import PagesComponents.Organization_.Project_.Updates.Table exposing (hideTable, showColumns, showTable)
import PagesComponents.Organization_.Project_.Updates.Utils exposing (setDirty, setDirtyM)
import Ports
import Services.Lenses exposing (mapAmlSidebarM, mapAmlSidebarMTM, mapErdM, mapErdMT, mapSelectedMT, setAmlSidebar, setContent, setErrors, setSelected, setUpdatedAt)
import Services.Urls as Urls
import Set exposing (Set)
import Time
import Track


type alias Model x =
    { x
        | conf : ErdConf
        , dirty : Bool
        , erd : Maybe Erd
        , cursorMode : CursorMode
        , amlSidebar : Maybe AmlSidebar
    }



-- INIT


init : Maybe SourceId -> Maybe Erd -> AmlSidebar
init sourceId erd =
    let
        selected : Maybe SourceId
        selected =
            sourceId |> Maybe.orElse (erd |> Maybe.andThen (.sources >> List.find (\s -> s.enabled && SourceKind.isUser s.kind)) |> Maybe.map .id)
    in
    { id = Conf.ids.amlSidebarDialog
    , selected = selected |> Maybe.andThen (buildSelected erd)
    , errors = []
    , otherSourcesTableIdsCache = getOtherSourcesTableIds selected erd
    }



-- UPDATE


update : Time.Posix -> ProjectRef -> AmlSidebarMsg -> Model x -> ( Model x, Extra Msg )
update now projectRef msg model =
    case msg of
        AOpen id ->
            ( model |> setAmlSidebar (Just (init id model.erd))
            , if projectRef |> Organization.canUseAml then
                Track.sourceEditorOpened model.erd |> Extra.cmd

              else
                [ Track.sourceEditorOpened model.erd, Track.planLimit Feature.aml model.erd ] |> Extra.cmdL
            )

        AClose ->
            ( model |> setAmlSidebar Nothing, Track.sourceEditorClosed model.erd |> Extra.cmd )

        AToggle ->
            ( model, Bool.cond (model.amlSidebar == Nothing) (AOpen Nothing) AClose |> AmlSidebarMsg |> Extra.msg )

        AChangeSource sourceId ->
            ( model |> mapAmlSidebarM (setSelected (sourceId |> Maybe.andThen (buildSelected model.erd))) |> setOtherSourcesTableIdsCache sourceId, Extra.none )

        AUpdateSource id content ->
            ( model |> mapErdM (Erd.mapSource id (setContent (Source.buildContent content) >> setUpdatedAt now)), Ports.getAmlSchema id content |> Extra.cmd )

        AGotSchema id length schema errors ->
            (model.erd |> Maybe.andThen (.sources >> List.findBy .id id))
                |> Maybe.map
                    (\source ->
                        let
                            editorError : String -> ParserError
                            editorError message =
                                { message = message, kind = "EditorError", level = ParserError.Error, offset = { start = 0, end = 0 }, position = { start = { line = 1, column = 1 }, end = { line = 1, column = 1 } } }
                        in
                        if source.id /= id then
                            ( model |> mapAmlSidebarM (setErrors [ editorError "Source has changed" ]), Extra.none )

                        else if String.length (Source.contentStr source) /= length then
                            ( model |> mapAmlSidebarM (setErrors [ editorError "AML has changed" ]), Extra.none )

                        else if errors |> List.any (\e -> e.level == ParserError.Error) then
                            ( model |> mapAmlSidebarM (setErrors errors), Extra.none )

                        else if schema |> Maybe.any (\s -> projectRef |> Organization.canWriteAml (List.length s.tables) |> not) then
                            ( model |> mapAmlSidebarM (setErrors [ projectRef |> PlanDialog.amlWriteError |> editorError ]), Extra.none )

                        else
                            schema |> Maybe.map (\s -> model |> updateSource now source s errors |> setDirty) |> Maybe.withDefault ( model |> mapAmlSidebarM (setErrors errors), Extra.none )
                    )
                |> Maybe.withDefault ( model |> mapAmlSidebarM (setErrors [ { message = "Source not found", kind = "EditorError", level = ParserError.Error, offset = { start = 0, end = 0 }, position = { start = { line = 1, column = 1 }, end = { line = 1, column = 1 } } } ]), Extra.none )

        ASourceUpdated id ->
            (model.erd |> Maybe.andThen (.sources >> List.findBy .id id))
                |> Maybe.map (\source -> model |> mapAmlSidebarMTM (mapSelectedMT (Tuple.mapSecondT (\old -> source |> Source.contentStr |> (\new -> ( new, Extra.new (Track.sourceRefreshed model.erd source) (( AUpdateSource source.id old, AUpdateSource source.id new ) |> Tuple.map AmlSidebarMsg) ))))) |> Extra.defaultT)
                |> Maybe.withDefault ( model, Extra.none )


updateSource : Time.Posix -> Source -> JsonSchema -> List ParserError -> Model x -> ( Model x, Extra Msg )
updateSource now source schema errors model =
    let
        tableLayouts : List ErdTableLayout
        tableLayouts =
            model.erd |> Maybe.mapOrElse (Erd.currentLayout >> .tables) []

        ( parsed, amlColumns ) =
            ( schema |> JsonAdapter.buildSchema >> (\s -> Source.setSchema s source)
            , schema.tables |> List.map (\t -> ( ( t.schema, t.table ), JsonTable.orderedColumnPaths t )) |> Dict.fromList
            )

        ( removed, bothPresent, added ) =
            List.diff .id (source.tables |> Dict.values) (parsed.tables |> Dict.values)

        otherSourcesTableIds : Set TableId
        otherSourcesTableIds =
            model.amlSidebar |> Maybe.mapOrElse .otherSourcesTableIdsCache Set.empty

        toHide : List TableId
        toHide =
            removed |> List.filterNot (\t -> Set.member t.id otherSourcesTableIds) |> List.map .id

        updated : List Table
        updated =
            bothPresent |> List.filter (\( t1, t2 ) -> t1 /= t2) |> List.map Tuple.second

        toShow : List ( TableId, Maybe PositionHint )
        toShow =
            (updated ++ added)
                |> List.filterNot (\t -> tableLayouts |> List.map .id |> List.member t.id)
                |> associateTables removed
                |> List.map
                    (\( table, previous ) ->
                        ( table.id
                        , previous
                            |> Maybe.andThen (\t -> tableLayouts |> List.findBy .id t.id)
                            |> Maybe.map (.props >> .position)
                            |> Maybe.filter (\p -> p /= Position.zeroGrid)
                            |> Maybe.map PlaceAt
                        )
                    )

        apply : List a -> (a -> Model x -> ( Model x, Extra Msg )) -> ( Model x, Extra Msg ) -> ( Model x, Extra Msg )
        apply items f m =
            items |> List.foldl (\a ( curModel, curExtra ) -> curModel |> f a |> Tuple.mapSecond (Extra.combine curExtra >> Extra.dropHistory)) m
    in
    ( model |> mapAmlSidebarM (setErrors errors) |> mapErdM (Erd.mapSource source.id (Source.updateWith parsed)), Extra.none )
        |> apply toShow (\( id, hint ) -> mapErdMT (showTable now id [] hint "aml") >> setDirtyM)
        |> apply toHide (\id -> mapErdMT (hideTable now id) >> setDirtyM)
        |> apply updated (\t -> mapErdMT (showColumns now t.id (ShowColumns.List (amlColumns |> Dict.getOrElse t.id []))) >> setDirtyM)


associateTables : List Table -> List Table -> List ( Table, Maybe Table )
associateTables removed added =
    if List.length added == 1 && List.length removed == 1 then
        added |> List.map (\t -> ( t, removed |> List.head ))

    else
        added |> List.map (\table -> ( table, Nothing ))


setSource : Maybe Source -> AmlSidebar -> AmlSidebar
setSource source model =
    model |> setSelected (source |> Maybe.map (\s -> ( s.id, s |> Source.contentStr )))


setOtherSourcesTableIdsCache : Maybe SourceId -> Model x -> Model x
setOtherSourcesTableIdsCache sourceId model =
    model |> mapAmlSidebarM (\v -> { v | otherSourcesTableIdsCache = getOtherSourcesTableIds sourceId model.erd })


buildSelected : Maybe Erd -> SourceId -> Maybe ( SourceId, String )
buildSelected erd sourceId =
    erd |> Maybe.andThen (.sources >> List.findBy .id sourceId) |> Maybe.map (\s -> ( s.id, s |> Source.contentStr ))


getOtherSourcesTableIds : Maybe SourceId -> Maybe Erd -> Set TableId
getOtherSourcesTableIds currentSourceId erd =
    case currentSourceId of
        Nothing ->
            Set.empty

        Just id ->
            erd
                |> Maybe.mapOrElse .sources []
                |> List.filterNot (\s -> s.id == id)
                |> List.concatMap (.tables >> Dict.keys)
                |> Set.fromList



-- VIEW


view : ProjectRef -> Erd -> AmlSidebar -> Html Msg
view projectRef erd model =
    let
        userSources : List Source
        userSources =
            erd.sources |> List.filter (.kind >> SourceKind.isUser)

        selectedSource : Maybe Source
        selectedSource =
            model.selected |> Maybe.andThen (\( id, _ ) -> userSources |> List.findBy .id id)
    in
    div []
        [ viewHeading
        , if projectRef |> Organization.canUseAml then
            div [ class "px-3 py-2" ]
                [ viewChooseSource selectedSource userSources
                , selectedSource |> Maybe.mapOrElse (viewSourceEditor model) (div [] [])
                ]

          else
            div [ class "px-3 py-2" ] [ PlanDialog.amlDisabledAlert projectRef ]
        ]


viewHeading : Html Msg
viewHeading =
    div [ class "px-6 py-5 border-b border-gray-200" ]
        [ div [ class "flex space-x-3" ]
            [ div [ class "flex-1" ]
                [ h3 [ class "text-lg leading-6 font-medium text-gray-900" ] [ text "Update your schema" ]
                ]
            , div [ class "flex-shrink-0 self-center flex" ]
                [ button [ onClick (AmlSidebarMsg AClose), class "-m-2 p-2 rounded-full flex items-center text-gray-400 hover:text-gray-600" ] [ Icon.solid Icon.X "" ]
                ]
            ]
        , p [ class "mt-1 text-sm text-gray-500" ]
            [ text "In Azimutt your schema is the union of all active sources. Create or update one with "
            , extLink Urls.amlDocs [ class "link" ] [ text "AML syntax" ]
            , text " to extend it."
            ]
        ]


viewChooseSource : Maybe Source -> List Source -> Html Msg
viewChooseSource selectedSource userSources =
    let
        selectId : HtmlId
        selectId =
            "sources"
    in
    div []
        [ label [ for selectId, class "block text-sm font-medium text-gray-700 sr-only" ] [ text "Sources" ]
        , div [ class "mt-1 flex rounded-md shadow-sm" ]
            [ div [ class "relative flex items-stretch flex-grow focus-within:z-10" ]
                [ select [ id selectId, name selectId, onInput (SourceId.fromString >> AChangeSource >> AmlSidebarMsg), disabled (List.isEmpty userSources), css [ "block w-full text-sm border-gray-300 rounded-none rounded-l-md", focus [ "ring-indigo-500 border-indigo-500" ], Tw.disabled [ "bg-slate-50 text-slate-500 shadow-none" ] ] ]
                    (option [] [ text (Bool.cond (List.isEmpty userSources) "-- no edit source, create one →" "-- select a source to edit") ]
                        :: (userSources |> List.sortBy .name |> List.map (\s -> option [ selected (Maybe.map .id selectedSource == Just s.id), value (SourceId.toString s.id) ] [ text s.name ]))
                    )
                ]
            , button [ onClick (simplePrompt "AML source name:" CreateUserSource), class "-ml-px relative inline-flex items-center space-x-2 px-4 py-2 border border-gray-300 text-sm font-medium rounded-r-md text-gray-700 bg-gray-50 hover:bg-gray-100 focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500" ]
                [ text "New source"
                ]
            ]
        ]


viewSourceEditor : AmlSidebar -> Source -> Html Msg
viewSourceEditor model source =
    let
        ( errors, warnings ) =
            ( model.errors |> List.filterBy .level ParserError.Error, model.errors |> List.filterBy .level ParserError.Warning )
    in
    div [ class "mt-3" ]
        [ Editor.basic "source-editor" (Source.contentStr source) (AUpdateSource source.id >> AmlSidebarMsg) (ASourceUpdated source.id |> AmlSidebarMsg) """Write your schema using AML syntax

Ex:

users
  id uuid pk
  first_name varchar(128)
  last_name varchar(128)
  email varchar(128) nullable

credentials | used to authenticate users
  user_id pk fk users.id
  login varchar(128) unique
  password varchar(128) nullable
  role varchar(10)=guest index | possible values: admin or guest
  created_at timestamp

roles
  slug varchar(10)

# define a standalone relation
fk credentials.role -> roles.slug""" 30 (List.nonEmpty errors)
        , viewErrors (errors |> List.map (\err -> err.message ++ " at line " ++ String.fromInt err.position.start.line ++ ", column " ++ String.fromInt err.position.start.column))
        , viewWarnings (warnings |> List.map (\err -> err.message ++ " at line " ++ String.fromInt err.position.start.line ++ ", column " ++ String.fromInt err.position.start.column))
        , viewHelp
        ]


viewErrors : List String -> Html msg
viewErrors errors =
    div []
        ((if errors |> List.nonEmpty then
            div [ class "mt-2 text-sm text-gray-500" ]
                [ text "Issues with AML? Try our "
                , extLink Urls.amlEditor [ class "link" ] [ text "online editor" ]
                , text " or check the "
                , extLink Urls.amlDocs [ class "link" ] [ text "documentation" ]
                , text "."
                , br [] []
                , text "(We are working to bring the editor here but have issues with Elm, Web Components & Monaco Editor, contact us if you can help 😉)"
                ]

          else
            div [] []
         )
            :: (errors |> List.map (\err -> p [ class "mt-2 text-sm text-red-600" ] [ text err ]))
        )


viewWarnings : List String -> Html msg
viewWarnings warnings =
    div []
        ((if warnings |> List.any (String.contains "legacy") then
            div [ class "mt-2 text-sm text-gray-500" ]
                [ text "Oh! It seems you are using the legacy AML syntax 😅"
                , br [] []
                , text "Fix it easily with "
                , extLink Urls.amlV1Converter [ class "link" ] [ text "our converter tool" ]
                , text " 🪄"
                ]

          else
            div [] []
         )
            :: (warnings |> List.map (\warning -> p [ class "mt-2 text-sm text-yellow-600" ] [ text warning ]))
        )


viewHelp : Html msg
viewHelp =
    p [ class "mt-2 text-sm text-gray-500" ]
        [ text "Write your database schema using "
        , extLink Urls.amlDocs [ class "link" ] [ text "AML syntax" ]
        , text ". You can also use the "
        , extLink Urls.vscodeExt [ class "link" ] [ text "VS Code extension" ]
        , text " for best editing experience."
        ]
