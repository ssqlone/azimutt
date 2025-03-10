module PagesComponents.Organization_.Project_.Views.Erd exposing (ErdArgs, argsToString, stringToArgs, viewErd)

import Components.Atoms.Button as Button
import Components.Atoms.Icon as Icon exposing (Icon(..))
import Components.Molecules.Alert as Alert
import Components.Molecules.ContextMenu as ContextMenu exposing (Direction(..))
import Components.Molecules.Dropdown as Dropdown
import Components.Organisms.Table exposing (TableHover)
import Components.Organisms.TableRow as TableRow exposing (TableRowHover, TableRowRelation, TableRowRelationColumn, TableRowSuccess)
import Components.Slices.LlmKey exposing (promptLlmKey)
import Conf
import Dict exposing (Dict)
import Html exposing (Html, button, div, h2, input, p, span, text)
import Html.Attributes exposing (autofocus, class, classList, id, name, placeholder, title, type_, value)
import Html.Events exposing (onBlur, onClick, onInput)
import Html.Events.Extra.Mouse exposing (Button(..))
import Html.Keyed as Keyed
import Html.Lazy as Lazy
import Libs.Bool as B
import Libs.Dict as Dict
import Libs.Html exposing (bText, extLink, sendTweet)
import Libs.Html.Attributes exposing (css, role)
import Libs.Html.Events exposing (PointerEvent, onContextMenu, onDblClick, onPointerDown, onWheel)
import Libs.List as List
import Libs.Maybe as Maybe
import Libs.Models.HtmlId exposing (HtmlId)
import Libs.Models.Platform as Platform exposing (Platform)
import Libs.Models.ZoomLevel exposing (ZoomLevel)
import Libs.Nel as Nel exposing (Nel)
import Libs.String as String
import Libs.Tailwind as Tw exposing (Color, focus)
import Libs.Time as Time
import Libs.Tuple as Tuple
import Models.Area as Area
import Models.DbSource as DbSource
import Models.ErdProps exposing (ErdProps)
import Models.OpenAIKey exposing (OpenAIKey)
import Models.OpenAIModel exposing (OpenAIModel)
import Models.Position as Position
import Models.Project.CanvasProps as CanvasProps exposing (CanvasProps)
import Models.Project.ColumnName exposing (ColumnName)
import Models.Project.ColumnPath as ColumnPath exposing (ColumnPath, ColumnPathStr)
import Models.Project.Comment exposing (Comment)
import Models.Project.Group as Group exposing (Group)
import Models.Project.Metadata exposing (Metadata)
import Models.Project.ProjectSettings exposing (LlmSettings)
import Models.Project.RowValue exposing (RowValue)
import Models.Project.SchemaName exposing (SchemaName)
import Models.Project.Source exposing (Source)
import Models.Project.Table exposing (Table)
import Models.Project.TableId as TableId exposing (TableId)
import Models.Project.TableMeta as TableMeta exposing (TableMeta)
import Models.Project.TableRow as TableRow exposing (TableRow, TableRowColumn)
import Models.ProjectInfo exposing (ProjectInfo)
import Models.RelationStyle exposing (RelationStyle)
import Models.Size as Size
import PagesComponents.Organization_.Project_.Components.DetailsSidebar as DetailsSidebar
import PagesComponents.Organization_.Project_.Models exposing (GroupEdit, GroupMsg(..), MemoEdit, MemoMsg(..), Msg(..), ProjectSettingsMsg(..), VirtualRelation, confirm)
import PagesComponents.Organization_.Project_.Models.CursorMode as CursorMode exposing (CursorMode)
import PagesComponents.Organization_.Project_.Models.DragState as DragState exposing (DragState)
import PagesComponents.Organization_.Project_.Models.Erd as Erd exposing (Erd)
import PagesComponents.Organization_.Project_.Models.ErdColumn exposing (ErdColumn)
import PagesComponents.Organization_.Project_.Models.ErdConf exposing (ErdConf)
import PagesComponents.Organization_.Project_.Models.ErdLayout as ErdLayout exposing (ErdLayout)
import PagesComponents.Organization_.Project_.Models.ErdRelation exposing (ErdRelation)
import PagesComponents.Organization_.Project_.Models.ErdTable as ErdTable exposing (ErdTable)
import PagesComponents.Organization_.Project_.Models.ErdTableLayout as ErdTableLayout exposing (ErdTableLayout)
import PagesComponents.Organization_.Project_.Models.ErdTableProps as ErdTableProps exposing (ErdTableProps)
import PagesComponents.Organization_.Project_.Models.LinkLayout exposing (LinkLayout)
import PagesComponents.Organization_.Project_.Models.LinkLayoutId as LinkLayoutId
import PagesComponents.Organization_.Project_.Models.Memo exposing (Memo)
import PagesComponents.Organization_.Project_.Models.MemoId as MemoId
import PagesComponents.Organization_.Project_.Updates.Drag as Drag
import PagesComponents.Organization_.Project_.Views.Erd.LinkLayout as LinkLayout
import PagesComponents.Organization_.Project_.Views.Erd.Memo as Memo
import PagesComponents.Organization_.Project_.Views.Erd.Relation as Relation exposing (viewEmptyRelation, viewRelation, viewVirtualRelation)
import PagesComponents.Organization_.Project_.Views.Erd.RelationRow exposing (viewRelationRow)
import PagesComponents.Organization_.Project_.Views.Erd.SelectionBox as SelectionBox
import PagesComponents.Organization_.Project_.Views.Erd.Table as Table exposing (viewTable)
import PagesComponents.Organization_.Project_.Views.Erd.TableRow as TableRow exposing (viewTableRow)
import PagesComponents.Organization_.Project_.Views.Modals.ErdContextMenu as ErdContextMenu
import PagesComponents.Organization_.Project_.Views.Modals.GroupContextMenu as GroupContextMenu
import Ports
import Services.Urls as Urls
import Set exposing (Set)
import Shared exposing (Prompt)
import Time
import Track


