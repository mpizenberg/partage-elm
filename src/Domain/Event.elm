module Domain.Event exposing (Envelope, GroupMetadataChange, Id, Payload(..), compareEnvelopes, sortEvents)

import Domain.Entry as Entry exposing (Entry)
import Domain.Group as Group
import Domain.Member as Member
import Time


type alias Id =
    String


type alias Envelope =
    { id : Id
    , clientTimestamp : Time.Posix
    , triggeredBy : Member.Id
    , payload : Payload
    }


type Payload
    = MemberCreated { memberId : Member.Id, name : String, memberType : Member.Type, addedBy : Member.Id }
    | MemberRenamed { memberId : Member.Id, oldName : String, newName : String }
    | MemberRetired { memberId : Member.Id }
    | MemberUnretired { memberId : Member.Id }
    | MemberReplaced { previousId : Member.Id, newId : Member.Id }
    | MemberMetadataUpdated { memberId : Member.Id, metadata : Member.Metadata }
    | EntryAdded Entry
    | EntryModified Entry
    | EntryDeleted { rootId : Entry.Id }
    | EntryUndeleted { rootId : Entry.Id }
    | GroupMetadataUpdated GroupMetadataChange


type alias GroupMetadataChange =
    { name : Maybe String
    , subtitle : Maybe (Maybe String)
    , description : Maybe (Maybe String)
    , links : Maybe (List Group.Link)
    }


compareEnvelopes : Envelope -> Envelope -> Order
compareEnvelopes a b =
    let
        ta =
            Time.posixToMillis a.clientTimestamp

        tb =
            Time.posixToMillis b.clientTimestamp
    in
    case compare ta tb of
        EQ ->
            compare a.id b.id

        order ->
            order


sortEvents : List Envelope -> List Envelope
sortEvents =
    List.sortWith compareEnvelopes
