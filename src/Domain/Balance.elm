module Domain.Balance exposing (MemberBalance, Status(..))

import Domain.Member as Member


type alias MemberBalance =
    { memberRootId : Member.Id
    , totalPaid : Int
    , totalOwed : Int
    , netBalance : Int
    }


type Status
    = Creditor
    | Debtor
    | Settled