type alias ErdArgs =
    String


argsToString : Time.Posix -> Platform -> CursorMode -> String -> String -> DetailsSidebar.Selected -> Maybe TableHover -> Maybe TableRowHover -> Maybe GroupEdit -> ErdArgs
argsToString now platform cursorMode openedDropdown openedPopover selected hoverTable hoverRow editGroup =
    [ Time.posixToMillis now |> String.fromInt, Platform.toString platform, CursorMode.toString cursorMode, openedDropdown, openedPopover, selected, hoverTableToString hoverTable, hoverRowToString hoverRow, editGroup |> Maybe.mapOrElse (.index >> String.fromInt) "", editGroup |> Maybe.mapOrElse .content "" ] |> String.join "~"


stringToArgs : ErdArgs -> ( ( Time.Posix, Platform, CursorMode ), ( String, String, DetailsSidebar.Selected ), ( Maybe TableHover, Maybe TableRowHover, Maybe GroupEdit ) )
stringToArgs args =
    case args |> String.split "~" of
        [ now, platform, cursorMode, openedDropdown, openedPopover, selected, hoverTable, hoverTableRow, editGroupIndex, editGroupContent ] ->
            ( ( now |> String.toInt |> Maybe.withDefault 0 |> Time.millisToPosix, Platform.fromString platform, CursorMode.fromString cursorMode ), ( openedDropdown, openedPopover, selected ), ( hoverTableFromString hoverTable, hoverRowFromString hoverTableRow, editGroupIndex |> String.toInt |> Maybe.map (\index -> { index = index, content = editGroupContent }) ) )

        _ ->
            ( ( Time.zero, Platform.PC, CursorMode.Select ), ( "", "", "" ), ( Nothing, Nothing, Nothing ) )


