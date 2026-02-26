module Domain.Settlement exposing (Preference, Transaction)

import Domain.Member as Member


type alias Transaction =
    { from : Member.Id
    , to : Member.Id
    , amount : Int
    }


type alias Preference =
    { memberRootId : Member.Id
    , preferredRecipients : List Member.Id
    }
