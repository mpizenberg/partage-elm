module Domain.Activity exposing (Type(..))

{-| Activity types for the group activity feed.
-}


{-| The kind of activity that occurred, used for displaying an activity feed.
-}
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