viewErd : ErdConf -> ErdProps -> Erd -> Maybe SelectionBox.Model -> Maybe VirtualRelation -> Maybe MemoEdit -> ErdArgs -> Maybe DragState -> Html Msg
viewErd conf erdElem erd selectionBox virtualRelation editMemo args dragging =
    let
        ( ( now, platform, cursorMode ), ( openedDropdown, openedPopover, selected ), ( hoverTable, hoverTableRow, editGroup ) ) =
            stringToArgs args

        layout : ErdLayout
        layout =
            erd |> Erd.currentLayout

        canvas : CanvasProps
        canvas =
            dragging |> Maybe.filter (\d -> d.id == Conf.ids.erd) |> Maybe.mapOrElse (\d -> layout.canvas |> Drag.moveCanvas d |> Tuple.first) layout.canvas

        -- TODO: use to render only visible tables => needs to handle size change to 0...
        --canvasViewport : Area.Canvas
        --canvasViewport =
        --    canvas |> CanvasProps.viewport erdElem
        draggedLayout : ErdLayout
        draggedLayout =
            dragging |> Maybe.mapOrElse (\d -> layout |> Drag.moveInLayout d canvas.zoom |> Tuple.first) layout

        layoutTables : List ErdTableLayout
        layoutTables =
            draggedLayout.tables

        tableRows : List ( TableRow, Color )
        tableRows =
            draggedLayout.tableRows |> List.map (\r -> ( r, layout.tables |> List.findBy .id r.table |> Maybe.mapOrElse (.props >> .color) (ErdTableProps.computeColor r.table) ))

        tableRowRelations : List TableRowRelation
        tableRowRelations =
            buildRowRelations erd tableRows

        memos : List Memo
        memos =
            draggedLayout.memos

        links : List LinkLayout
        links =
            draggedLayout.links

        ( displayedTables, hiddenTables ) =
            layoutTables |> List.partition (\t -> t.props.size /= Size.zeroCanvas)

        groups : List ( Int, Group, Area.Canvas )
        groups =
            layout.groups |> List.zipWithIndex |> List.filterMap (ErdTableLayout.buildGroupArea displayedTables)

        virtualRelationInfo : Maybe ( ( Maybe { table : ErdTableProps, index : Int, highlighted : Bool }, ErdColumn ), Position.Canvas )
        virtualRelationInfo =
            virtualRelation
                |> Maybe.andThen
                    (\vr ->
                        vr.src
                            |> Maybe.andThen
                                (\src ->
                                    (erd |> Erd.getColumnI src)
                                        |> Maybe.map
                                            (\ref ->
                                                ( ( Relation.buildColumnInfo src.column (layoutTables |> List.findBy .id src.table), ref )
                                                , vr.mouse |> Erd.viewportToCanvas erdElem canvas
                                                )
                                            )
                                )
                    )

        otherLayouts : String
        otherLayouts =
            erd.layouts |> Dict.remove erd.currentLayout |> Dict.keys |> List.sort |> String.join "~"
    in
    div
        ([ id Conf.ids.erd
         , class "az-erd h-full bg-gray-100 overflow-hidden"
         , classList
            [ ( "invisible", List.nonEmpty layoutTables && (erdElem.size == Size.zeroViewport || erd.layoutOnLoad /= "") )
            , ( "cursor-grab-all", cursorMode == CursorMode.Drag && dragging == Nothing && virtualRelation == Nothing )
            , ( "cursor-grabbing-all", cursorMode == CursorMode.Drag && dragging /= Nothing && virtualRelation == Nothing )
            , ( "cursor-crosshair-all", virtualRelation /= Nothing )
            ]
         ]
            ++ B.cond (conf.move && ErdLayout.nonEmpty layout) [ onWheel OnWheel platform ] []
            ++ B.cond ((conf.move || conf.select) && virtualRelation == Nothing && editMemo == Nothing) [ onPointerDown (handleErdPointerDown conf cursorMode) platform ] []
            ++ B.cond (conf.layout && virtualRelation == Nothing && editMemo == Nothing && ErdLayout.nonEmpty layout) [ onDblClick (CanvasProps.eventCanvas erdElem canvas >> Position.onGrid >> MCreate >> MemoMsg) platform, onContextMenu (\e -> ContextMenuCreate (ErdContextMenu.view platform erdElem canvas otherLayouts layout e) e) platform ] []
        )
        [ div [ class "az-canvas origin-top-left", Position.styleTransformDiagram canvas.position canvas.zoom ]
            -- use HTML order instead of z-index, must be careful with it, this allows to have tooltips & popovers always on top
            [ -- canvas.position |> Position.debugDiagram "canvas" "bg-black"
              -- , layout.tables |> List.map (.props >> Area.offGrid) |> Area.mergeCanvas |> Maybe.mapOrElse (Area.debugCanvas "tablesArea" "border-blue-500") (div [] []),
              hiddenTables |> viewHiddenTables erd.settings.defaultSchema
            , groups |> viewGroups platform erd.settings.defaultSchema editGroup
            , tableRowRelations |> viewRelationRows conf erd.settings.relationStyle hoverTableRow
            , tableRows |> viewTableRows now platform conf cursorMode erd.settings.defaultSchema openedDropdown openedPopover erd hoverTableRow tableRowRelations
            , erd.relations |> Lazy.lazy5 viewRelations conf erd.settings.defaultSchema erd.settings.relationStyle displayedTables
            , links |> viewLinks platform conf cursorMode (dragging |> Maybe.any DragState.hasMoved) otherLayouts
            , layoutTables |> viewTables platform conf cursorMode virtualRelation openedDropdown openedPopover hoverTable dragging canvas.zoom erd.settings.defaultSchema selected erd.settings.columnBasicTypes erd.tables erd.metadata layout
            , memos |> viewMemos platform conf cursorMode editMemo
            , div [ class "az-selection-box pointer-events-none" ] (selectionBox |> Maybe.filter (\_ -> layout |> ErdLayout.nonEmpty) |> Maybe.mapOrElse SelectionBox.view [])
            , div [ class "az-virtual-relation pointer-events-none" ] [ virtualRelationInfo |> Maybe.mapOrElse (\i -> viewVirtualRelation erd.settings.relationStyle i) viewEmptyRelation ]
            ]
        , if layout |> ErdLayout.isEmpty then
            viewEmptyState openedDropdown (Conf.ids.erd ++ "-empty") erd

          else
            div [] []
        ]


