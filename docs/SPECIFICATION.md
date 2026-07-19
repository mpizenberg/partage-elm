# Partage - Complete Feature Specification

> **Partage** is a fully encrypted, local-first, bill-splitting application
> designed for trusted groups (friends, family, roommates).
> It runs as an installable Progressive Web App (PWA).

---

## Table of Contents

1. [Core Principles](#1-core-principles)
2. [User Identity](#2-user-identity)
3. [Group Management](#3-group-management)
4. [Member Management](#4-member-management)
5. [Entries: Expenses, Transfers, and Income](#5-entries-expenses-transfers-and-income)
6. [Balance Calculation](#6-balance-calculation)
7. [Settlement Planning](#7-settlement-planning)
8. [Activity Feed & Audit Trail](#8-activity-feed--audit-trail)
9. [Filtering & Sorting](#9-filtering--sorting)
10. [Multi-Currency Support](#10-multi-currency-support)
11. [Encryption & Security](#11-encryption--security)
12. [Invitation & Group Joining](#12-invitation--group-joining)
13. [Import / Export](#13-import--export)
14. [Offline & Synchronization](#14-offline--synchronization)
15. [Push Notifications](#15-push-notifications)
16. [Progressive Web App (PWA)](#16-progressive-web-app-pwa)
17. [Internationalization (i18n)](#17-internationalization-i18n)
18. [Usage Statistics](#18-usage-statistics)
19. [Navigation & Screens](#19-navigation--screens)
20. [Accessibility & UX Details](#20-accessibility--ux-details)

---

## 1. Core Principles

| Principle | Description |
|---|---|
| **Privacy-first** | All sensitive data is end-to-end encrypted. The server never sees plaintext. |
| **Zero-knowledge server** | The server only relays encrypted data. It cannot read, query, or enforce business logic on the content. |
| **Local-first** | The application works offline. All data is stored locally and synced when connectivity is available. |
| **Trusted-group model** | Groups are designed for people who know each other. Anyone with the group link (and its embedded key) can join without approval. |
| **Immutable audit trail** | Entries are never truly deleted. Modifications and deletions create new versioned records, preserving the full history. |
| **Deterministic convergence** | Multiple devices can make changes concurrently. All clients build identical state by replaying events in a deterministic total order (by timestamp and event ID). |
| **No user accounts** | There are no centralized user accounts, passwords, or emails. Identity is a locally-generated cryptographic keypair. |

---

## 2. User Identity

### 2.1 Identity Creation

- On first launch, the user lands on a **public welcome/landing page** that explains the app and shows a button to start using the app (by generating a local ID).
- The application generates a **cryptographic keypair** locally in the browser using **ECDSA P-256** (chosen for broad Web Crypto API compatibility across browsers).
- The keypair is used for **digital signatures** (to authenticate operations).
- The **public key hash** (SHA-256 of the public key) serves as the user's anonymous, unique identifier.
- No username, email, or password is required.
- The welcome page itself is reachable without an identity (for SEO and prospective users) and includes a language selector.

### 2.2 Identity Storage

- The keypair is stored in the browser's local database (IndexedDB), serialized as JWK (JSON Web Key).
- There is exactly **one identity per browser profile**.
- The identity persists across sessions until the browser data is cleared.
- Alongside the keypair, the app also persists a **local "self profile"** of contact and payment information (see [4.6](#46-member-metadata-encrypted)). It is stored only in IndexedDB (never synced) and is used to pre-fill member metadata across groups.

### 2.3 Identity Recovery

- **There is no password recovery mechanism.** If the browser data is lost, the identity is lost.
- The user can rejoin groups via a new invite link, but they will appear as a new member.
- The user can link their new identity to any previous member entry (see [Device Links](#44-device-links-identity-claiming)).

### 2.4 Identity Guarantees

- The server never learns the user's real name or any personal information.
- The user's identifier (public key hash) is pseudonymous and cannot be correlated across groups by the server.

### 2.5 Automatic Identity Generation

- If a user opens an invite link without an existing identity, the app automatically generates one before proceeding with the join flow.

---

## 3. Group Management

### 3.1 Group Creation

- Any user can create a new group.
- **Required fields:** group name, creator's display name, default currency.
- **Optional fields:** virtual members (name-only placeholders for people who haven't joined yet).
- Additional group metadata (subtitle, description, links) can be edited after creation via the group settings screen. This keeps the creation form simple and focused.
- **Anti-spam protection:** Creating a group requires solving a **Proof-of-Work (PoW) challenge**.
  - Difficulty: 18 leading zero bits in the SHA-256 hash (~2-4 seconds of computation).
  - Challenge validity window: 10 minutes.
  - Each challenge can only be used once (enforced server-side via unique constraint on `powChallenge`).
  - The PoW is solved in a Web Worker to avoid blocking the UI.
- The creator is automatically added as the first member of the group.

### 3.2 Group Metadata

Each group has the following metadata, all **encrypted**:

| Field | Required | Editable | Description |
|---|---|---|---|
| Name | Yes | Yes | The display name of the group. |
| Subtitle | No | Yes | A short tagline shown in the group header. |
| Description | No | Yes | A longer description shown on the Members tab. |
| Links | No | Yes | A list of `{label, url}` pairs rendered as clickable chips (e.g., shared spreadsheet, payment link). |
| Default currency | Yes | No | The ISO 4217 currency code used for balance normalization. Set at group creation and cannot be changed afterward. |

- Group metadata changes are tracked in the activity feed via `GroupMetadataUpdated` events that record which fields changed.

### 3.3 Group Archiving

- A user can **archive a group** to hide it from the main group list.
- Archived groups appear in a separate collapsible section on the home screen with reduced visual prominence.
- Archiving is a **local-only** operation (not an event, not synced to other members).
- Archived groups can be **unarchived** at any time.

### 3.4 Group Removal

- A user can **remove a group from their local device** (with confirmation).
- This does not delete the group on the server or for other members.

---

## 4. Member Management

### 4.1 Member Types

| Type | Description |
|---|---|
| **Real member** | A user who joined with their own cryptographic identity. Identified by their public key hash. |
| **Virtual member** | A name-only placeholder for someone who hasn't joined the app yet. Identified by a generated UUID. Can be created by any group member. |

### 4.2 Member Lifecycle (Event-Sourced)

Members are managed through an **immutable event log**. The current state of each member is computed by replaying all events. The following events exist:

| Event | Description |
|---|---|
| `MemberCreated` | A new member is added (real or virtual). Records member ID, name, member type, and who added them. When a member creates themselves, the envelope also carries their signing public key (see [11.3](#113-event-signing)). |
| `MemberRenamed` | A member's display name is changed. Records root ID, old and new names. |
| `MemberRetired` | A member is marked as departed/inactive. Records root ID. |
| `MemberUnretired` | A retired member is reactivated. Records root ID. |
| `MemberLinked` | A device claims an existing member's identity (see [Device Links](#44-device-links-identity-claiming)). Records root ID, device ID, and a per-device sequence number; the envelope carries the device's signing public key (see [11.3](#113-event-signing)). |
| `MemberMetadataUpdated` | A member's contact or payment information is updated. Records root ID and full metadata. |
| `SettlementPreferencesUpdated` | A member's settlement preferences are updated (preferred payment recipients). Records member root ID and ordered list of preferred recipients. |

### 4.3 Computed Member State

From the event log, each member has a computed state:

| Property | Description |
|---|---|
| `rootId` | The member's own ID, assigned at creation. Serves as the stable identifier for the person. |
| `name` | Current display name (latest rename, or creation name). |
| `isRetired` | True if the latest lifecycle event is `MemberRetired`. |
| `joinedAt` | Timestamp when the member was created. |
| `metadata` | Contact and payment information (see [4.6](#46-member-metadata-encrypted)). |
| `memberType` | The **effective** type: real if the member was created real or at least one device currently links to it; virtual otherwise. |
| `publicKey` | The creating device's public key, taken from the envelope-level `key` field of the member's self-`MemberCreated` event (empty for virtual members). |

Alongside the members, the group state maintains a **device-link map**: for each device that has emitted `MemberLinked` events, the winning link (see [4.4](#44-device-links-identity-claiming)) with its root ID, public key, and sequence number.

A member is considered **active** if they are not retired.

### 4.4 Device Links (Identity Claiming)

A **root** is a person; a **link** is a device claim. When a real user joins a group, they can **claim the identity of any existing group member** (virtual or real) by emitting a `MemberLinked` event asserting "this device acts as this root":

- A device has at most one effective link — its **latest** — so a device can only ever point at one root. Emitting a new link atomically vacates the previously claimed member: fixing a wrong claim needs no revert event and no terminal states.
- Per device, the winning link is the one with the highest `(seq, timestamp, event ID)`, compared in that order. `seq` is a per-device monotonic counter (next = current winner's seq + 1, starting at 0), which makes a device's own re-links robust to its clock jumping backwards. Event IDs are unique, so the order is total and replay is deterministic.
- **ID resolution** checks the device-link map first, then falls back to root identity: a device that joined as a new member (its device ID is a root ID) but later linked elsewhere resolves to the link target. Its own root remains in the group with its history; moving entries between roots remains the job of [member merging](#47-member-merging).
- The rootId is used throughout the application as the **stable identifier** for a member: balance calculations, activity feeds, entry displays, and settlement plans all aggregate by rootId. Names, retirement, and metadata are properties of the root, unaffected by which device claims it.
- In the join UI, claiming a **virtual member** is the primary path (prominently displayed). Claiming a **real member** is available in a separate section, intended for device migration or identity recovery scenarios. After joining, the member detail view offers **"This is me"** to re-link the device to a different member, which is how a wrong claim is corrected.

### 4.5 Member Operation Rules

Member operations follow strict validation rules. Invalid events are **silently ignored** during state computation, which is intentional for deterministic convergence (different replicas may receive events in different orders, but replay them in the same deterministic sort order).

| Operation | Valid When | Invalid When |
|---|---|---|
| **Create** | No member with this rootId already exists. | Duplicate member ID. |
| **Rename** | Member with the given rootId exists. | Member does not exist. |
| **Retire** | Member exists and is not already retired. | Member does not exist, or is already retired. |
| **Unretire** | Member exists and is currently retired. | Member does not exist, or is not retired. |
| **Link** | Member with the target rootId exists, and the link beats the device's current winning link (higher `(seq, timestamp, event ID)`). | Member does not exist, or an existing link for the device wins. |

**Authorization rules:**
- `GroupCreated`: Allowed once — only the first `GroupCreated` in sort order applies; later ones are ignored (a duplicate would rewrite the default currency, re-basing every balance).
- `MemberCreated`: Allowed if the member is creating themselves, or the actor is an existing group member.
- `MemberLinked`: Allowed if the actor is the linked device itself (asserting its own identity).
- All other operations: The actor must be an existing group member.

Key design principles:
- **State transitions**: Active members can be retired; retired members can be unretired. There are no terminal states — links can always be re-emitted.
- **Root ID resolution**: The device-link map takes precedence, then root identity. The display name is the root's current name, regardless of which device claims it.

### 4.6 Member Metadata (Encrypted)

Each member can have optional contact and payment information:

| Category | Fields |
|---|---|
| **Contact** | Phone number, email address |
| **Payment methods** | IBAN, Wero, Lydia, Revolut, PayPal, Venmo, Bitcoin (BTC address), Cardano (ADA address) |
| **Notes** | Free-text information field |

- All metadata is **encrypted** with the group key.
- Payment details are displayed as copiable text.
- Some payment methods generate clickable payment links (Lydia, Revolut, PayPal, Venmo, Bitcoin).
- Phone numbers are displayed as clickable `tel:` links.
- Metadata changes are tracked in the activity feed with field-by-field change detection.

### 4.7 Member Merging

In addition to identity claiming (which links a device to an existing member), the app supports **merging one existing member into another**, primarily to clean up duplicates created when someone joined as a new member instead of claiming a virtual placeholder.

- The merge is a two-step flow: pick the **target** member to keep, then preview the effects before confirming.
- Confirmation requires typing a sentinel string (type-to-confirm) to guard against accidental merges.
- A merge produces a batch of events submitted together:
  - Every active entry referencing the source member as a payer, beneficiary, transfer participant, or income receiver is **rewritten** via `EntryModified` to reference the target.
  - Transfers that would become self-transfers after rewriting are **soft-deleted** via `EntryDeleted`.
  - The source member's settlement preferences are merged into the target's via `SettlementPreferencesUpdated`.
  - Finally, the source member is retired via `MemberRetired`.
- Merge is **not atomic** on the server: if a sync fails mid-way the merge lands partially. There is no automated rollback, but the operation is replayable because each underlying event is idempotent.
- Late-arriving events that still reference the source are not rewritten retroactively; the source is retired so it remains visible only in history.

### 4.8 Member Display Order

- **Active members**: The current user appears first (with a "(you)" badge), then others sorted alphabetically (case-insensitive).
- **Departed members**: Listed alphabetically in a collapsible section.

---

## 5. Entries: Expenses, Transfers, and Income

### 5.1 Entry Types

| Type | Description |
|---|---|
| **Expense** | A shared cost paid by one or more payers on behalf of one or more beneficiaries. |
| **Transfer** | A direct payment from one member to another (typically a reimbursement/settlement). |
| **Income** | Shared income received by one member on behalf of one or more beneficiaries (e.g., a group refund, shared revenue). |

### 5.2 Expense Entry Fields

| Field | Required | Description |
|---|---|---|
| Description | Yes | What the expense is for. |
| Amount | Yes | The total amount (must be > 0). |
| Currency | Yes | ISO 4217 code. |
| Date | Yes | Date of the expense (defaults to today). |
| Payers | Yes | One or more members who paid, each with their paid amount. |
| Beneficiaries | Yes | One or more members who benefit, with split configuration. |
| Category | No | One of: food, transport, accommodation, entertainment, shopping, groceries, utilities, healthcare, other. |
| Location | No | Where the expense occurred. *(Modeled in domain; UI deferred to a future release.)* |
| Notes | No | Additional free-text notes. |
| Default currency amount | Conditional | Required if the entry currency differs from the group's default currency. |

### 5.3 Transfer Entry Fields

| Field | Required | Description |
|---|---|---|
| Amount | Yes | The transfer amount (must be > 0). |
| Currency | Yes | ISO 4217 code. |
| Date | Yes | Date of the transfer (defaults to today). |
| From | Yes | The member sending money. |
| To | Yes | The member receiving money. Cannot be the same as "from". |
| Notes | No | Additional free-text notes. |
| Default currency amount | Conditional | Required if the entry currency differs from the group's default currency. |

### 5.4 Income Entry Fields

| Field | Required | Description |
|---|---|---|
| Description | Yes | What the income is for. |
| Amount | Yes | The total amount (must be > 0). |
| Currency | Yes | ISO 4217 code. |
| Date | Yes | Date of the income (defaults to today). |
| Received by | Yes | The member who received the money. |
| Beneficiaries | Yes | One or more members who benefit from the income, with split configuration. |
| Notes | No | Additional free-text notes. |
| Default currency amount | Conditional | Required if the entry currency differs from the group's default currency. |

Income entries have **no category** field. They are identified by a unique "Income" tag for filtering purposes, similar to how transfers are identified by a "Transfer" tag.

### 5.5 Expense Splitting Methods

#### Shares-Based Split

- Each beneficiary has a number of shares (default: 1).
- The total amount is divided proportionally by each beneficiary's share count relative to the total shares.
- **Rounding guarantee:** Integer arithmetic (in cents) is used. Any remainder cents are distributed deterministically to beneficiaries sorted by member ID. A member with N shares can receive up to N remainder cents. This ensures the split always sums exactly to the total.

#### Exact Amount Split

- Each beneficiary has a specific amount they owe.
- The sum of all exact amounts must equal the total expense amount exactly.

Both splitting methods are also available for **income** entries.

### 5.6 Multiple Payers

- By default, a single payer pays the full amount.
- Multiple payers mode: each payer specifies the portion they paid.
- The sum of all payer amounts must equal the total expense amount exactly.
- When the entry currency differs from the default currency, payer amounts are proportionally converted using integer arithmetic (cents) with deterministic remainder distribution.

### 5.7 Entry Versioning

Each entry has metadata that supports versioning:

| Field | Description |
|---|---|
| `id` | Unique UUID v4 for this version. |
| `rootId` | UUID of the original entry in the chain. |
| `previousVersionId` | UUID of the prior version (if this is a modification). |
| `depth` | Chain depth (0 for the original, incremented for each modification). |
| `isDeleted` | Whether this version represents a deletion. |
| `createdBy` | Member ID of the author. |
| `createdAt` | Timestamp of creation. |

- Entries can be **modified** by creating a new entry linked to the original.
- The modification records: who modified it, when, and the full new data.
- **Current version rule:** For a given `rootId`, the current version is the version with the **greatest `depth`** (the longest modification chain); equal depths are broken by the **greater version `id`** (string comparison). Deliberately **not** last-writer-wins: comparing wall-clock timestamps would let the device with the fastest clock win every concurrent-edit conflict, whereas depth is intrinsic to the chain and clock-independent. Every client computes the same winner from the same set of versions. The equal-depth tie-break is arbitrary but deterministic. All versions are retained; `previousVersionId` supports audit trail display and diff computation.

### 5.8 Entry Deletion & Restoration

- Entries can be **soft-deleted** (creating a new version with deleted status via `EntryDeleted` event).
- Deleted entries are hidden by default but can be shown via a toggle.
- Deleted entries can be **restored** (via `EntryUndeleted` event).
- Deleted entries are excluded from balance calculations.

### 5.9 Entry Duplication

- From an entry's detail view, a **Duplicate** button opens the new-entry form pre-filled with the entry's fields (kind, description, amount, currency, payers, beneficiaries, etc.) and today's date.
- Submitting creates an independent new entry; the duplicate has no link to the source in the version chain.

### 5.10 Form Validation Rules

- Description (expense, income): required, non-empty after trimming.
- Amount: required, numeric, strictly positive.
- Default currency amount: required when currency differs from group default, strictly positive.
- Payers (expense): at least one required; sum must match total exactly.
- Beneficiaries (expense, income): at least one required; for exact split, sum must match total exactly.
- Transfer from/to: must be different members.
- Receiver (income): exactly one member required.

---

## 6. Balance Calculation

### 6.1 Per-Member Balance

For each member, the application computes:

| Metric | Calculation |
|---|---|
| **Total Paid** | Sum of all amounts this member paid across all active entries. |
| **Total Owed** | Sum of all amounts this member owes across all active entries. |
| **Net Balance** | Total Paid - Total Owed. |

- **Positive net balance** = the member is owed money (creditor).
- **Negative net balance** = the member owes money (debtor).
- **Zero (|balance| < 0.01)** = the member is settled.

### 6.2 Calculation Rules

- Only **active** entries are included (deleted entries are excluded).
- All amounts are normalized to the **group's default currency** using the stored `defaultCurrencyAmount`.
- Member IDs are resolved to their **root member IDs** (accounting for device links, see [Device Links](#44-device-links-identity-claiming)).
- Rounding uses **cent-based integer arithmetic** for deterministic, exact results.

#### Entry Type Contributions

| Entry Type | Total Paid contribution | Total Owed contribution |
|---|---|---|
| **Expense** | Payer amounts (proportionally converted for multi-currency). | Beneficiary split amounts. |
| **Transfer** | `from` member: transfer amount. | `to` member: transfer amount. |
| **Income** | Beneficiary split amounts (beneficiaries gain a credit). | `receivedBy` member: total income amount. |

### 6.3 Balance Display

- Each member's balance is shown in a **BalanceCard** component.
- Color coding:
  - **Green**: member is owed money (positive balance).
  - **Red**: member owes money (negative balance).
  - **Neutral**: member is settled (|balance| < 0.01).
- The current user's card shows a "(you)" badge.
- A "New Transfer" button appears when expanding a member card, for quick settlement recording.

---

## 7. Settlement Planning

### 7.1 Settlement Algorithm

The application generates an optimized **settlement plan** that minimizes the total number of transactions needed to settle all debts.

**Two-pass algorithm:**

1. **Pass 1 - Preference-Aware:** Debtors with settlement preferences are processed first. They are sorted by amount (smallest first) and matched to their preferred creditors in priority order.
2. **Pass 2 - Greedy Optimization:** Remaining debtors are sorted by amount (largest first) and matched to the largest available creditors greedily.

**Guarantees:**
- All debts are settled after the plan is executed.
- Amounts are rounded to 2 decimal places.
- Micro-debts below 0.01 are treated as zero.

**Plan stability:** To avoid the displayed plan jumping around as members record transfers one by one, the app uses a **stable settlement** derivation. The greedy two-pass runs against an **anchor snapshot** (the balances as of the most recent non-transfer event), and only the cumulative effect of post-anchor transfers is applied on top. As long as transfers don't change which non-transfer events have occurred, edges untouched by the new transfers keep their position in the plan list.

### 7.2 Settlement Preferences

Each member can configure **preferred recipients** for receiving payments, ordered by priority.

- `preferredRecipients`: An ordered list of creditors to try first when settling this member's debts.
- Empty list removes all preferences for a member.
- Preferences are synced via `SettlementPreferencesUpdated` events.

### 7.3 Settlement Recording

- Each transaction in the settlement plan has a "Record Transfer" button.
- Clicking it creates a **Transfer entry** recording the payment.
- Transactions involving the current user are **highlighted** visually.
- When all debts are settled, a "All settled up" message with a checkmark is displayed.
- Settlement details show the recipient's payment methods (IBAN, Lydia, Revolut, etc.) when available.

---

## 8. Activity Feed & Audit Trail

### 8.1 Activity Types

The activity feed tracks all significant actions in a group. Activities are split into three categories for filtering:

**Entry Activities:**

| Activity Type | Trigger |
|---|---|
| `EntryAdded` | A new expense is created. |
| `EntryModified` | An existing expense is edited. Records field-by-field changes. |
| `TransferAdded` | A new transfer is created. |
| `TransferModified` | An existing transfer is edited. Records field-by-field changes. |
| `IncomeAdded` | A new income entry is created. |
| `IncomeModified` | An existing income entry is edited. Records field-by-field changes. |
| `EntryDeleted` | An entry is soft-deleted. |
| `EntryUndeleted` | A deleted entry is restored. |

**Member Activities:**

| Activity Type | Trigger |
|---|---|
| `MemberCreated` | A new member joins the group (real or virtual). Records name and member type. |
| `MemberLinked` | A device claims a member's identity. Records name and root ID. |
| `MemberRenamed` | A member changes their display name. Shows old and new names. |
| `MemberRetired` | A member is marked as departed. |
| `MemberUnretired` | A retired member is reactivated. |
| `MemberMetadataUpdated` | A member's contact or payment information is updated. Records which fields changed. |

**Group Activities:**

| Activity Type | Trigger |
|---|---|
| `GroupCreated` | The group was created. Records name and default currency. |
| `GroupMetadataUpdated` | Group metadata (name, subtitle, etc.) is changed. Records which fields changed with old/new values. |
| `SettlementPreferencesUpdated` | A member's settlement preferences are changed. Records old and new preferred recipients. |

### 8.2 Activity Details

Each activity records:
- **Who** performed the action (actor ID).
- **When** (timestamp).
- **What** changed (full entry/member data, and for modifications, a field-by-field change list).
- **Involved members** (all member IDs affected by the activity).

#### Modification Change Detection

For entry modifications, the system computes field-by-field diffs:

| Entry Type | Tracked Fields |
|---|---|
| **Expense** | description, amount, currency, date, payers, beneficiaries, category, notes |
| **Transfer** | amount, currency, date, from, to, notes |
| **Income** | description, amount, currency, date, receivedBy, beneficiaries, notes |

For member metadata modifications: phone, email, payment methods, notes.
For group metadata modifications: name, subtitle, description, links.

### 8.3 Activity Sorting

- Activities are sorted **newest first** by timestamp.
- Activities are grouped by date for display, with date separator headers.
- When new activities are added (e.g., from sync), they are merged into the existing sorted list efficiently. The current implementation uses a tail-recursive merge of sorted lists. Alternative approaches such as binary search insertion could be explored if profiling reveals a bottleneck.

### 8.4 Immutability Guarantee

- The activity feed is derived from the immutable event log and entry history.
- Activities cannot be edited or deleted.
- The full history of every entry (all versions) is preserved.

---

## 9. Filtering & Sorting

### 9.1 Entry Filters

Entries can be filtered by multiple criteria simultaneously:

| Filter | Logic | Description |
|---|---|---|
| **Person** | AND | Entry must involve ALL specified persons (as payer, beneficiary, sender, or receiver). |
| **Category** | OR | Entry must match ANY of the selected categories. Transfers have a special "Transfer" tag. Income has a special "Income" tag. |
| **Currency** | OR | Entry must use ANY of the selected currencies. |
| **Date range** | OR | Entry date must fall within ANY of the selected date ranges. |

- **Cross-type combination**: All active filter types are combined with **AND** logic (all must pass).
- **Within same type**: Person filters use AND; all others use OR.
- **Empty filter**: Shows all entries.

### 9.2 Category Filter Tags

The category filter supports three types of tags:

| Tag Type | Description |
|---|---|
| **Expense categories** | Food, Transport, Accommodation, Entertainment, Shopping, Groceries, Utilities, Healthcare, Other |
| **Transfer** | Matches all transfer entries (no sub-categories). |
| **Income** | Matches all income entries (no sub-categories). |

### 9.3 Date Presets

| Preset | Range |
|---|---|
| Today | Start of today to end of today |
| Yesterday | Start of yesterday to end of yesterday |
| Last 7 days | 7 days ago to end of today |
| Last 30 days | 30 days ago to end of today |
| This month | 1st of current month to last moment of current month |
| Last month | 1st of previous month to last moment of previous month |
| Custom | User-defined start and end dates |

### 9.4 Activity Filters

Activities can be filtered by three dimensions (combined with AND):

| Filter | Description |
|---|---|
| **Activity type** | Entry activities, Member activities, or Group activities. |
| **Actor** | Who performed the action. |
| **Involved members** | Members affected by the activity. |

### 9.5 Deleted Entry Visibility

- Deleted entries are **hidden by default**.
- A toggle allows showing/hiding deleted entries in the list.

### 9.6 Entry Search

- The Entries tab has a **search bar** that case-insensitively matches the query against entry description, notes, and the resolved display names of payers, beneficiaries, transfer participants, and income receivers.
- Search is combined with the active filters using **AND** logic.

---

## 10. Multi-Currency Support

### 10.1 Supported Currencies

The application supports 10 currencies:

| Code | Symbol | Name | Precision |
|---|---|---|---|
| EUR | € | Euro | 2 decimal places |
| USD | $ | US Dollar | 2 decimal places |
| GBP | £ | British Pound | 2 decimal places |
| CHF | CHF | Swiss Franc | 2 decimal places |
| JPY | ¥ | Japanese Yen | 0 decimal places |
| AUD | A$ | Australian Dollar | 2 decimal places |
| CAD | C$ | Canadian Dollar | 2 decimal places |
| NZD | NZ$ | New Zealand Dollar | 2 decimal places |
| BRL | R$ | Brazilian Real | 2 decimal places |
| ARS | AR$ | Argentine Peso | 2 decimal places |

**Currency precision** determines the number of fractional digits when formatting amounts and the interpretation of the smallest unit. For example, 1050 cents in EUR formats as "10.50 EUR", while 1050 in JPY formats as "1050 ¥" (no fractional part). All amounts are stored internally as integers in the currency's **smallest unit** (cents for most currencies, whole units for JPY).

### 10.2 Currency Behavior

- Each group has a **default currency** set at creation time. It cannot be changed afterward.
- Each entry can use **any currency**.
- When an entry uses a non-default currency, the user must provide the **equivalent amount in the default currency** (manual exchange rate entry).
- Both the original amount/currency and the default currency amount are stored. The exchange rate is derived from these two amounts for display purposes but is not stored separately.
- The default currency is pre-selected based on the user's language (EUR for French, USD otherwise).

### 10.3 Currency in Calculations

- **Balance calculations** use the `defaultCurrencyAmount` for normalization.
- **Settlement plans** use the group's default currency.
- **Entry display** shows both original and converted amounts when they differ (e.g., "5.00 EUR ($6.00)").

### 10.4 Currency Formatting

- Amounts are formatted with the currency symbol and **locale-aware decimal and grouping separators** (e.g., `€10.50` / `1,234.56` in English, `10,50 €` / `1 234,56` in French) and the currency-specific precision (e.g., `¥1050` with no fractional part).
- Formatting is done in Elm against per-language locale config; no dependency on `Intl.NumberFormat`.

---

## 11. Encryption & Security

### 11.1 Encryption Architecture

The application uses a **two-layer encryption model**:

| Layer | Content | Encrypted? |
|---|---|---|
| **Sync metadata** | Server sequence numbers, `groupId`, `actorId`. | No (strictly necessary for sync relay and access control). |
| **Everything else** | Everything else. | Yes (AES-256-GCM). |

### 11.2 Cryptographic Primitives

| Purpose | Algorithm | Parameters |
|---|---|---|
| Data encryption | AES-256-GCM | 256-bit key, 12-byte random IV, built-in authentication tag. |
| Digital signatures | ECDSA P-256 with SHA-256 | Chosen for Web Crypto API compatibility across browsers. |
| Hashing | SHA-256 | Used for public key hashing, PoW, password derivation. |

### 11.3 Event Signing

Every event is **cryptographically signed** by its author:

- **Canonicalization:** the received envelope JSON with the `sig` field removed, other fields kept verbatim in their received order. Verifiers never re-encode the decoded payload, so events carrying fields or types from a newer app version keep valid signatures on older clients.
- **Signing:** the author serializes the envelope (event ID, timestamp `ts`, author `by`, schema version `v`, optional author key `key`, payload `p`) to compact JSON and signs it with its ECDSA P-256 private key (SHA-256).
- **Key introduction:** an envelope that establishes its author's signing key — the author's own `MemberCreated` or `MemberLinked` — carries that key in the envelope-level `key` field. Verifiers collect keys only from this field (plus existing group state), never from payloads, so key learning is part of the frozen envelope contract and works even when the payload is a newer type the client cannot decode.
- **Key immutability:** a key, once established for a member or device id, never changes. Keys already known from group state always win over keys carried by an incoming batch, and within a batch the earliest introduction in sort order wins — so a crafted envelope cannot remap an existing member's id to another key. Residual (trust-on-first-use): a device joining with empty state trusts the earliest key introduction it sees; a group member could backdate a forged introduction to poison later joiners. Accepted within the trusted-group threat model.
- **Verification:** on receipt, the signature is verified against the author's stored public key. Events with invalid signatures are rejected during state computation.
- **Genesis exception:** `GroupCreated` events bypass signature verification (no prior state to look up public keys).

### 11.3b Forward Compatibility

Clients must tolerate events authored by newer app versions:

- Envelopes carry a schema version field `"v"` (absent = 1) for future "update required" messaging.
- An envelope is passed through encoding, local storage, and export as the raw JSON it was decoded from, so fields unknown to this client survive round trips.
- A payload that fails to decode (unknown type, or a known type whose shape changed) becomes an **Unknown** event: it still verifies and persists, state computation ignores it, the activity feed shows a generic "update the app" line, and the group view shows a persistent warning banner. After an app update the stored raw JSON decodes normally — no data is lost.
- A pulled record that fails to decrypt, or an envelope whose JSON shape cannot be decoded, is skipped and counted (surfaced via the error log); the sync cursor always advances, so one corrupt or malicious record can never permanently break a group's sync. Records are skipped even when every record in a pull fails: the group key is immutable after joining (a wrong key would have failed at join time), so mass decrypt failure means garbage records, not a key mismatch.

Deliberate limitations of this mechanism:

- **Signature-algorithm changes.** Key introduction is envelope-level (see [11.3](#113-event-signing)), so a member who joins via an event type unknown to an outdated client still gets their key registered there and their subsequent events verify. What this cannot absorb is a new *signature algorithm*: an outdated client cannot verify signatures it doesn't implement, and events failing verification are dropped at pull time without being persisted, so an app update alone does not recover them (recovery needs a full re-pull, i.e. re-joining via invite link or importing a fresh export). **Constraint on future releases: shipping a new signature algorithm must come with a healing mechanism, e.g. a one-time full re-pull.**
- **Edits from outdated clients.** `EntryModified` carries the full re-encoded entry, so an outdated client editing an entry silently drops entry fields it doesn't know about. Accepted as disproportionate to fix for a fast-updating PWA fleet.
- **Envelope-level changes.** Adding envelope fields is safe (canonicalization preserves unknown fields). A breaking change to the envelope shape itself requires bumping `"v"` and gating on it with an "update required" message.

### 11.4 Key Management

- Each group has a **single symmetric key** (AES-256) shared by all members.
- The group key is distributed via **URL fragments** (see [Invitation](#12-invitation--group-joining)).
- Group keys are stored locally in IndexedDB.

### 11.5 Server Authentication

- There are no server accounts or sessions. Every request carries a **bearer secret deterministically derived** from the group key: `Base64URL(SHA-256(Base64(groupKey)))`.
- At group creation the client registers a verifier, `Base64URL(SHA-256(secret))`; the server stores only this hash and compares it (in constant time) against the hash of each presented secret.
- This means anyone with the group key can authenticate to the server for that group, without any additional credentials — and a leaked bearer secret grants relay access but never reveals the group key.

### 11.6 What the Server Can See

The server can only see:
- Record sequence numbers and receive timestamps (used for sync cursoring).
- The `groupId` and `actorId` fields (needed for access control and relay).
- The size and frequency of encrypted events.
- Which server accounts exchange data (but not the identities behind them).

Everything else is encrypted and opaque to the server.

---

## 12. Invitation & Group Joining

### 12.1 Invite Link Structure

Invite links have the format:

```
https://<app-domain>/join/<groupId>#<base64url-encoded-group-key>
```

- The **group ID** is in the URL path (sent to the server).
- The **group key** is in the URL **fragment** (after `#`), which is **never sent to the server** by the browser.
- The key uses **Base64URL encoding** (URL-safe characters, no padding).

### 12.2 Invite Link Sharing

- The invite modal provides:
  - A **QR code** containing the full invite link (dynamically generated as SVG).
  - A **"Copy link"** button.
  - Integration with the **Web Share API** (on supported devices).
- A security notice reminds users to share links only via trusted channels.

### 12.3 Joining Flow

When a user opens an invite link:

1. The app extracts the group ID from the URL path and the group key from the fragment.
2. If no identity exists, one is automatically generated.
3. The app authenticates to the server using the derived password.
4. All historical encrypted data is fetched and decrypted locally.
5. The user sees the group name and member list.
6. The user can:
   - **Claim a virtual member** (primary path, if unclaimed virtual members exist).
   - **Re-join as an existing real member** (separate section, for device migration).
   - **Join as a new member** with a new display name (duplicate names must be prevented).
7. A member event is recorded and synced.

---

## 13. Import / Export

### 13.1 Export

Two export formats are available per group from the home screen:

- **Full group export (JSON)** — contains all decrypted data (entries, members, metadata, events, audit trail). Compressed (gzip) before download. Metadata includes export timestamp and version. Intended for backup or transferring a group to another device.
- **CSV expense export** — a flat, spreadsheet-friendly view of the group's entries with one row per active entry: date, kind, description, amount, currency, default-currency amount, payers, beneficiaries, category, location, notes, and creator. Intended for accounting or external analysis, not for re-import.

### 13.2 Import

- Users can import a previously exported full-group JSON file.
- If the group already exists locally, the import is rejected (duplicate group ID).
- After import, the user can **re-join** the imported group with their current identity (via a new invite link or by replaying the join flow on the imported state), reusing the same local copy.
- If the user has imported a group they are **not a member of**, the group is shown in **read-only mode**: a banner is displayed and all mutating actions (add entry, edit member, etc.) are hidden. The user must join the group to make changes.
- **Future work:** Merge analysis for overlapping groups (detect `local_subset`, `import_subset`, `diverged` relationships and merge by taking the union of all events deduplicated by event ID).

---

## 14. Offline & Synchronization

### 14.1 Local-First Architecture

- All operations (add, modify, delete entries; manage members) are **applied immediately to local state**.
- The application is fully functional without an internet connection.
- Data is persisted in **IndexedDB** across sessions.

### 14.2 Local Storage

The following data is stored locally per group in IndexedDB:

| Store | Content |
|---|---|
| `identity` | User's cryptographic keypair, language preference, notification translations. |
| `groups` | Group summaries (name, currency, member count, balance, archive state). |
| `groupKeys` | Symmetric encryption keys per group. |
| `events` | The full append-only event log per group, indexed by group ID. Each row is `{ id, groupId, env }` where `env` is the raw envelope JSON as received or authored — stored verbatim so events from newer app versions survive and re-decode after an update (see [11.3b](#113b-forward-compatibility)). |
| `syncCursors` | Last sync cursor per group (server-assigned `seq` integer). |
| `unpushedIds` | Set of event IDs created locally but not yet pushed to server. |
| `usageStats` | Network and storage tracking data. |

### 14.3 Synchronization

- The server acts as a **relay** for encrypted events.
- **Initial sync**: Fetches all historical events (paginated, 200 per page) and replays them in deterministic order to build local state.
- **Incremental sync**: Pushes local unpushed events and pulls remote events since last cursor.
- **Real-time subscriptions**: The app subscribes to server-sent events via WebSocket for live updates from other devices/users.
- **Offline queue**: Events created while offline are queued (tracked in `unpushedIds`) and synced when connectivity returns. Groups **created** while offline are also queued and registered on the server when connectivity returns (the server account is created on the first successful push).

### 14.4 Event Compression & Batching

Event data is **compressed and batched** before encryption to reduce bandwidth and storage:

- Compression uses gzip (via the browser's `CompressionStream` API).
- Compression is applied conditionally: the compressed payload is kept only when it is at least **30% smaller** than the uncompressed version, otherwise the original bytes are stored uncompressed.
- A `compressed` flag on each record indicates whether decompression is needed on read.
- **Batching:** Multiple unpushed events are flushed into a single compressed+encrypted record on a periodic timer (current cadence: every ~100 seconds), as well as on explicit user actions and when transitioning back online.
- JSON wire identifiers in encoded events are kept short to further reduce payload size.

### 14.5 Event Ordering & Conflict Resolution

All group state is derived by replaying the **immutable event log** in a deterministic total order.

**Ordering rule:** Each event is assigned a **UUID v7** identifier at creation time. UUID v7 embeds a millisecond-precision timestamp in its most significant bits, followed by random bits. Events are sorted by timestamp then event ID, providing a deterministic total order that naturally reflects creation time. Since groups are trusted, client-generated UUIDs are authoritative. All clients use the same comparison function after decryption, guaranteeing convergence.

**Timestamp clamping:** When authoring an event, a device clamps its timestamp to sort strictly after the latest event it has already applied (a Lamport-style clock). A device whose wall clock runs behind another member's therefore cannot produce an event that sorts before state it has already seen — such an event would take effect on live devices but be ignored by every subsequent full replay.

**State computation:** Events are replayed in sort order. Each event is validated against the current state at the point of replay. Invalid events are **silently ignored** (see [4.5](#45-member-operation-rules)). This ensures all clients converge to identical state regardless of the order in which events were received over the network.

**Conflict categories:**

The following concurrent event pairs are **order-dependent** (their outcome depends on which is processed first). Deterministic ordering resolves them automatically:

| Category | Conflicting pair | Resolution |
|---|---|---|
| **Member lifecycle** | `retire`/`unretire` interleaving (same member) | Processed in sort order; each is validated against the member's state at that point. |
| **Entry versioning** | Concurrent modifications (same `rootId`) | Deepest-chain-wins. The current version is the version with the greatest `depth`; equal depths are broken by the greater version `id` (see [5.7](#57-entry-versioning)). |
| **Entry versioning** | Modify + delete (same `rootId`) | Last-writer-wins. The event with the later timestamp determines whether the entry is modified or deleted. |
| **Last-writer-wins** | Concurrent renames (same member) | Latest timestamp determines the current name. |
| **Last-writer-wins** | Concurrent metadata updates (same member or group) | Latest timestamp determines the current value. |
| **Target vs. create** | Any event referencing an entry or member vs. the event creating it | The referencing event is ignored when it sorts before the create. Timestamp clamping prevents honest clients from producing this ordering. |

**Non-conflicting operations** (always commutative, order-independent):

- Creating new entries (different `rootId`s).
- Creating new members (different member IDs).
- Device links: the winning link per device is the maximum by `(seq, timestamp, event ID)` — a total order, so the outcome is the same regardless of processing order.
- Any events targeting different entities.

### 14.6 Incremental Sync Optimization

When new events arrive via sync, a **full replay** from scratch is not always necessary:

- **In-order events** (timestamp ≥ max existing timestamp): Always safe to apply directly on top of current state. No replay needed.
- **Late-arriving events** (timestamp < max existing timestamp): Safe to apply directly **only if** they target entities with no later-timestamped events in the conflict categories above (member lifecycle, same-entry versioning, or target vs. create). Otherwise, a replay from scratch is required.

In practice, late arrivals involving lifecycle conflicts are extremely rare (they require two users to retire/unretire the same member within a short offline window). The vast majority of syncs hit the fast path.

**Computed state caching:** The materialized group state is cached locally. On app load, if the event log has not changed, the cached state is used directly. Otherwise, the state is recomputed from the full event log.

### 14.7 Connectivity Indicators

- An **offline banner** (with Wi-Fi icon) appears when the app detects loss of connectivity.
- The banner is accessible (`role="alert"`, `aria-live="polite"`).
- The app automatically re-subscribes and syncs the offline queue when connectivity is restored.

---

## 15. Push Notifications

### 15.1 Architecture

The application supports **web push notifications** to alert members of group activity, even when the app is not open.

- Push notifications are delivered via an external push relay server.
- The client fetches a **VAPID public key** from the push server at startup.
- Each member subscribes to push notifications on a per-group basis, using the topic format `{groupId}-{memberRootId}`.

### 15.2 Notification Triggers

After a successful event sync, the client sends push notifications to affected members:

- **Affected members** are extracted from event payloads (payers, beneficiaries, transfer participants, etc.).
- The actor (who triggered the event) is excluded from notifications.
- Notifications are deduplicated per unique member.

### 15.3 Notification Localization

Push notification messages are localized in the service worker:

- Translation templates are stored in IndexedDB (under the `identity` store with key `notificationTranslations`).
- Templates are updated whenever the user changes their language.
- The service worker reads templates at display time and interpolates variables (e.g., `{name}` → actor's display name).
- Falls back to English if translations are unavailable.

### 15.4 Notification Types

| Type Key | Trigger |
|---|---|
| `expense_added` | A new expense is created. |
| `transfer_added` | A new transfer is created. |
| `income_added` | A new income entry is created. |
| `expense_modified` | An existing expense is edited. |
| `transfer_modified` | An existing transfer is edited. |
| `income_modified` | An existing income entry is edited. |
| `entry_deleted` | An entry is deleted. |
| `member_joined` | A new member joins the group. |

### 15.5 User Controls

- Users can enable or disable push notifications per group from the Members tab.
- Notification permission is requested via the browser's standard permission flow.
- The subscription state is tracked locally.

### 15.6 Privacy Trade-offs and Future Directions

Push is a deliberate exception to the zero-knowledge model:

- Notification metadata — the group name (title), the actor's display name, and the
  event kind — is sent in **plaintext** to the push relay, which is a shared
  third-party server, not part of a Partage deployment.
- The push relay's notify endpoint is **unauthenticated**: anyone who knows a topic
  string (`{groupId}-{memberRootId}`) can send notifications to that member.

Two future stages would close these gaps. In any design, recipient computation stays
client-side: only the sending client can read events, so only it knows which members
are affected.

1. **Fold push into the relay server**, replacing the external push relay: a
   subscriptions table stored next to the group's event log, subscribe/unsubscribe
   and notify routes authenticated with the group bearer secret, and per-instance
   VAPID keys (env/secrets). Sending uses the `web-push` package on Node and a
   WebCrypto implementation of VAPID + RFC 8291 on Cloudflare (ES256 and the
   ECDH/HKDF primitives are all available). This removes the third-party dependency
   and keeps notification metadata within the operator's own instance.
2. **Fully zero-knowledge push** (later hardening): distribute each member's push
   subscription (endpoint + keys) inside the encrypted event log and have the
   *sending client* perform the RFC 8291 payload encryption itself; the server then
   only VAPID-signs and forwards an opaque blob, seeing endpoint URLs but no
   content. This costs real complexity — RFC 8291 in the client, subscription churn
   propagating through the event log, stale-subscription cleanup — and since stage 1
   already makes the push operator the group's own relay host, the remaining trust
   gap is small. Documented as a possibility, not planned.

---

## 16. Progressive Web App (PWA)

### 16.1 Installation

- The app can be **installed** on any device as a standalone application.
- **Android / Desktop Chrome**: The native browser install prompt is intercepted and presented as a custom UI.
- **iOS**: Manual installation instructions are shown (with step-by-step guide) after a delay.
- **macOS Safari**: Dedicated manual installation hint, since the native prompt is unavailable.
- The install prompt is **dismissible** and re-appears after a cooldown period.
- The prompt is not shown if the app is already running in standalone mode.

### 16.2 Standalone Mode

- When installed, the app runs in **standalone** display mode (no browser chrome).
- Portrait orientation is preferred.
- The viewport uses `100dvh` (dynamic viewport height) to correctly account for mobile browser UI bars.

### 16.3 Service Worker

- The service worker provides **offline caching** with the following strategies:
  - **Cache-first** for static assets (JS, CSS, HTML, SVG, WASM, JSON) and fonts.
  - **Network-first** for API calls.
- **Auto-update**: The service worker updates automatically. The app handles `SKIP_WAITING` for seamless transitions.
- Navigation fallback to `index.html` for SPA routing.
- The service worker also handles **push notification display** with localized message interpolation (see [Push Notifications](#15-push-notifications)).

### 16.4 App Metadata

- App name: "Partage - Bill Splitting"
- Short name: "Partage"
- Categories: finance, utilities.
- Icons: SVG with maskable variants for adaptive displays.
- Apple-specific meta tags for iOS web app support.

---

## 17. Internationalization (i18n)

### 17.1 Supported Languages

| Code | Language | Status |
|---|---|---|
| `en` | English | Supported |
| `fr` | French | Supported |

Spanish support is **deferred** (see Appendix B) and is not currently selectable.

### 17.2 Language Detection & Persistence

- On first visit, the language is **auto-detected** from the browser's locale (`navigator.language`).
- The selected language is **persisted** in IndexedDB (under the `identity` store).
- A **language switcher** is available on the welcome page, the join page, and the About page.

### 17.3 Translation Coverage

- All UI text, labels, buttons, error messages, and toast notifications are translated.
- ~330 translation keys per language.
- Interpolation is supported: `{paramName}` placeholders in translation strings.
- Translations are generated at build time using the **travelm-agency** tool from source JSON files.

### 17.4 Locale-Aware Formatting

| Format | Description |
|---|---|
| Currency | Symbol prefix with precision-aware decimal formatting (e.g., "€10.50", "¥1050"). |
| Date | Short and long date formats with localized month names. |
| Numbers | Currency-appropriate decimal separators. |
| Date grouping | Labels like "Today", "Yesterday", month names in the active language. |

---

## 18. Usage Statistics

### 18.1 Tracked Metrics (Local Only)

The application tracks usage statistics **locally** (never sent to the server):

| Metric | Description |
|---|---|
| Total bytes transferred | Cumulative network bandwidth used (tracked via PerformanceObserver). |
| Storage size | Estimated storage consumption via `navigator.storage.estimate()` (updated at most once per day). |
| Tracking start date | When tracking began. |

### 18.2 Cost Estimation

The app estimates the user's share of infrastructure costs:

| Component | Rate |
|---|---|
| Base cost | $0.10 / month / user |
| Storage | ~$0.10 / GB / month |
| Bandwidth | ~$0.10 / GB |
| Compute | 5x the storage cost |

- A **cost breakdown** is displayed on the About screen.
- Shows: base, storage, compute, network costs, total, and average per month.

### 18.3 Reset

- Users can **reset** their usage statistics (e.g., after making a donation).

---

## 19. Navigation & Screens

### 19.1 Routing

| Route | Screen | Auth Required |
|---|---|---|
| `/` | Welcome landing page (also `/welcome`) | No |
| `/groups` | Group selection (home) | Yes |
| `/groups/new` | Create new group | Yes |
| `/join/:groupId#key` | Join group via invite link | No (auto-generates identity if needed) |
| `/groups/:groupId` | Group view - Balance tab | Yes |
| `/groups/:groupId/entries` | Group view - Entries tab | Yes |
| `/groups/:groupId/entries?highlight=:entryId` | Entries tab with highlighted entry | Yes |
| `/groups/:groupId/members` | Group view - Members tab | Yes |
| `/groups/:groupId/activity` | Group view - Activities tab | Yes |
| `/groups/:groupId/new-entry` | New entry form | Yes |
| `/groups/:groupId/entries/:entryId/edit` | Edit entry form | Yes |
| `/groups/:groupId/members/new` | Add virtual member | Yes |
| `/groups/:groupId/members/:memberId/edit` | Edit member metadata | Yes |
| `/groups/:groupId/members/:sourceId/merge` | Member merge - pick target | Yes |
| `/groups/:groupId/members/:sourceId/merge/:targetId` | Member merge - preview & confirm | Yes |
| `/groups/:groupId/settings` | Edit group metadata | Yes |
| `/about` | About & usage stats | No |
| `/error-log` | In-memory error log & debug report | No |
| `*` (catch-all) | NotFound screen | - |

### 19.2 Route Guards

- **Identity required**: Routes that need a user identity redirect to `/` (the welcome page) if no identity exists.
- **Welcome page**: When the user already has an identity, the welcome page still renders but exposes a shortcut to `/groups`. Once identity is generated from the welcome page, the user is sent to `/groups`.
- **Join exception**: The join route is accessible without an identity; one is auto-generated before proceeding.
- **About / Error log**: Accessible regardless of identity, so the user can read about the app or copy a debug report even when they have no groups.

### 19.3 Screen Descriptions

| Screen | Purpose |
|---|---|
| **WelcomeScreen** | Public landing page. Explains the app, lists features and screenshots, offers identity generation, language switcher, and a funding/sponsorship link. Doubles as the entry point for SEO. |
| **GroupSelectionScreen** | Home screen for users with an identity. Lists all groups with name, date, member count, and color-coded balance badge. Provides JSON export, CSV expense export, JSON import, and group removal. Archived groups shown in collapsible section. |
| **CreateGroupScreen** | Group creation form with name, creator name, currency, and optional virtual members. Includes PoW solver with progress feedback. |
| **JoinGroupScreen** | Invite acceptance. Shows group info, virtual/real member lists, and new member form. Includes a language switcher. |
| **GroupViewScreen** | Main group interaction with 4 tabs (Balance, Entries, Members, Activities). Header shows group name, subtitle, and user's balance summary. Floating Action Button for adding entries. Shows a read-only banner when the user is not a member of an imported group. |
| **NewEntryScreen** | Entry creation/editing form. Supports expense, transfer, and income entry types with type switcher. Also reached via the **Duplicate** action on an entry. |
| **AddMemberScreen** | Form to add a virtual (placeholder) member to the group. Prevents duplicate names. |
| **EditMemberMetadataScreen** | Form to edit a member's display name, contact info, and payment methods. For the current user, also exposes **Pre-fill from saved profile** and **Save as my profile** actions to share metadata across groups. Prevents duplicate names on rename. |
| **MergeMemberScreen** | Two-step page to merge one member into another (pick target, then preview effects and type-to-confirm). |
| **EditGroupMetadataScreen** | Form to edit group name, subtitle, description, links, and archive state. |
| **AboutScreen** | App information, motivation, privacy info, usage statistics, language switcher, and links to GitHub, Sponsors, and Discussions (each opening in a new tab). |
| **ErrorLogScreen** | Displays in-memory error entries collected during the session. Provides **Copy** and **Share** buttons to send a debug report (via the Web Share API when available). |

### 19.4 Tab System (GroupViewScreen)

| Tab | Features |
|---|---|
| **Balance** | Per-member balance cards (color-coded). Settlement plan with "Record Transfer" buttons and payment method display. Settlement preference editor. |
| **Entries** | Entry list with cards (expenses, transfers, income). Search bar + filters (person, category, currency, date). Toggle deleted entries. Click to view details / edit / duplicate / delete. Total amount counts expenses only (transfers and income excluded). Active filters are summarized when collapsed. |
| **Members** | Member list with metadata indicators. Invite button with QR code, Copy link, and Web Share. Add virtual member. Merge member. Group info section. Member detail with name editing, contact and payment info. Group metadata editing. Notification toggle. |
| **Activities** | Activity feed (newest first, grouped by date). Activity type, actor, and involved member filters. Active filters are summarized when collapsed. Each entry-related activity links back to the entry via deep link. |

---

## 20. Accessibility & UX Details

### 20.1 Accessibility

- The offline banner uses `role="alert"` and `aria-live="polite"` for screen reader compatibility.
- Form inputs include proper labels and error states.
- Buttons use semantic HTML; in-app navigation uses real `<a href>` anchors to preserve middle-click, copy-link, and screen-reader navigation.
- Color-coded elements (balances) also use text indicators (+/-/settled).

### 20.2 Toast Notifications

- In-app toast notifications for success/error feedback (e.g., "Entry added", "Error saving").
- Toasts auto-dismiss after a configurable duration.
- Multiple toasts can stack.

### 20.3 Confirmation Dialogs

- Destructive actions (delete entry, remove group) require explicit confirmation.

### 20.4 Loading States

- Spinner displayed during: identity generation, PoW solving, group creation, data syncing.
- Buttons show "Recording..." state during settlement recording.
- Forms are disabled during submission.

### 20.5 Error Handling

- Form validation errors displayed per-field.
- Network errors surface as toast notifications.
- PoW solving errors displayed with retry option.
- Identity generation errors displayed prominently on setup screen.

### 20.6 Responsive Design

- Mobile-first design.
- Full-width inputs and stacked layouts on mobile.
- Side-by-side layouts on tablet/desktop.
- Maximum container width on larger screens.
- Touch-friendly button sizes.
- Floating Action Button for primary actions on mobile.

---

## Appendix A: Expense Category List

| Category |
|---|
| Food |
| Transport |
| Accommodation |
| Entertainment |
| Shopping |
| Groceries |
| Utilities |
| Healthcare |
| Other |

## Appendix B: Out-of-Scope Features (Documented for Future)

The following features are explicitly **not** in scope currently but are documented as potential future additions:

- Receipt photo attachments and OCR. In tension with open source and free app hosting.
- Recurring expenses and budgets.
- Push notifications enhancements: privacy hardening (see [15.6](#156-privacy-trade-offs-and-future-directions)) and refinements based on usage feedback.
- Analytics and spending charts.
- Import from other bill-splitting apps (Splitwise, Tricount, etc.).
- PDF / CSV export.
- Trust-minimized groups.
- Spanish language support (temporarily deferred).
- Full locale-aware currency formatting via `Intl.NumberFormat`.

## Appendix C: Client-Server Architecture

This appendix documents the boundary between the client (PWA) and the server (relay), to support independent reimplementation of either side.

### C.1 Server Overview

The server is a **purpose-built minimal relay** ([`packages/relay`](../packages/relay)): a small web-standard HTTP + WebSocket app over an append-only SQLite store of encrypted blobs. It stores ciphertext, enforces per-group access control, rate-limits group creation with a proof-of-work gate, and notifies connected clients when new records arrive. It has **no business logic** about entries, members, balances, or any application-level concept.

One portable core runs on two adapters:

- **Self-host:** a single Node process (Node ≥ 22.5) with one SQLite file and in-process WebSocket topics; optionally serves the built frontend.
- **Cloudflare:** a Worker routing each group to its own SQLite-backed Durable Object with hibernating WebSockets; the frontend is served as same-origin static assets.

### C.2 Server Database Schema

**`groups`** — one row per group.

| Field | Type | Description |
|---|---|---|
| `id` | string (primary key) | Client-generated group identifier (15-character alphanumeric). |
| `created_by` | string | Public key hash of the group creator (unencrypted). |
| `auth_verifier` | string | Hash of the group's bearer secret (see [C.5](#c5-authentication)). |
| `pow_challenge` | string | The solved PoW challenge (audit trail). |
| `created` | string (ISO 8601) | Creation timestamp. |

**`events`** — append-only log of encrypted event batches.

| Field | Type | Description |
|---|---|---|
| `seq` | integer (autoincrement) | Server-assigned sync cursor. Strictly monotonic per group, not necessarily dense. |
| `group_id` | string | Links the record to a group. |
| `actor_id` | string | Public key hash of the user who pushed the record. |
| `data` | string (max 1 MB) | JSON `{ciphertext, iv}`: base64, AES-256-GCM encrypted payload (may contain multiple batched events). |
| `compressed` | bool | Whether the payload was gzip-compressed before encryption. |
| `created` | string (ISO 8601) | Server receive time (informational only). |

The encrypted payload contains all application-level data, including the **UUID v7 event identifier** used for deterministic ordering (see [14.5](#145-event-ordering--conflict-resolution)). The server never sees these values.

### C.3 Server API

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `GET` | `/api/pow/challenge?groupId={id}` | none | Get a PoW challenge bound to the groupId. Returns `{challenge, timestamp, difficulty, signature}`. |
| `POST` | `/api/groups` | PoW | Create a group. Body: `{groupId, createdBy, authVerifier}` plus the solved challenge fields (`pow_challenge`, `pow_timestamp`, `pow_difficulty`, `pow_signature`, `pow_solution`). `201` on success, `400` on invalid PoW, `409` if the group already exists. |
| `GET` | `/api/groups/{id}/events?since={seq}` | bearer | Pull records with `seq > since`, ascending, at most 200 per page. Returns `{events: [{seq, actorId, eventData, compressed, created}], hasMore}`. |
| `POST` | `/api/groups/{id}/events` | bearer | Append one encrypted batch: `{actorId, eventData, compressed}`. Returns `{seq}` with status `201`. |
| `WS` | `/api/groups/{id}/ws?auth={secret}` | secret | Live updates: the server sends `{seq}` whenever a record is appended to the group. A notified client reacts with a normal authenticated pull from its cursor. |

Records can never be updated or deleted through the API — the event log is append-only by construction.

### C.4 Proof-of-Work Gate (anti-spam)

Group creation is public but rate-limited by a stateless PoW scheme:

- The challenge endpoint returns `{challenge, timestamp, difficulty: 18, signature}` where `signature = HMAC-SHA256(challenge:groupId:timestamp:difficulty, POW_SECRET)`. The server stores nothing.
- The client brute-forces a `solution` such that `SHA-256(challenge + solution)` has `difficulty` leading zero **bits**.
- On group creation the server recomputes the HMAC (over the groupId being created), enforces a 10-minute TTL, and verifies the leading-zero-bits condition.
- Replay is useless without server-side state: a signed challenge only fits one groupId, and that group can only be created once.

### C.5 Authentication

There are no accounts and no sessions:

- The bearer secret is derived from the group key as `Base64URL(SHA-256(Base64(groupKey)))` (see [11.5](#115-server-authentication)).
- At group creation the client sends `authVerifier = Base64URL(SHA-256(secret))`; the server stores only this hash.
- Every HTTP request carries `Authorization: Bearer {secret}`; the server hashes it and compares against the stored verifier in constant time. The WebSocket route passes the secret as the `auth` query parameter instead, because the browser WebSocket API cannot set headers.
- `401` means the credentials are wrong; `404` means the group does not exist on this server.

### C.6 Client Responsibilities

The client handles **all** application logic:

| Responsibility | Details |
|---|---|
| **Cryptography** | Key generation (ECDSA P-256), AES-256-GCM encryption/decryption, event signing and verification, bearer-secret derivation, PoW solving. |
| **Event sourcing** | Encoding changes as immutable events, replaying events in deterministic order (by timestamp and event ID after decryption), computing current state from the event log. |
| **Business logic** | Entry management, member state computation, balance calculation, settlement planning, activity feed generation. |
| **Local storage** | IndexedDB for identity, group keys, event log, computed state cache, pending events, sync cursors, and usage statistics. |
| **Sync management** | Pushing local events (with optional compression), pulling remote events (using the server `seq` as sync cursor), offline queue, live-update subscription handling. |
| **Push notifications** | Sending push notifications to affected members after sync, managing subscriptions, localizing notification messages. |
| **UI & routing** | All screens, navigation, forms, modals, i18n, PWA installation, service worker. |
