module Domain.Activity exposing (Type(..))


type Type
    = EntryAdded
    | EntryModified
    | EntryDeleted
    | EntryUndeleted
    | MemberJoined
    | MemberLinked
    | MemberRenamed
    | MemberRetired
    | GroupMetadataUpdated