viewTables : Platform -> ErdConf -> CursorMode -> Maybe VirtualRelation -> HtmlId -> HtmlId -> Maybe TableHover -> Maybe DragState -> ZoomLevel -> SchemaName -> DetailsSidebar.Selected -> Bool -> Dict TableId ErdTable -> Metadata -> ErdLayout -> List ErdTableLayout -> Html Msg
viewTables platform conf cursorMode virtualRelation openedDropdown openedPopover hoverTable dragging zoom defaultSchema selected useBasicTypes tables metadata layout tableLayouts =
    Keyed.node "div"
        [ class "az-tables" ]
        (tableLayouts
            |> List.reverse
            |> List.indexedMap Tuple.new
            |> List.filterMap (\( index, tableLayout ) -> tables |> Dict.get tableLayout.id |> Maybe.map (\table -> ( index, table, tableLayout )))
            |> List.map
                (\( index, table, tableLayout ) ->
                    ( TableId.toString table.id
                    , Lazy.lazy7 viewTable
                        conf
                        zoom
                        (Table.argsToString
                            platform
                            cursorMode
                            defaultSchema
                            (B.cond (openedDropdown |> String.startsWith table.htmlId) openedDropdown "")
                            (B.cond (openedPopover |> String.startsWith table.htmlId) openedPopover "")
                            index
                            selected
                            (hoverTable |> Maybe.any (\( t, _ ) -> t == table.id))
                            (dragging |> Maybe.any (\d -> d.id == table.htmlId && d.init /= d.last))
                            (virtualRelation /= Nothing)
                            useBasicTypes
                        )
                        layout
                        (metadata |> Dict.getOrElse table.id TableMeta.empty)
                        tableLayout
                        table
                    )
                )
        )


viewRelations : ErdConf -> SchemaName -> RelationStyle -> List ErdTableLayout -> List ErdRelation -> Html Msg
viewRelations conf defaultSchema style tableLayouts relations =
    let
        displayedIds : Set TableId
        displayedIds =
            tableLayouts |> List.map .id |> Set.fromList

        displayedRelations : List ErdRelation
        displayedRelations =
            relations |> List.filter (\r -> [ r.src, r.ref ] |> List.any (\c -> displayedIds |> Set.member c.table))
    in
    Keyed.node "div"
        [ class "az-relations select-none pointer-events-none" ]
        (displayedRelations
            |> List.map
                (\r ->
                    ( r.name
                    , Lazy.lazy6 viewRelation
                        defaultSchema
                        style
                        conf
                        (tableLayouts |> List.findBy .id r.src.table)
                        (tableLayouts |> List.findBy .id r.ref.table)
                        r
                    )
                )
        )


