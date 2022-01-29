module PagesComponents.Projects.Id_.Models.ErdRelation exposing (ErdRelation, create, unpack)

import Dict exposing (Dict)
import Models.Project.Origin exposing (Origin)
import Models.Project.Relation exposing (Relation)
import Models.Project.RelationId exposing (RelationId)
import Models.Project.RelationName exposing (RelationName)
import Models.Project.Table exposing (Table)
import Models.Project.TableId exposing (TableId)
import PagesComponents.Projects.Id_.Models.ErdColumnRef as ErdColumnRef exposing (ErdColumnRef)


type alias ErdRelation =
    { id : RelationId
    , name : RelationName
    , src : ErdColumnRef
    , ref : ErdColumnRef
    , origins : List Origin
    }


create : Dict TableId Table -> Relation -> ErdRelation
create tables relation =
    { id = relation.id
    , name = relation.name
    , src = relation.src |> ErdColumnRef.create tables
    , ref = relation.ref |> ErdColumnRef.create tables
    , origins = relation.origins
    }


unpack : ErdRelation -> Relation
unpack relation =
    { id = relation.id
    , name = relation.name
    , src = relation.src |> ErdColumnRef.unpack
    , ref = relation.ref |> ErdColumnRef.unpack
    , origins = relation.origins
    }
