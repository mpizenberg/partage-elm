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
5. [Entries: Expenses and Transfers](#5-entries-expenses-and-transfers)
6. [Balance Calculation](#6-balance-calculation)
7. [Settlement Planning](#7-settlement-planning)
8. [Activity Feed & Audit Trail](#8-activity-feed--audit-trail)
9. [Filtering & Sorting](#9-filtering--sorting)
10. [Multi-Currency Support](#10-multi-currency-support)
11. [Encryption & Security](#11-encryption--security)
12. [Invitation & Group Joining](#12-invitation--group-joining)
13. [Import / Export](#13-import--export)
14. [Offline & Synchronization](#14-offline--synchronization)
15. [Progressive Web App (PWA)](#15-progressive-web-app-pwa)
16. [Internationalization (i18n)](#16-internationalization-i18n)
17. [Usage Statistics](#17-usage-statistics)
18. [Navigation & Screens](#18-navigation--screens)
19. [Accessibility & UX Details](#19-accessibility--ux-details)

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
- The application generates a **cryptographic keypair** (ECDSA, P-256 curve) locally in the browser.
- The keypair is used for **digital signatures** (to authenticate operations).
- The **public key hash** (SHA-256 of the public key) serves as the user's anonymous, unique identifier.
- No username, email, or password is required.

### 2.2 Identity Storage

- The keypair is stored in the browser's local database (IndexedDB).
- There is exactly **one identity per browser profile**.
- The identity persists across sessions until the browser data is cleared.

### 2.3 Identity Recovery

- **There is no password recovery mechanism.** If the browser data is lost, the identity is lost.
- The user can rejoin groups via a new invite link, but they will appear as a new member.
- The user can link their new identity to any previous member entry (see [Member Aliases](#44-member-aliases)).

### 2.4 Identity Guarantees

- The server never learns the user's real name or any personal information.
- The user's identifier (public key hash) is pseudonymous and cannot be correlated across groups by the server.

---

## 3. Group Management

### 3.1 Group Creation

- Any user can create a new group.
- **Required fields:** group name, creator's display name, default currency.
- **Optional fields:** subtitle, description, links (label + URL pairs).
- **Anti-spam protection:** Creating a group requires solving a **Proof-of-Work (PoW) challenge**.
  - Difficulty: 18 leading zero bits in the SHA-256 hash (~2-4 seconds of computation).
  - Challenge validity window: 10 minutes.
  - Each challenge can only be used once (enforced server-side).
  - The PoW is solved in a background thread to avoid blocking the UI, with progress feedback.
- The creator is automatically added as the first member of the group.
- Virtual members (name-only placeholders) can be added at creation time.

### 3.2 Group Metadata

Each group has the following metadata, all **encrypted**:

| Field | Required | Description |
|---|---|---|
| Name | Yes | The display name of the group. |
| Subtitle | No | A short tagline shown in the group header. |
| Description | No | A longer description shown on the Members tab. |
| Links | No | A list of `{label, url}` pairs rendered as clickable chips (e.g., shared spreadsheet, payment link). |
| Default currency | Yes | The ISO 4217 currency code used for balance normalization. Set at group creation and cannot be changed afterward. |

- Group metadata (except default currency) can be edited after creation.
- Metadata changes are tracked in the activity feed.

### 3.3 Group Deletion

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
| `member_created` | A new member is added (real or virtual). Records name, public key (if real), virtual flag, and who added them. |
| `member_renamed` | A member's display name is changed. Records old and new names. |
| `member_retired` | A member is marked as departed/inactive. They no longer appear in new entry forms but their historical data is preserved. |
| `member_unretired` | A retired member is reactivated. |
| `member_replaced` | A member's identity is claimed by a new real member (see [Member Aliases](#44-member-aliases)). Any member type (virtual or real) can be claimed. This is one of the recovery mechanisms for lost identities, and is safe given the group's trust assumptions. |
| `member_metadata_updated` | A member's contact or payment information is updated. |

### 4.3 Computed Member State

From the event log, each member has a computed state:

| Property | Description |
|---|---|
| `name` | Current display name (latest rename, or creation name). |
| `rootId` | The ID of the first member in the replacement chain. Equals the member's own ID if they have not replaced anyone. |
| `isActive` | True if not retired and not replaced. |
| `isRetired` | True if the latest lifecycle event is `member_retired`. |
| `isReplaced` | True if the member has been claimed by another member. |
| `replacedById` | The ID of the member who claimed this identity. |

### 4.4 Member Aliases (Identity Claiming)

When a real user joins a group, they can **claim the identity of any existing group member** (virtual or real):

- The claimed member's ID is linked to the new member's ID via a `member_replaced` event.
- The new member inherits the **rootId** of the claimed member. This links the entire replacement chain to a single stable identifier — the rootId — which is always the ID of the **first member** in the chain.
- This is analogous to how entry version chains work: each entry version has its own ID, but the chain is identified by the `rootId` of the original entry.
- **Example:** If member A (rootId=A) is replaced by B, then B.rootId=A. If B is later replaced by C, then C.rootId=A. All three share the same rootId.
- The rootId is used throughout the application as the **stable identifier** for a member chain: balance calculations, activity feeds, entry displays, and settlement plans all aggregate by rootId.
- **Name resolution:** Although the rootId identifies the chain, the **display name** is always resolved to the newest active (non-replaced) member's current name in the chain. For example, if virtual member "Alice" (rootId=A) was claimed by real member "Alice R." (rootId=A), the display name everywhere is "Alice R." — even for historical entries originally involving the virtual member.
- In the join UI, claiming a **virtual member** is the primary path (prominently displayed). Claiming a **real member** is available in a collapsed section, intended for device migration or identity recovery scenarios.

### 4.5 Member Operation Rules

Member operations follow strict validation rules. Invalid events are **silently ignored** during state computation, which is intentional for deterministic convergence (different replicas may receive events in different orders, but replay them in the same deterministic sort order).

| Operation | Valid When | Invalid When |
|---|---|---|
| **Rename** | Member exists (any state). | Member does not exist. |
| **Retire** | Member is active (not retired, not replaced). | Member does not exist, is already retired, or has been replaced. |
| **Unretire** | Member is retired and not replaced. | Member does not exist, is not retired, or has been replaced. |
| **Replace** | Member is active (not retired, not replaced) and the replacer is a different member. | Member does not exist, is retired, has already been replaced, or is the same as the replacer. |

Key design principles:
- **State transitions**: Active members can be retired or replaced. Retired members can be unretired. Replaced members are terminal (cannot be retired, unretired, or replaced again).
- **Root ID resolution**: Replacement chains share a stable rootId (the first member's ID). The display name is always resolved to the newest active member's name in the chain.

### 4.6 Member Metadata (Encrypted)

Each member can have optional contact and payment information:

| Category | Fields |
|---|---|
| **Contact** | Phone number |
| **Payment methods** | IBAN, Wero, Lydia, Revolut, PayPal, Venmo, Bitcoin (BTC address), Cardano (ADA address) |
| **Notes** | Free-text information field |

- All metadata is **encrypted** with the group key.
- Payment details are displayed as copiable text.
- Some payment methods generate clickable payment links (Lydia, Revolut, PayPal, Venmo, Bitcoin).
- Phone numbers are displayed as clickable `tel:` links.

### 4.7 Member Display Order

- **Active members**: The current user appears first (with a "(you)" badge), then others sorted alphabetically (case-insensitive).
- **Departed members**: Listed alphabetically in a collapsible section.

---

## 5. Entries: Expenses and Transfers

### 5.1 Entry Types

| Type | Description |
|---|---|
| **Expense** | A shared cost paid by one or more payers on behalf of one or more beneficiaries. |
| **Transfer** | A direct payment from one member to another (typically a reimbursement/settlement). |

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
| Location | No | Where the expense occurred. |
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

### 5.4 Expense Splitting Methods

#### Shares-Based Split

- Each beneficiary has a number of shares (default: 1).
- The total amount is divided proportionally by each beneficiary's share count relative to the total shares.
- **Rounding guarantee:** Integer arithmetic (in cents) is used. Any remainder cents are distributed deterministically to beneficiaries sorted by member ID. A member with N shares can receive up to N remainder cents. This ensures the split always sums exactly to the total.

#### Exact Amount Split

- Each beneficiary has a specific amount they owe.
- The sum of all exact amounts must equal the total expense amount exactly.

### 5.5 Multiple Payers

- By default, a single payer pays the full amount.
- Multiple payers mode: each payer specifies the portion they paid.
- The sum of all payer amounts must equal the total expense amount exactly.
- When the entry currency differs from the default currency, payer amounts are proportionally converted using integer arithmetic (cents) with deterministic remainder distribution.

### 5.6 Entry Modification

- Entries can be **modified**, by creating a new entry linked to the original.
- Each entry version has its own unique ID (UUID). The version history is linked via `previousVersionId` (UUID of the prior version) and `rootId` (UUID of the original entry in the chain).
- The modification records: who modified it, when, and the full new data.
- **Current version rule:** For a given `rootId`, the current version is the **non-deleted version with the latest client timestamp** (with client-generated event UUID as tiebreaker). This makes concurrent modifications resolve deterministically via last-writer-wins. The `previousVersionId` is used for audit trail display and diff computation, not for determining the current version.

### 5.7 Entry Deletion & Restoration

- Entries can be **soft-deleted** (creating a new version with deleted status).
- Deleted entries are hidden by default but can be shown via a toggle.
- Deleted entries can be **restored** (undeleted).
- Deleted entries are excluded from balance calculations.

### 5.8 Form Validation Rules

- Description: required, non-empty after trimming.
- Amount: required, numeric, strictly positive.
- Default currency amount: required when currency differs from group default, strictly positive.
- Payers: at least one required; sum must match total exactly.
- Beneficiaries: at least one required; for exact split, sum must match total exactly.
- Transfer from/to: must be different members.

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

### 6.3 Balance Display

- Each member's balance is shown in a **BalanceCard** component.
- Color coding:
  - **Green**: member is owed money (positive balance).
  - **Red**: member owes money (negative balance).
  - **Neutral**: member is settled (|balance| < 0.01).
- The current user's card shows a "(you)" badge.
- A "Pay Them" button appears on cards of members who are owed money (creditors), for quick settlement.

---

## 7. Settlement Planning

### 7.1 Settlement Algorithm

The application generates an optimized **settlement plan** that minimizes the total number of transactions needed to settle all debts.

**Two-pass algorithm:**

1. **Pass 1 - Preference-Aware:** Debtors with settlement preferences are processed first. They are sorted by amount (smallest first) and matched to their preferred creditors in priority order.
2. **Pass 2 - Greedy Optimization:** Remaining debtors are sorted by amount (largest first) and matched to available creditors greedily.

**Guarantees:**
- All debts are settled after the plan is executed.
- Amounts are rounded to 2 decimal places.
- Micro-debts below 0.01 are treated as zero.

### 7.2 Settlement Preferences

Each member can configure **preferred recipients** for receiving payments, ordered by priority.

- `prefer`: Try to settle with these recipients first (in order of preference).

### 7.3 Settlement Recording

- Each transaction in the settlement plan has a "Mark as Paid" button.
- Clicking it creates a **Transfer entry** recording the payment.
- Transactions involving the current user are **highlighted** visually.
- When all debts are settled, a "All settled up" message with a checkmark is displayed.

---

## 8. Activity Feed & Audit Trail

### 8.1 Activity Types

The activity feed tracks all significant actions in a group:

| Activity Type | Trigger |
|---|---|
| `entry_added` | A new expense or transfer is created. |
| `entry_modified` | An existing entry is edited. Records what changed (field-by-field diff). |
| `entry_deleted` | An entry is soft-deleted. |
| `entry_undeleted` | A deleted entry is restored. |
| `member_joined` | A new member joins the group (real or virtual). |
| `member_linked` | A real member claims another member's identity. |
| `member_renamed` | A member changes their display name. Shows old and new names. |
| `member_retired` | A member is marked as departed. |
| `group_metadata_updated` | Group metadata (name, subtitle, etc.) is changed. |

### 8.2 Activity Details

Each activity records:
- **Who** performed the action (actor ID and name).
- **When** (timestamp).
- **What** changed (full entry/member data, and for modifications, a field-by-field change record with from/to values).
- **Participant names** are resolved and stored (payer names, beneficiary names, from/to names).
- **Current name annotation**: If a member's name has changed since the activity, the current name is also shown.

### 8.3 Activity Sorting

- Activities are sorted **newest first** by timestamp.
- Incremental updates use **binary search insertion** for efficiency.

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
| **Category** | OR | Entry must match ANY of the selected categories. Transfers have a special "transfer" category. |
| **Currency** | OR | Entry must use ANY of the selected currencies. |
| **Date range** | OR | Entry date must fall within ANY of the selected date ranges. |

- **Cross-type combination**: All active filter types are combined with **AND** logic (all must pass).
- **Within same type**: Person filters use AND; all others use OR.
- **Empty filter**: Shows all entries.

### 9.2 Date Presets

| Preset | Range |
|---|---|
| Today | Start of today to end of today |
| Yesterday | Start of yesterday to end of yesterday |
| Last 7 days | 7 days ago to end of today |
| Last 30 days | 30 days ago to end of today |
| This month | 1st of current month to last moment of current month |
| Last month | 1st of previous month to last moment of previous month |
| Custom | User-defined start and end dates |

### 9.3 Activity Filters

Activities can be filtered by:
- Activity type (entry events, member events).
- Actor (who performed the action).
- Involved members.

### 9.4 Deleted Entry Visibility

- Deleted entries are **hidden by default**.
- A toggle allows showing/hiding deleted entries in the list.

---

## 10. Multi-Currency Support

### 10.1 Supported Currencies

The application supports 20+ currencies including: USD, EUR, GBP, JPY, AUD, CAD, CHF, CNY, SEK, NZD, MXN, SGD, HKD, NOK, KRW, TRY, INR, RUB, BRL, ZAR.

### 10.2 Currency Behavior

- Each group has a **default currency** set at creation time. It cannot be changed afterward.
- Each entry can use **any currency**.
- When an entry uses a non-default currency, the user must provide the **equivalent amount in the default currency** (manual exchange rate entry).
- Both the original amount/currency and the default currency amount are stored. The exchange rate is derived from these two amounts for display purposes but is not stored separately.

### 10.3 Currency in Calculations

- **Balance calculations** use the `defaultCurrencyAmount` for normalization.
- **Settlement plans** use the group's default currency.
- **Entry display** shows both original and converted amounts when they differ (e.g., "5.00 EUR ($6.00)").

### 10.4 Currency Formatting

- Amounts are formatted using **locale-aware currency formatting** (e.g., "$1,234.56" in English, "1 234,56 EUR" in French).
- The default currency is pre-selected based on the user's language (EUR for French, USD otherwise).

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
| Digital signatures | ECDSA | P-256 curve, SHA-256 hash. |
| Hashing | SHA-256 | Used for public key hashing, PoW, password derivation. |

### 11.3 Key Management

- Each group has a **single symmetric key** (AES-256) shared by all members.
- The group key is distributed via **URL fragments** (see [Invitation](#12-invitation--group-joining)).
- Group keys are stored locally in IndexedDB.

### 11.4 Server Authentication

- Each group has an associated **server account** for accessing the relay.
- The account password is **deterministically derived** from the group key: `Base64URL(SHA-256(Base64(groupKey)))`.
- This means anyone with the group key can authenticate to the server for that group, without any additional credentials.

### 11.5 What the Server Can See

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
  - A **QR code** containing the full invite link (dynamically generated).
  - A **"Copy link"** button.
  - Integration with the **Web Share API** (on supported devices).
- A security notice reminds users to share links only via trusted channels.

### 12.3 Joining Flow

When a user opens an invite link:

1. The app extracts the group ID from the URL path and the group key from the fragment.
2. The app authenticates to the server using the derived password.
3. All historical encrypted data is fetched and decrypted locally.
4. The user sees the group name and member list.
5. The user can:
   - **Claim a virtual member** (primary path, if unclaimed virtual members exist).
   - **Re-join as an existing real member** (collapsed section, for device migration).
   - **Join as a new member** with a new display name (duplicate names are prevented).
6. A member event is recorded and synced.

---

## 13. Import / Export

### 13.1 Export

- Users can select one or more groups from the group selection screen and export them.
- Export format: **JSON** containing all decrypted data (entries, members, metadata, events, audit trail).
- Metadata includes export timestamp and version.

### 13.2 Import

- Users can import a previously exported JSON file.
- The application analyzes the relationship between local and imported data for each group:

| Relationship | Meaning |
|---|---|
| `new` | The group doesn't exist locally. It will be created. |
| `local_subset` | The local copy already has more recent data. Nothing to merge. |
| `import_subset` | The imported data is older than local. Nothing to merge. |
| `diverged` | Both local and imported data have unique changes. They will be merged by taking the union of all events (deduplicated by event ID) and replaying in deterministic order. |

### 13.3 Import Preview

- Before importing, a **preview modal** shows:
  - Each group with its relationship status.
  - Entry and member counts.
  - Currency information.
- The user confirms each group before the import is applied.

---

## 14. Offline & Synchronization

### 14.1 Local-First Architecture

- All operations (add, modify, delete entries; manage members) are **applied immediately to local state**.
- The application is fully functional without an internet connection.
- Data is persisted in **IndexedDB** across sessions.

### 14.2 Local Storage

The following data is stored locally per group:

| Store | Content |
|---|---|
| Identity | User's cryptographic keypair. |
| Groups | Group metadata and settings. |
| Group keys | Symmetric encryption keys per group. |
| Events | The full append-only event log per group (encrypted). |
| Computed state cache | Materialized group state for fast loading (rebuilt from events on demand). |
| Pending events | Events created while offline, queued for sync. |
| Usage statistics | Network and storage tracking data. |

### 14.3 Synchronization

- The server acts as a **relay** for encrypted events.
- **Initial sync**: Fetches all historical events and replays them in deterministic order to build local state.
- **Incremental sync**: Pushes local events and pulls remote events.
- **Real-time subscriptions**: The app subscribes to server-sent events for live updates from other devices/users.
- **Offline queue**: Events created while offline are queued and synced when connectivity returns.

### 14.4 Event Ordering & Conflict Resolution

All group state is derived by replaying the **immutable event log** in a deterministic total order.

**Ordering rule:** Events are sorted by `(clientTimestamp, clientEventId)`. Both values are part of the encrypted event payload, generated by the client at event creation time. The client timestamp (millisecond-precision Unix timestamp) provides the primary ordering; the client-generated event UUID (lexicographic comparison) breaks ties. Since groups are trusted, client-provided timestamps are authoritative. All clients use the same comparison function after decryption, guaranteeing convergence.

**State computation:** Events are replayed in sort order. Each event is validated against the current state at the point of replay. Invalid events are **silently ignored** (see [4.5](#45-member-operation-rules)). This ensures all clients converge to identical state regardless of the order in which events were received over the network.

**Conflict categories:**

The following concurrent event pairs are **order-dependent** (their outcome depends on which is processed first). Deterministic ordering resolves them automatically:

| Category | Conflicting pair | Resolution |
|---|---|---|
| **Member lifecycle** | `retire` vs `replace` (same member) | First in sort order succeeds; the other is silently ignored (state is now terminal or incompatible). |
| **Member lifecycle** | `replace` vs `replace` (same member, different claimers) | First in sort order succeeds; the other is silently ignored (member already replaced). |
| **Member lifecycle** | `retire`/`unretire` interleaving (same member) | Processed in sort order; each is validated against the member's state at that point. |
| **Entry versioning** | Concurrent modifications (same `rootId`) | Last-writer-wins by timestamp. The current version is the non-deleted version with the latest timestamp (see [5.6](#56-entry-modification)). |
| **Entry versioning** | Modify + delete (same `rootId`) | Last-writer-wins. The event with the later timestamp determines whether the entry is modified or deleted. |
| **Last-writer-wins** | Concurrent renames (same member) | Latest timestamp determines the current name. |
| **Last-writer-wins** | Concurrent metadata updates (same member or group) | Latest timestamp determines the current value. |

**Non-conflicting operations** (always commutative, order-independent):

- Creating new entries (different `rootId`s).
- Creating new members (different member IDs).
- Any events targeting different entities.

### 14.5 Incremental Sync Optimization

When new events arrive via sync, a **full replay** from scratch is not always necessary:

- **In-order events** (timestamp ≥ max existing timestamp): Always safe to apply directly on top of current state. No replay needed.
- **Late-arriving events** (timestamp < max existing timestamp): Safe to apply directly **only if** they target entities with no later-timestamped events in the conflict categories above (member lifecycle or same-entry versioning). Otherwise, a replay from scratch is required.

In practice, late arrivals involving lifecycle conflicts are extremely rare (they require two users to retire/replace the same member within a short offline window). The vast majority of syncs hit the fast path.

**Computed state caching:** The materialized group state is cached locally. On app load, if the event log has not changed, the cached state is used directly. Otherwise, the state is recomputed from the full event log.

### 14.6 Connectivity Indicators

- An **offline banner** (with Wi-Fi icon) appears when the app detects loss of connectivity.
- The banner is accessible (`role="alert"`, `aria-live="polite"`).
- The app automatically re-subscribes and syncs the offline queue when connectivity is restored.

---

## 15. Progressive Web App (PWA)

### 15.1 Installation

- The app can be **installed** on any device as a standalone application.
- **Android / Desktop Chrome**: The native browser install prompt is intercepted and presented as a custom UI.
- **iOS**: Manual installation instructions are shown (with step-by-step guide) after a 30-second delay.
- The install prompt is **dismissible** and re-appears after 7 days.
- The prompt is not shown if the app is already running in standalone mode.
- After installation, the app redirects to the installed standalone version.

### 15.2 Standalone Mode

- When installed, the app runs in **standalone** display mode (no browser chrome).
- Portrait orientation is preferred.

### 15.3 Service Worker

- The service worker provides **offline caching** with the following strategies:
  - **Cache-first** for static assets (JS, CSS, HTML, SVG, WASM, JSON) and fonts.
  - **Network-first** for API calls.
- **Auto-update**: The service worker updates automatically. The app handles `SKIP_WAITING` for seamless transitions.
- Maximum per-resource precache size: 5 MB.
- Navigation fallback to `index.html` for SPA routing.

### 15.4 App Metadata

- App name: "Partage - Bill Splitting"
- Categories: finance, utilities.
- Theme color: `#2563eb` (blue).
- Icons: SVG with maskable variants for adaptive displays.
- Apple-specific meta tags for iOS web app support.

---

## 16. Internationalization (i18n)

### 16.1 Supported Languages

| Code | Language |
|---|---|
| `en` | English |
| `fr` | French |
| `es` | Spanish |

### 16.2 Language Detection & Persistence

- On first visit, the language is **auto-detected** from the browser's locale (`navigator.language`).
- The selected language is **persisted** in localStorage.
- A **language switcher** is available on every screen.

### 16.3 Translation Coverage

- All UI text, labels, buttons, error messages, and toast notifications are translated.
- ~200 translation keys per language.
- Interpolation is supported: `{paramName}` placeholders in translation strings.

### 16.4 Locale-Aware Formatting

| Format | Description |
|---|---|
| Currency | Locale-aware formatting (e.g., "$1,234.56" vs "1 234,56 EUR"). |
| Date | Short and long date formats with weekday, localized month names. |
| Relative time | "5 minutes ago", "yesterday", etc., in the active language. |
| Numbers | Locale-aware decimal separators and grouping. |
| Date grouping | Labels like "Today", "Yesterday", month names in the active language. |

---

## 17. Usage Statistics

### 17.1 Tracked Metrics (Local Only)

The application tracks usage statistics **locally** (never sent to the server):

| Metric | Description |
|---|---|
| Total bytes transferred | Cumulative network bandwidth used. |
| Storage size | Estimated storage consumption (updated at most once per day). |
| Tracking start date | When tracking began. |

### 17.2 Cost Estimation

The app estimates the user's share of infrastructure costs:

| Component | Rate |
|---|---|
| Base cost | $0.10 / month / user |
| Storage | ~$0.10 / GB / month |
| Bandwidth | ~$0.10 / GB |
| Compute | 5x the storage cost |

- A **cost breakdown** is displayed on the About screen.
- Shows: base, storage, compute, network costs, total, and average per month.

### 17.3 Reset

- Users can **reset** their usage statistics (e.g., after making a donation).

---

## 18. Navigation & Screens

### 18.1 Routing

| Route | Screen | Auth Required |
|---|---|---|
| `/setup` | Identity creation | No (redirects away if identity exists) |
| `/` | Group selection (home) | Yes |
| `/groups/new` | Create new group | Yes |
| `/join/:groupId#key` | Join group via invite link | No |
| `/groups/:groupId` | Group view (default: Balance tab) | Yes |
| `/groups/:groupId/entries` | Group view - Entries tab | Yes |
| `/groups/:groupId/members` | Group view - Members tab | Yes |
| `/groups/:groupId/activities` | Group view - Activities tab | Yes |
| `/about` | About & usage stats | No |
| `*` (catch-all) | Redirects to `/` | - |

### 18.2 Route Guards

- **Identity required**: Routes that need a user identity redirect to `/setup` if no identity exists.
- **Setup guard**: The setup screen redirects to `/` if an identity already exists.

### 18.3 Screen Descriptions

| Screen | Purpose |
|---|---|
| **SetupScreen** | First-time onboarding. Generates cryptographic identity. Shows privacy explanation. |
| **GroupSelectionScreen** | Home screen. Lists all groups with name, date, member count, and color-coded balance badge. Provides export/import and group deletion. |
| **CreateGroupScreen** | Group creation wizard with name, currency, optional metadata, virtual member management, and PoW solver with progress feedback. |
| **JoinGroupScreen** | Invite acceptance. Shows group info, virtual/real member lists, and new member form. |
| **GroupViewScreen** | Main group interaction with 4 tabs (Balance, Entries, Members, Activities). Header shows group name, subtitle, and user's balance summary. Floating Action Button for adding entries. |
| **AboutScreen** | App information, motivation, privacy info, usage statistics, links to GitHub, Sponsors, and Discussions. |

### 18.4 Tab System (GroupViewScreen)

| Tab | Features |
|---|---|
| **Balance** | Per-member balance cards (color-coded). Settlement plan with "Mark as Paid" buttons. Settlement preference editor. |
| **Entries** | Entry list with cards. Filters (person, category, currency, date). Toggle deleted entries. Click to view details/edit/delete. |
| **Members** | Member list with metadata indicators. Invite button. Add virtual member. Group info section. Member detail modal (edit name, metadata, payment info). Group metadata modal. |
| **Activities** | Activity feed (newest first). Activity type and member filters. |

---

## 19. Accessibility & UX Details

### 19.1 Accessibility

- The offline banner uses `role="alert"` and `aria-live="polite"` for screen reader compatibility.
- Form inputs include proper labels and error states.
- Buttons use semantic HTML.
- Color-coded elements (balances) also use text indicators (+/-/settled).

### 19.2 Toast Notifications

- In-app toast notifications for success/error feedback (e.g., "Entry added", "Error saving").
- Toasts auto-dismiss after a configurable duration.
- Multiple toasts can stack.

### 19.3 Confirmation Dialogs

- Destructive actions (delete entry, remove group) require explicit confirmation.

### 19.4 Loading States

- Spinner displayed during: identity generation, PoW solving, group creation, data syncing.
- Buttons show "Recording..." state during settlement recording.
- Forms are disabled during submission.

### 19.5 Error Handling

- Form validation errors displayed per-field.
- Network errors surface as toast notifications.
- PoW solving errors displayed with retry option.
- Identity generation errors displayed prominently on setup screen.

### 19.6 Responsive Design

- Mobile-first design with a breakpoint at 768px.
- Full-width inputs and stacked layouts on mobile.
- Side-by-side layouts on tablet/desktop.
- Maximum container width of 768px on larger screens.
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
- Push notifications (to be redesigned from scratch).
- Analytics and spending charts.
- Import from other bill-splitting apps (Splitwise, Tricount, etc.).
- PDF / CSV export.
- Trust-minimized groups.

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
| `password` | string (hashed) | Derived from group key (see [11.4](#114-server-authentication)). |
| `groupId` | string (unique) | Links user account to a specific group. |

**`groups`** — One record per group.

| Field | Type | Description |
|---|---|---|
| `id` | string (auto) | PocketBase record ID, used as the group identifier. |
| `createdAt` | number | Unix timestamp (unencrypted). |
| `createdBy` | string | Public key hash of the group creator (unencrypted). |
| `powChallenge` | string (unique) | The solved PoW challenge hash (prevents reuse). |

**`loro_updates`** (current server schema) — Append-only log of encrypted CRDT updates.

| Field | Type | Description |
|---|---|---|
| `id` | string (auto) | PocketBase record ID. |
| `groupId` | string | Links the update to a group. |
| `timestamp` | number | Unix timestamp (unencrypted, for sync ordering). |
| `actorId` | string | Public key hash of the user who made the change. |
| `updateData` | string (max 1 MB) | Base64-encoded, AES-256-GCM encrypted Loro update bytes. |
| `version` | json (optional) | Loro version vector (for debugging). |

**`events`** (target server schema) — Append-only log of encrypted events.

| Field | Type | Description |
|---|---|---|
| `id` | string (auto) | PocketBase record ID. |
| `groupId` | string | Links the event to a group. |
| `actorId` | string | Public key hash of the user who pushed the event. |
| `eventData` | string (max 1 MB) | Base64-encoded, AES-256-GCM encrypted event payload. |
| `created` | datetime (auto) | PocketBase auto-generated creation timestamp. Used only as a sync cursor by clients. |

The encrypted `eventData` payload contains all application-level data, including the **client timestamp** and **client-generated event UUID** used for deterministic ordering (see [14.4](#144-event-ordering--conflict-resolution)). The server never sees these values.

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

**CRDT Sync** (current server API)**:**

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/collections/loro_updates/records` | Push an encrypted Loro update. |
| `GET` | `/api/collections/loro_updates/records?filter=groupId="{id}"&sort=+timestamp` | Fetch all updates for a group (initial sync). |
| `GET` | `/api/collections/loro_updates/records?filter=groupId="{id}" && timestamp>{ts}` | Fetch updates since a timestamp (incremental sync). |

**Event Sync** (target server API)**:**

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/collections/events/records` | Push an encrypted event. |
| `GET` | `/api/collections/events/records?filter=groupId="{id}"&sort=+created` | Fetch all events for a group (initial sync). |
| `GET` | `/api/collections/events/records?filter=groupId="{id}" && created>"{ts}"` | Fetch events since last sync (incremental sync). The `created` field is PocketBase's auto-generated timestamp, used only as a sync cursor. |

**Real-time (WebSocket):**

| Method | Endpoint | Description |
|---|---|---|
| `WS` | `/api/realtime` | Subscribe to `events` collection (or `loro_updates` on current server) for live updates. Client filters by `groupId`. |

### C.4 Server Access Control Rules

| Collection | List/View | Create | Update | Delete |
|---|---|---|---|---|
| `users` | Own record only | Public (with hook validation) | Not allowed | Admin only |
| `groups` | Authenticated + matching `groupId` | Public (with PoW hook validation) | Not allowed (immutable) | Admin only |
| `loro_updates` | Authenticated + matching `groupId` | Authenticated + matching `groupId` | Not allowed (append-only) | Admin only |
| `events` | Authenticated + matching `groupId` | Authenticated + matching `groupId` | Not allowed (append-only) | Admin only |

### C.5 Server Hooks

The server has two validation hooks implemented in JavaScript:

1. **PoW validation** (on group creation): Verifies the PoW challenge signature (HMAC-SHA256 with server secret), checks the solution has the required leading zero bits, and ensures the challenge hasn't expired (10-minute window).
2. **User creation validation**: Verifies that the referenced `groupId` exists in the groups collection.

### C.6 Client Responsibilities

The client handles **all** application logic:

| Responsibility | Details |
|---|---|
| **Cryptography** | Key generation (ECDSA P-256), AES-256-GCM encryption/decryption, password derivation, PoW solving. |
| **Event sourcing** | Encoding changes as immutable events, replaying events in deterministic order (by client timestamp + client event UUID after decryption), computing current state from the event log. |
| **Business logic** | Entry management, member state computation, balance calculation, settlement planning, activity feed generation. |
| **Local storage** | IndexedDB for identity, group keys, event log, computed state cache, pending events, and usage statistics. |
| **Sync management** | Pushing local events, pulling remote events (using PocketBase `created` as sync cursor), offline queue, real-time subscription handling. |
| **UI & routing** | All screens, navigation, forms, modals, i18n, PWA installation, service worker. |

### C.7 Authentication Flow

1. **Group creation:** Client solves PoW challenge, sends solution to server. Server validates and creates group record.
2. **User account creation:** Client derives password from group key as `Base64URL(SHA-256(Base64(groupKey)))` and creates a user record with username `group_{groupId}`.
3. **Session authentication:** Client authenticates with username/password to receive a JWT token. All subsequent API calls include the token as `Authorization: Bearer {token}`.
4. **Token refresh:** Client refreshes the JWT token before expiry to maintain the session.

Note: "User accounts" here are per-group server accounts for API access. They are unrelated to user identity (the cryptographic keypair). Anyone with the group key can derive the same password and authenticate.