viewTableRows : Time.Posix -> Platform -> ErdConf -> CursorMode -> SchemaName -> HtmlId -> HtmlId -> Erd -> Maybe TableRowHover -> List TableRowRelation -> List ( TableRow, Color ) -> Html Msg
viewTableRows now platform conf cursorMode defaultSchema openedDropdown openedPopover erd hoverRow rowRelations tableRows =
    let
        rowRelationsBySrc : Dict TableRow.Id (List TableRowRelation)
        rowRelationsBySrc =
            rowRelations |> List.groupBy (\r -> r.src.row.id)

        rowRelationsByRef : Dict TableRow.Id (List TableRowRelation)
        rowRelationsByRef =
            rowRelations |> List.groupBy (\r -> r.ref.row.id)
    in
    Keyed.node "div"
        [ class "az-table-rows" ]
        (tableRows
            -- last one added on top
            |> List.reverse
            |> List.map
                (\( row, color ) ->
                    ( TableRow.toHtmlId row.id
                    , viewTableRow now
                        platform
                        conf
                        cursorMode
                        defaultSchema
                        openedDropdown
                        openedPopover
                        (TableRow.toHtmlId row.id)
                        erd
                        (erd.sources |> List.findBy .id row.source |> Maybe.andThen DbSource.fromSource)
                        (erd.tables |> TableId.dictGetI row.table)
                        (erd.relations |> List.filter (\r -> r.src.table == row.table || r.ref.table == row.table))
                        (erd.metadata |> Dict.get row.table)
                        hoverRow
                        ((rowRelationsBySrc |> Dict.getOrElse row.id []) ++ (rowRelationsByRef |> Dict.getOrElse row.id []))
                        color
                        row
                    )
                )
        )


viewRelationRows : ErdConf -> RelationStyle -> Maybe TableRowHover -> List TableRowRelation -> Html Msg
viewRelationRows conf style hoverRow relations =
    Keyed.node "div"
        [ class "az-relations select-none pointer-events-none" ]
        (relations |> List.map (\rel -> ( rel.id, viewRelationRow conf style hoverRow rel )))


viewMemos : Platform -> ErdConf -> CursorMode -> Maybe MemoEdit -> List Memo -> Html Msg
viewMemos platform conf cursorMode editMemo memos =
    Keyed.node "div"
        [ class "az-memos" ]
        (memos
            |> List.map
                (\memo ->
                    ( MemoId.toHtmlId memo.id
                    , Lazy.lazy5 Memo.viewMemo platform conf cursorMode (editMemo |> Maybe.filterBy .id memo.id) memo
                    )
                )
        )


viewLinks : Platform -> ErdConf -> CursorMode -> Bool -> String -> List LinkLayout -> Html Msg
viewLinks platform conf cursorMode dragging otherLayouts links =
    Keyed.node "div"
        [ class "az-links" ]
        (links
            |> List.map
                (\link ->
                    ( LinkLayoutId.toHtmlId link.id
                    , Lazy.lazy6 LinkLayout.viewLink platform conf cursorMode dragging otherLayouts link
                    )
                )
        )


viewGroups : Platform -> SchemaName -> Maybe GroupEdit -> List ( Int, Group, Area.Canvas ) -> Html Msg
viewGroups platform defaultSchema editGroup groups =
    div [ class "az-groups" ]
        (groups
            |> List.map
                (\( index, group, area ) ->
                    div
                        ([ css [ "absolute border-2 bg-opacity-25", Tw.bg_300 group.color, Tw.border_300 group.color ]
                         , onDblClick (\_ -> GEdit index group.name |> GroupMsg) platform
                         , onContextMenu (\e -> ContextMenuCreate (GroupContextMenu.view defaultSchema index group) e) platform
                         ]
                            ++ Area.styleTransformCanvas area
                        )
                        [ editGroup
                            |> Maybe.filter (\edit -> edit.index == index)
                            |> Maybe.mapOrElse
                                (\edit ->
                                    let
                                        inputId : HtmlId
                                        inputId =
                                            Group.toInputId index
                                    in
                                    input
                                        [ type_ "text"
                                        , name inputId
                                        , id inputId
                                        , placeholder "Group name"
                                        , value edit.content
                                        , onInput (GEditUpdate >> GroupMsg)
                                        , onBlur (GEditSave edit |> GroupMsg)
                                        , autofocus True
                                        , css [ "px-2 py-0 shadow-sm block border-gray-300 rounded-md", focus [ Tw.ring_500 group.color, Tw.border_500 group.color ] ]
                                        ]
                                        []
                                )
                                (div [ css [ "px-2 select-none", Tw.text_600 group.color ] ] [ text group.name ])
                        ]
                )
        )


