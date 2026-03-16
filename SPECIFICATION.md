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

- On first launch, the user is presented with a **setup screen**.
- The application generates a **cryptographic keypair** locally in the browser using **ECDSA P-256** (chosen for broad Web Crypto API compatibility across browsers).
- The keypair is used for **digital signatures** (to authenticate operations).
- The **public key hash** (SHA-256 of the public key) serves as the user's anonymous, unique identifier.
- No username, email, or password is required.

### 2.2 Identity Storage

- The keypair is stored in the browser's local database (IndexedDB), serialized as JWK (JSON Web Key).
- There is exactly **one identity per browser profile**.
- The identity persists across sessions until the browser data is cleared.

### 2.3 Identity Recovery

- **There is no password recovery mechanism.** If the browser data is lost, the identity is lost.
- The user can rejoin groups via a new invite link, but they will appear as a new member.
- The user can link their new identity to any previous member entry (see [Member Aliases](#44-member-aliases)).

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
| `MemberCreated` | A new member is added (real or virtual). Records member ID, name, member type, who added them, and public key. |
| `MemberRenamed` | A member's display name is changed. Records root ID, old and new names. |
| `MemberRetired` | A member is marked as departed/inactive. Records root ID. |
| `MemberUnretired` | A retired member is reactivated. Records root ID. |
| `MemberReplaced` | A new real member claims an existing member's identity (see [Member Aliases](#44-member-aliases)). Records root ID, previous member ID, new member ID, and public key. |
| `MemberMetadataUpdated` | A member's contact or payment information is updated. Records root ID and full metadata. |
| `SettlementPreferencesUpdated` | A member's settlement preferences are updated (preferred payment recipients). Records member root ID and ordered list of preferred recipients. |

### 4.3 Computed Member State

From the event log, each member chain has a computed state:

| Property | Description |
|---|---|
| `rootId` | The ID of the first member in the replacement chain. Equals the member's own ID if they have not replaced anyone. Serves as the stable identifier for the chain. |
| `name` | Current display name (latest rename, or creation name). |
| `isRetired` | True if the latest lifecycle event is `MemberRetired`. |
| `joinedAt` | Timestamp when the member was created. |
| `metadata` | Contact and payment information (see [4.6](#46-member-metadata-encrypted)). |
| `currentMember` | The winning device identity in the chain (determined by depth, then ID as tiebreaker). |
| `allMembers` | Dictionary of all device identities in the chain, keyed by member ID. |

A member is considered **active** if they are not retired and not replaced (i.e., no other member's `previousId` points to them).

### 4.4 Member Aliases (Identity Claiming)

When a real user joins a group, they can **claim the identity of any existing group member** (virtual or real):

- A `MemberReplaced` event records the link between the new member and the claimed member. The new member stores a **backward pointer** (`previousId`) to the member it replaced.
- The new member inherits the **rootId** of the claimed member. This links the entire replacement chain to a single stable identifier — the rootId — which is always the ID of the **first member** in the chain.
- Each member in the chain has a **depth** (0 for the original, incremented for each replacement). When multiple replacements exist concurrently, the **current member** is determined by highest depth, with member ID as a lexicographic tiebreaker.
- **Example:** If member A (rootId=A) is replaced by B, then B.rootId=A and B.previousId=A. If B is later replaced by C, then C.rootId=A and C.previousId=B. All three share the same rootId. Whether A or B is replaced is computed by checking if any member's `previousId` points to them.
- The rootId is used throughout the application as the **stable identifier** for a member chain: balance calculations, activity feeds, entry displays, and settlement plans all aggregate by rootId.
- **Name resolution:** Although the rootId identifies the chain, the **display name** is always resolved to the newest active (non-replaced) member's current name in the chain. For example, if virtual member "Alice" (rootId=A) was claimed by real member "Alice R." (rootId=A), the display name everywhere is "Alice R." — even for historical entries originally involving the virtual member.
- In the join UI, claiming a **virtual member** is the primary path (prominently displayed). Claiming a **real member** is available in a separate section, intended for device migration or identity recovery scenarios.

### 4.5 Member Operation Rules

Member operations follow strict validation rules. Invalid events are **silently ignored** during state computation, which is intentional for deterministic convergence (different replicas may receive events in different orders, but replay them in the same deterministic sort order).

| Operation | Valid When | Invalid When |
|---|---|---|
| **Create** | No chain with this rootId already exists. | Duplicate member ID. |
| **Rename** | Chain with the given rootId exists. | Chain does not exist. |
| **Retire** | Chain exists and member is not already retired. | Chain does not exist, or is already retired. |
| **Unretire** | Chain exists and member is currently retired. | Chain does not exist, or is not retired. |
| **Replace** | Chain exists, `previousId` exists in chain, `newId` is not already in chain, and `previousId != newId`. | Chain does not exist, previous member not found, new ID already in chain, or self-replacement. |

**Authorization rules:**
- `GroupCreated`: Always allowed.
- `MemberCreated`: Allowed if the member is creating themselves, or the actor is an existing group member.
- `MemberReplaced`: Allowed if the actor is the new member (asserting their own identity).
- All other operations: The actor must be an existing group member.

Key design principles:
- **State transitions**: Active members can be retired or replaced. Retired members can be unretired. Replaced members are terminal (cannot be retired, unretired, or replaced again).
- **Root ID resolution**: Replacement chains share a stable rootId (the first member's ID). The display name is always resolved to the newest active member's name in the chain.

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

### 4.7 Member Display Order

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
| `id` | Unique UUID v7 for this version. |
| `rootId` | UUID of the original entry in the chain. |
| `previousVersionId` | UUID of the prior version (if this is a modification). |
| `depth` | Chain depth (0 for the original, incremented for each modification). |
| `isDeleted` | Whether this version represents a deletion. |
| `createdBy` | Member ID of the author. |
| `createdAt` | Timestamp of creation. |

- Entries can be **modified** by creating a new entry linked to the original.
- The modification records: who modified it, when, and the full new data.
- **Current version rule:** For a given `rootId`, the current version is the **non-deleted version with the latest UUID v7** (which encodes creation timestamp). This makes concurrent modifications resolve deterministically via last-writer-wins. The `previousVersionId` is used for audit trail display and diff computation, not for determining the current version.

### 5.8 Entry Deletion & Restoration

- Entries can be **soft-deleted** (creating a new version with deleted status via `EntryDeleted` event).
- Deleted entries are hidden by default but can be shown via a toggle.
- Deleted entries can be **restored** (via `EntryUndeleted` event).
- Deleted entries are excluded from balance calculations.

### 5.9 Form Validation Rules

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
- Member IDs are resolved to their **root member IDs** (accounting for aliases/replacements, see [Member Aliases](#44-member-aliases)).
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
| `EntryAdded` | A new expense or income is created. |
| `EntryModified` | An existing expense or income is edited. Records field-by-field changes. |
| `TransferAdded` | A new transfer is created. |
| `TransferModified` | An existing transfer is edited. Records field-by-field changes. |
| `EntryDeleted` | An entry is soft-deleted. |
| `EntryUndeleted` | A deleted entry is restored. |

**Member Activities:**

| Activity Type | Trigger |
|---|---|
| `MemberCreated` | A new member joins the group (real or virtual). Records name and member type. |
| `MemberReplaced` | A real member claims another member's identity. Records name and root ID. |
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

- Amounts are formatted with the currency symbol and appropriate decimal precision (e.g., "€10.50", "¥1050").
- **Future work:** Full locale-aware currency formatting via `Intl.NumberFormat` (e.g., "1 234,56 EUR" in French).

---

## 11. Encryption & Security

### 11.1 Encryption Architecture

The application uses a **two-layer encryption model**:

| Layer | Content | Encrypted? |
|---|---|---|
| **Sync metadata** | PocketBase record IDs, `groupId`, `actorId`. | No (strictly necessary for sync relay and access control). |
| **Everything else** | Everything else. | Yes (AES-256-GCM). |

### 11.2 Cryptographic Primitives

| Purpose | Algorithm | Parameters |
|---|---|---|
| Data encryption | AES-256-GCM | 256-bit key, 12-byte random IV, built-in authentication tag. |
| Digital signatures | ECDSA P-256 with SHA-256 | Chosen for Web Crypto API compatibility across browsers. |
| Hashing | SHA-256 | Used for public key hashing, PoW, password derivation. |

### 11.3 Event Signing

Every event is **cryptographically signed** by its author:

- **Canonicalization:** The event is serialized to a deterministic JSON text (excluding the signature field) containing: event ID, timestamp, triggered-by member ID, and encoded payload.
- **Signing:** The canonical text is signed using the author's ECDSA P-256 private key with SHA-256 hashing.
- **Verification:** On receipt, the signature is verified against the author's stored public key. Events with invalid signatures are rejected during state computation.
- **Genesis exception:** `GroupCreated` events bypass signature verification (no prior state to look up public keys).

### 11.4 Key Management

- Each group has a **single symmetric key** (AES-256) shared by all members.
- The group key is distributed via **URL fragments** (see [Invitation](#12-invitation--group-joining)).
- Group keys are stored locally in IndexedDB.

### 11.5 Server Authentication

- Each group has an associated **server account** for accessing the relay.
- The account password is **deterministically derived** from the group key: `Base64URL(SHA-256(Base64(groupKey)))`.
- This means anyone with the group key can authenticate to the server for that group, without any additional credentials.

### 11.6 What the Server Can See

The server can only see:
- PocketBase record IDs and creation timestamps (automatic, used for sync cursoring).
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

- Users can export a single group from the group selection screen.
- Export format: **JSON** containing all decrypted data (entries, members, metadata, events, audit trail).
- The export is compressed before download.
- Metadata includes export timestamp and version.

### 13.2 Import

- Users can import a previously exported JSON file.
- If the group already exists locally, the import is rejected (duplicate group ID).
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
| `events` | The full append-only event log per group (encrypted), indexed by group ID. |
| `syncCursors` | Last sync cursor per group (PocketBase `created` timestamp). |
| `unpushedIds` | Set of event IDs created locally but not yet pushed to server. |
| `usageStats` | Network and storage tracking data. |

### 14.3 Synchronization

- The server acts as a **relay** for encrypted events.
- **Initial sync**: Fetches all historical events (paginated, 200 per page) and replays them in deterministic order to build local state.
- **Incremental sync**: Pushes local unpushed events and pulls remote events since last cursor.
- **Real-time subscriptions**: The app subscribes to server-sent events via WebSocket for live updates from other devices/users.
- **Offline queue**: Events created while offline are queued (tracked in `unpushedIds`) and synced when connectivity returns.

### 14.4 Event Compression

Event data can be **compressed** before encryption to reduce bandwidth and storage:

- Compression uses gzip (via the browser's CompressionStream API).
- Compression is applied conditionally when it achieves meaningful size reduction.
- A `compressed` flag on each record indicates whether decompression is needed on read.
- Multiple events can be batched into a single compressed+encrypted payload.

### 14.5 Event Ordering & Conflict Resolution

All group state is derived by replaying the **immutable event log** in a deterministic total order.

**Ordering rule:** Each event is assigned a **UUID v7** identifier at creation time. UUID v7 embeds a millisecond-precision timestamp in its most significant bits, followed by random bits. Events are sorted by timestamp then event ID, providing a deterministic total order that naturally reflects creation time. Since groups are trusted, client-generated UUIDs are authoritative. All clients use the same comparison function after decryption, guaranteeing convergence.

**State computation:** Events are replayed in sort order. Each event is validated against the current state at the point of replay. Invalid events are **silently ignored** (see [4.5](#45-member-operation-rules)). This ensures all clients converge to identical state regardless of the order in which events were received over the network.

**Conflict categories:**

The following concurrent event pairs are **order-dependent** (their outcome depends on which is processed first). Deterministic ordering resolves them automatically:

| Category | Conflicting pair | Resolution |
|---|---|---|
| **Member lifecycle** | `retire` vs `replace` (same member) | First in sort order succeeds; the other is silently ignored (state is now terminal or incompatible). |
| **Member lifecycle** | `replace` vs `replace` (same member, different claimers) | First in sort order succeeds; the other is silently ignored (member already replaced). |
| **Member lifecycle** | `retire`/`unretire` interleaving (same member) | Processed in sort order; each is validated against the member's state at that point. |
| **Entry versioning** | Concurrent modifications (same `rootId`) | Last-writer-wins by timestamp. The current version is the non-deleted version with the latest timestamp (see [5.7](#57-entry-versioning)). |
| **Entry versioning** | Modify + delete (same `rootId`) | Last-writer-wins. The event with the later timestamp determines whether the entry is modified or deleted. |
| **Last-writer-wins** | Concurrent renames (same member) | Latest timestamp determines the current name. |
| **Last-writer-wins** | Concurrent metadata updates (same member or group) | Latest timestamp determines the current value. |

**Non-conflicting operations** (always commutative, order-independent):

- Creating new entries (different `rootId`s).
- Creating new members (different member IDs).
- Any events targeting different entities.

### 14.6 Incremental Sync Optimization

When new events arrive via sync, a **full replay** from scratch is not always necessary:

- **In-order events** (timestamp ≥ max existing timestamp): Always safe to apply directly on top of current state. No replay needed.
- **Late-arriving events** (timestamp < max existing timestamp): Safe to apply directly **only if** they target entities with no later-timestamped events in the conflict categories above (member lifecycle or same-entry versioning). Otherwise, a replay from scratch is required.

In practice, late arrivals involving lifecycle conflicts are extremely rare (they require two users to retire/replace the same member within a short offline window). The vast majority of syncs hit the fast path.

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

---

## 16. Progressive Web App (PWA)

### 16.1 Installation

- The app can be **installed** on any device as a standalone application.
- **Android / Desktop Chrome**: The native browser install prompt is intercepted and presented as a custom UI.
- **iOS**: Manual installation instructions are shown (with step-by-step guide) after a delay.
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
| `es` | Spanish | Planned (temporarily deferred to prioritize feature development) |

### 17.2 Language Detection & Persistence

- On first visit, the language is **auto-detected** from the browser's locale (`navigator.language`).
- The selected language is **persisted** in IndexedDB (under the `identity` store).
- A **language switcher** is available on every screen.

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
| `/setup` | Identity creation | No (redirects away if identity exists) |
| `/` | Group selection (home) | Yes |
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
| `/groups/:groupId/settings` | Edit group metadata | Yes |
| `/about` | About & usage stats | No |
| `*` (catch-all) | Redirects to `/` | - |

### 19.2 Route Guards

- **Identity required**: Routes that need a user identity redirect to `/setup` if no identity exists.
- **Setup guard**: The setup screen redirects to `/` if an identity already exists.
- **Join exception**: The join route is accessible without an identity; one is auto-generated before proceeding.

### 19.3 Screen Descriptions

| Screen | Purpose |
|---|---|
| **SetupScreen** | First-time onboarding. Generates cryptographic identity. Shows privacy explanation. |
| **GroupSelectionScreen** | Home screen. Lists all groups with name, date, member count, and color-coded balance badge. Provides export/import and group deletion. Archived groups shown in collapsible section. |
| **CreateGroupScreen** | Group creation form with name, creator name, currency, and optional virtual members. Includes PoW solver with progress feedback. |
| **JoinGroupScreen** | Invite acceptance. Shows group info, virtual/real member lists, and new member form. |
| **GroupViewScreen** | Main group interaction with 4 tabs (Balance, Entries, Members, Activities). Header shows group name, subtitle, and user's balance summary. Floating Action Button for adding entries. |
| **NewEntryScreen** | Entry creation/editing form. Supports expense, transfer, and income entry types with type switcher. |
| **AddMemberScreen** | Form to add a virtual (placeholder) member to the group. |
| **EditMemberMetadataScreen** | Form to edit a member's display name, contact info, and payment methods. |
| **EditGroupMetadataScreen** | Form to edit group name, subtitle, description, links, and archive state. |
| **AboutScreen** | App information, motivation, privacy info, usage statistics, links to GitHub, Sponsors, and Discussions. |

### 19.4 Tab System (GroupViewScreen)

| Tab | Features |
|---|---|
| **Balance** | Per-member balance cards (color-coded). Settlement plan with "Record Transfer" buttons and payment method display. Settlement preference editor. |
| **Entries** | Entry list with cards (expenses, transfers, income). Filters (person, category, currency, date). Toggle deleted entries. Click to view details/edit/delete. |
| **Members** | Member list with metadata indicators. Invite button with QR code. Add virtual member. Group info section. Member detail with name editing, contact and payment info. Group metadata editing. Notification toggle. |
| **Activities** | Activity feed (newest first, grouped by date). Activity type, actor, and involved member filters. |

---

## 20. Accessibility & UX Details

### 20.1 Accessibility

- The offline banner uses `role="alert"` and `aria-live="polite"` for screen reader compatibility.
- Form inputs include proper labels and error states.
- Buttons use semantic HTML.
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
- Push notifications enhancements (to be refined based on usage feedback).
- Analytics and spending charts.
- Import from other bill-splitting apps (Splitwise, Tricount, etc.).
- PDF / CSV export.
- Trust-minimized groups.
- Spanish language support (temporarily deferred).
- Full locale-aware currency formatting via `Intl.NumberFormat`.

## Appendix C: Client-Server Architecture

This appendix documents the boundary between the client (PWA) and the server (relay), to support independent reimplementation of either side.

### C.1 Server Overview

The server is a **PocketBase** instance (Go-based backend-as-a-service) with an embedded SQLite database. It acts as a zero-knowledge relay: it stores encrypted blobs, enforces access control, and provides real-time event streaming. It has **no business logic** about entries, members, balances, or any application-level concept.

### C.2 Server Collections (Database Schema)

**`users`** — One record per group, used for authentication.

| Field | Type | Description |
|---|---|---|
| `id` | string (auto) | PocketBase record ID. |
| `username` | string (unique) | Format: `group_{groupId}`. |
| `password` | string (hashed) | Derived from group key (see [11.5](#115-server-authentication)). |
| `groupId` | string (unique) | Links user account to a specific group. |

**`groups`** — One record per group.

| Field | Type | Description |
|---|---|---|
| `id` | string (auto) | PocketBase record ID, used as the group identifier. |
| `createdBy` | string | Public key hash of the group creator (unencrypted). |
| `powChallenge` | string (unique) | The solved PoW challenge hash (prevents reuse). |
| `created` | datetime (auto) | PocketBase auto-generated creation timestamp. |

**`events`** — Append-only log of encrypted events.

| Field | Type | Description |
|---|---|---|
| `id` | string (auto) | PocketBase record ID. |
| `groupId` | string | Links the event to a group. |
| `actorId` | string | Public key hash of the user who pushed the event. |
| `eventData` | string (max 1 MB) | Base64-encoded, AES-256-GCM encrypted event payload (may contain multiple batched events). |
| `compressed` | bool | Whether the event data was gzip-compressed before encryption. |
| `created` | datetime (auto) | PocketBase auto-generated creation timestamp. Used only as a sync cursor by clients. |

The encrypted `eventData` payload contains all application-level data, including the **UUID v7 event identifier** used for deterministic ordering (see [14.5](#145-event-ordering--conflict-resolution)). The server never sees these values.

### C.3 Server API Endpoints

**Authentication:**

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/collections/users/records` | Create a group user account. |
| `POST` | `/api/collections/users/auth-with-password` | Authenticate and receive a JWT token. |
| `POST` | `/api/collections/users/auth-refresh` | Refresh an authentication token. |

**Proof-of-Work:**

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/pow/challenge` | Get a PoW challenge. Returns `{challenge, timestamp, difficulty, signature}`. |

**Groups:**

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/collections/groups/records` | Create a group (requires solved PoW in the request body). |
| `GET` | `/api/collections/groups/records/{id}` | Retrieve a group by ID. |

**Event Sync:**

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/collections/events/records` | Push an encrypted event (possibly batched and compressed). |
| `GET` | `/api/collections/events/records?filter=groupId="{id}"&sort=+created` | Fetch all events for a group (initial sync), paginated. |
| `GET` | `/api/collections/events/records?filter=groupId="{id}" && created>"{ts}"` | Fetch events since last sync (incremental sync). The `created` field is PocketBase's auto-generated timestamp, used only as a sync cursor. |

**Real-time (WebSocket):**

| Method | Endpoint | Description |
|---|---|---|
| `WS` | `/api/realtime` | Subscribe to `events` collection for live updates. Client filters by `groupId`. |

### C.4 Server Access Control Rules

| Collection | List/View | Create | Update | Delete |
|---|---|---|---|---|
| `users` | Own record only | Public (with hook validation) | Not allowed | Admin only |
| `groups` | Authenticated + matching `groupId` | Public (with PoW hook validation) | Not allowed (immutable) | Admin only |
| `events` | Authenticated + matching `groupId` | Authenticated + matching `groupId` | Not allowed (append-only) | Admin only |

### C.5 Server Hooks

The server has two validation hooks implemented in JavaScript:

1. **PoW validation** (on group creation): Verifies the PoW challenge signature (HMAC-SHA256 with server secret), checks the solution has the required leading zero bits, and ensures the challenge hasn't expired (10-minute window).
2. **User creation validation**: Verifies that the referenced `groupId` exists in the groups collection.

### C.6 Client Responsibilities

The client handles **all** application logic:

| Responsibility | Details |
|---|---|
| **Cryptography** | Key generation (ECDSA P-256), AES-256-GCM encryption/decryption, event signing and verification, password derivation, PoW solving. |
| **Event sourcing** | Encoding changes as immutable events, replaying events in deterministic order (by timestamp and event ID after decryption), computing current state from the event log. |
| **Business logic** | Entry management, member state computation, balance calculation, settlement planning, activity feed generation. |
| **Local storage** | IndexedDB for identity, group keys, event log, computed state cache, pending events, sync cursors, and usage statistics. |
| **Sync management** | Pushing local events (with optional compression), pulling remote events (using PocketBase `created` as sync cursor), offline queue, real-time subscription handling. |
| **Push notifications** | Sending push notifications to affected members after sync, managing subscriptions, localizing notification messages. |
| **UI & routing** | All screens, navigation, forms, modals, i18n, PWA installation, service worker. |

### C.7 Authentication Flow

1. **Group creation:** Client solves PoW challenge, sends solution to server. Server validates and creates group record.
2. **User account creation:** Client derives password from group key as `Base64URL(SHA-256(Base64(groupKey)))` and creates a user record with username `group_{groupId}`.
3. **Session authentication:** Client authenticates with username/password to receive a JWT token. All subsequent API calls include the token as `Authorization: Bearer {token}`.
4. **Token refresh:** Client refreshes the JWT token before expiry to maintain the session.

Note: "User accounts" here are per-group server accounts for API access. They are unrelated to user identity (the cryptographic keypair). Anyone with the group key can derive the same password and authenticate.

### C.8 Event Payload Types

The following event types can appear in encrypted event payloads:

| Event Type | Description |
|---|---|
| `GroupCreated` | Initializes a group with name and default currency. |
| `GroupMetadataUpdated` | Partial update to group metadata (only changed fields included). |
| `MemberCreated` | Adds a new member (real or virtual). |
| `MemberRenamed` | Changes a member's display name. |
| `MemberRetired` | Marks a member as inactive. |
| `MemberUnretired` | Reactivates a retired member. |
| `MemberReplaced` | Links a new identity to an existing member chain. |
| `MemberMetadataUpdated` | Updates a member's contact/payment information. |
| `SettlementPreferencesUpdated` | Updates a member's preferred payment recipients. |
| `EntryAdded` | Creates a new expense, transfer, or income entry. |
| `EntryModified` | Creates a new version of an existing entry. |
| `EntryDeleted` | Soft-deletes an entry. |
| `EntryUndeleted` | Restores a deleted entry. |