viewHiddenTables : SchemaName -> List ErdTableLayout -> Html Msg
viewHiddenTables defaultSchema tables =
    Keyed.node "div"
        [ class "az-hidden-tables" ]
        (tables
            |> List.filter (\t -> t.props.position /= Position.zeroGrid)
            |> List.map
                (\table ->
                    ( TableId.toString table.id
                    , div
                        ([ css [ "select-none absolute flex items-center justify-items-center px-3 py-1 border-t-8 border-b border-b-default-200 rounded-lg opacity-50 hover:opacity-100" ]
                         , title "This table in layout but not in the schema, you can delete it or add it back to the schema."
                         ]
                            ++ Position.stylesGrid table.props.position
                        )
                        [ div [ class "text-xl opacity-50" ] [ text (TableId.show defaultSchema table.id) ]
                        , button [ type_ "button", id ("hide-" ++ TableId.toHtmlId table.id), onClick (HideTable table.id), title "Remove table from layout", css [ "ml-3 flex text-sm opacity-25", focus [ "outline-none" ] ] ]
                            [ span [ class "sr-only" ] [ text "Remove from layout" ]
                            , Icon.solid Icon.Trash ""
                            ]
                        ]
                    )
                )
        )


viewEmptyState : HtmlId -> HtmlId -> Erd -> Html Msg
viewEmptyState openedDropdown htmlId erd =
    div [ class "flex h-full justify-center items-center" ]
        [ div [ class "max-w-prose p-6 bg-white border border-gray-200 rounded-lg" ]
            [ div [ class "text-center" ]
                [ Icon.outline2x Template "mx-auto text-primary-500"
                , h2 [ class "mt-2 text-lg font-medium text-gray-900" ]
                    [ text "Hello from Azimutt 👋" ]
                , if erd.tables |> Dict.isEmpty then
                    p [ class "mt-3 text-sm text-gray-500" ]
                        [ text "Azimutt allows you to create and explore your database schema. Start writing your schema using "
                        , extLink Urls.amlDocs [ class "link" ] [ text "AML syntax" ]
                        , text " or import and explore your schema. Add any source (database url, SQL or JSON) in project settings (top right "
                        , Icon.outline Icon.Cog "h-5 w-5 inline"
                        , text ")."
                        ]

                  else
                    div []
                        [ p [ class "mt-3 text-sm text-gray-500" ]
                            [ text "Explore your "
                            , bText (erd.tables |> String.pluralizeD "table")
                            , text " database with Azimutt. Create layouts, show tables you want and share them. Use the "
                            , button [ onClick (Focus Conf.ids.searchInput), css [ "link", focus [ "outline-none" ] ] ] [ text "search bar" ]
                            , text " or start with an overview:"
                            ]
                        , div [ class "my-8 flex justify-around items-center" ]
                            (let
                                showAll : Msg
                                showAll =
                                    if Dict.size erd.tables < Conf.constants.manyTablesLimit then
                                        ShowAllTables "welcome"

                                    else
                                        confirm "Show all tables" (text ("You are about to show " ++ (erd.tables |> String.pluralizeD "table") ++ ". That's a lot. It may slow down your browser and make Azimutt unresponsive. Continue?")) (ShowAllTables "welcome")

                                tableSelection : List (Html Msg)
                                tableSelection =
                                    if Dict.size erd.tables > 30 then
                                        [ span [] [ text "or" ]
                                        , let
                                            topTables : List { id : TableId, columns : List ColumnName }
                                            topTables =
                                                erd.tables |> Dict.values |> List.sortBy (ErdTable.rank >> negate) |> List.take 30 |> List.map (\t -> { id = t.id, columns = [] })
                                          in
                                          Button.white4 Tw.indigo [ onClick (ShowTables topTables Nothing "welcome") ] [ text ("Show only main tables (" ++ (topTables |> List.length |> String.fromInt) ++ ")") ]
                                        ]

                                    else
                                        []

                                toggleId : HtmlId
                                toggleId =
                                    htmlId ++ "-layout-toggle"
                             in
                             [ Button.white4 Tw.indigo [ onClick showAll ] [ text ("Show all tables (" ++ (erd.tables |> Dict.size |> String.fromInt) ++ ")") ] ]
                                ++ tableSelection
                                ++ [ Dropdown.dropdown { id = toggleId, direction = BottomLeft, isOpen = openedDropdown == toggleId }
                                        (\m -> Button.white4 Tw.indigo [ id m.id, onClick (DropdownToggle m.id) ] [ span [ class "sr-only" ] [ text "Generate layout" ], text "AI", Icon.outline Icon.Sparkles "h-5 w-5 ml-1" ])
                                        (\_ ->
                                            let
                                                prompt : String -> String -> ProjectInfo -> (OpenAIKey -> OpenAIModel -> List Table -> String -> Cmd Msg) -> (ProjectInfo -> Cmd Msg) -> (ProjectInfo -> String -> Cmd Msg) -> Msg
                                                prompt title placeholder project exec trackOpen trackQueried =
                                                    Batch
                                                        [ useLlm PromptOpen (PSLlmKeyUpdate >> ProjectSettingsMsg) erd.settings.llm (\k m -> multilinePrompt title placeholder (\s -> Cmd.batch [ exec k m (erd |> buildTables) s, trackQueried project s ]))
                                                        , trackOpen project |> Send
                                                        ]
                                            in
                                            div [ class "py-1", role "none" ]
                                                [ ContextMenu.btn "" (prompt "Which layout do you want to build?" "Your layout prompt..." erd.project Ports.llmLayoutPrompt Track.layoutPromptOpened Track.layoutPromptQueried) [] [ Icon.outline Icon.Sparkles "h-5 w-5 inline mr-1", text "Prompt to generate layout" ]
                                                , ContextMenu.btn "" (prompt "Generate layout from SQL query:" "Your SQL query..." erd.project Ports.llmLayoutFromSql Track.layoutFromSqlOpened Track.layoutFromSqlQueried) [] [ Icon.outline Icon.Sparkles "h-5 w-5 inline mr-1", text "Generate layout from SQL query" ]
                                                ]
                                        )
                                   ]
                            )
                        , Alert.simple Tw.indigo Icon.InformationCircle [ text "Click on colored column icons to follow relations (in/out)." ]
                        ]
                , p [ class "mt-3 text-sm text-gray-500" ]
                    [ text "If you ❤️ Azimutt, "
                    , sendTweet Conf.constants.cheeringTweet [ class "link" ] [ text "come and say hi" ]
                    , text ". We are eager to learn how you use it and for what. We also love "
                    , extLink Conf.constants.azimuttFeatureRequests [ class "link" ] [ text "feedback and feature requests" ]
                    , text "."
                    ]
                ]
            ]
        ]


useLlm : (Prompt msg -> String -> msg) -> (String -> msg) -> Maybe LlmSettings -> (OpenAIKey -> OpenAIModel -> msg) -> msg
useLlm openPrompt updateLlmKey llmM exec =
    llmM |> Maybe.map (\llm -> exec llm.key llm.model) |> Maybe.withDefault (promptLlmKey openPrompt updateLlmKey)


buildTables : Erd -> List Table
buildTables erd =
    erd.tables
        |> Dict.values
        |> List.map ErdTable.unpack
        |> List.map
            (\t ->
                -- merge Azimutt notes & tags into table comments to feed then into LLM
                (erd.metadata |> Dict.get t.id)
                    |> (\doc ->
                            { t
                                | comment =
                                    ((t.comment |> Maybe.map .text |> Maybe.filter String.nonEmpty |> Maybe.toList)
                                        ++ (doc |> Maybe.andThen .notes |> Maybe.filter String.nonEmpty |> Maybe.toList)
                                        ++ (doc |> Maybe.filter (.tags >> List.nonEmpty) |> Maybe.map (\d -> "Tags: " ++ String.join "," d.tags) |> Maybe.toList)
                                    )
                                        |> Nel.fromList
                                        |> Maybe.map (\n -> { text = n |> Nel.toList |> String.join "\n\n" })
                            }
                       )
            )


multilinePrompt : String -> String -> (String -> Cmd Msg) -> Msg
multilinePrompt title placeholder message =
    PromptOpen
        { color = Tw.blue
        , icon = Nothing
        , title = title
        , message = text "If you have sub-optimal or bad results, try again and let us know so we can improve."
        , placeholder = placeholder
        , multiline = True
        , choices = []
        , confirm = "Generate"
        , cancel = "Back"
        , onConfirm = message
        }
        ""


handleErdPointerDown : ErdConf -> CursorMode -> PointerEvent -> Msg
handleErdPointerDown conf cursorMode e =
    if e.button == MainButton then
        case cursorMode of
            CursorMode.Drag ->
                if conf.move then
                    e |> .clientPos |> DragStart Conf.ids.erd

                else
                    Noop "No erd drag"

            CursorMode.Select ->
                if conf.select then
                    e |> .clientPos |> DragStart Conf.ids.selectionBox

                else
                    Noop "No selection box"

    else if e.button == MiddleButton then
        if conf.move then
            e |> .clientPos |> DragStart Conf.ids.erd

        else
            Noop "No middle button erd drag"

    else
        Noop "No match on erd pointer down"


hoverTableToString : Maybe TableHover -> String
hoverTableToString hover =
    hover |> Maybe.mapOrElse (\( id, col ) -> TableId.toHtmlId id ++ "/" ++ (col |> Maybe.mapOrElse ColumnPath.toString "")) ""


hoverTableFromString : String -> Maybe TableHover
hoverTableFromString str =
    case str |> String.split "/" of
        idStr :: col ->
            idStr |> TableId.fromHtmlId |> Maybe.map (\id -> ( id, col |> List.head |> Maybe.map ColumnPath.fromString ))

        _ ->
            Nothing


hoverRowToString : Maybe TableRowHover -> String
hoverRowToString hover =
    hover |> Maybe.mapOrElse (\( id, col ) -> String.fromInt id ++ "/" ++ (col |> Maybe.mapOrElse ColumnPath.toString "")) ""


hoverRowFromString : String -> Maybe TableRowHover
hoverRowFromString str =
    case str |> String.split "/" of
        idStr :: col ->
            idStr |> String.toInt |> Maybe.map (\id -> ( id, col |> List.head |> Maybe.map ColumnPath.fromString ))

        _ ->
            Nothing


buildRowRelations : Erd -> List ( TableRow, Color ) -> List TableRowRelation
buildRowRelations erd rows =
    let
        successRows : Dict TableId (List TableRowSuccess)
        successRows =
            rows
                |> List.filterMap (\( r, c ) -> r |> TableRow.stateSuccess |> Maybe.filter (\_ -> r.size /= Size.zeroCanvas) |> Maybe.map (\s -> { row = r, state = s, color = c }))
                |> List.groupBy (.row >> .table)

        sourceRelations : Dict ( TableId, ColumnName ) (List ErdRelation)
        sourceRelations =
            erd.relations
                |> List.groupBy (\r -> ( r.src.table, r.src.column.head ))

        getRelations : TableId -> ColumnPathStr -> List ErdRelation
        getRelations table column =
            sourceRelations |> Dict.get ( table, column ) |> Maybe.withDefault []

        getRowValues : TableId -> RowValue -> List TableRowRelationColumn
        getRowValues table value =
            successRows
                |> Dict.get table
                |> Maybe.withDefault []
                |> List.filterMap (\r -> r.state.columns |> List.zipWithIndex |> List.find (\( v, _ ) -> v.path == value.column && v.value == value.value) |> Maybe.map (TableRow.initRelationColumn r))

        relations : List TableRowRelation
        relations =
            successRows
                |> Dict.toList
                |> List.concatMap Tuple.second
                |> List.concatMap
                    (\r ->
                        r.state.columns
                            |> List.filter (\c -> r.row.hidden |> Set.member c.pathStr |> not)
                            |> List.indexedMap (\i c -> TableRow.initRelationColumn r ( c, i ))
                            |> List.concatMap
                                (\src ->
                                    getRelations src.row.table src.column.pathStr
                                        |> List.concatMap (\rel -> getRowValues rel.ref.table { column = rel.ref.column, value = src.column.value })
                                        |> List.map (TableRow.initRelation src)
                                )
                    )
    in
    relations
