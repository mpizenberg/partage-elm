# Partage Feature Specification

Partage is a fully encrypted, local-first bill-splitting Progressive Web App for trusted groups such as friends, families, and roommates.

This document is the contract for the shipped product: user-visible behavior, ledger semantics, privacy guarantees, and interoperability constraints. Source code and tests define implementation details. Deployment instructions live in [DEPLOY.md](DEPLOY.md), and storage/performance rationale lives in [STORAGE_AND_PERFORMANCE.md](STORAGE_AND_PERFORMANCE.md).

## Product principles

- **Privacy first.** Group content is encrypted in the browser. The relay stores and transports ciphertext.
- **Local first.** A device keeps the full group history, works offline, and synchronizes when online.
- **No accounts.** A browser identity is a locally generated signing keypair, not an email/password account.
- **Trusted groups.** Possession of an invite link grants the group key. Members can edit shared data; signed history provides attribution rather than per-field permissions.
- **Preserved history.** Group changes form an append-only, signed event log. Editing, deleting, and restoring entries does not erase prior versions.
- **Deterministic convergence.** Devices with the same valid event set derive the same group state.
- **Relay as cache.** Client replicas are the system of record and can restore missing relay history.

## Identity and local device state

### Browser identity

On first use, Partage creates an ECDSA P-256 keypair with the Web Crypto API. The SHA-256 hash of the public key is the device identifier used to author events. No name, email address, password, or centralized registration is required.

One current identity is stored in IndexedDB per browser profile. It survives normal sessions but is lost when browser storage is cleared. There is no password recovery. A user with a new identity can still recover access by opening an invite, importing a group backup, or linking the new device to an existing member.

The About page can deliberately replace the signing identity after suspected compromise. The prior device identifier is retained locally only to make recovery and relinking discoverable. The new identity cannot author events in an existing group until it is linked there.

The device also stores a local self-profile containing contact and payment details. It can pre-fill the user's member metadata in different groups, but is never synchronized by itself.

### Local preferences and diagnostics

Language, archive state, notification subscriptions, usage statistics, dismissed security findings, and developer-mode settings are local to the browser unless their feature explicitly says otherwise.

The app keeps an in-memory error log that can be copied or shared as a debug report. Developer mode exposes per-group diagnostics for event counts, storage, compression, synchronization, verification, replay timing, and security signals. Diagnostics are computed locally and do not expose decrypted content to the relay.

## Groups and membership

### Creating and managing a group

Creating a group requires:

- a group name;
- the creator's display name;
- an immutable default currency; and
- a proof-of-work challenge that limits automated group creation.

Virtual members may be added during creation. Group subtitle, description, and labelled links can be edited later. Group metadata and its changes are encrypted and appear in the activity history.

A group can be archived locally. Archiving makes it read-only, stops synchronization and live updates, and removes its push subscription. Unarchiving resumes synchronization and live updates; notifications must be enabled again separately. Removing a group deletes only that device's local copy; it does not erase other replicas or immediately delete relay data.

### Members

A group contains:

- **real members**, represented by one or more linked device identities; and
- **virtual members**, name-only placeholders that can participate in the ledger before using Partage.

Members can be renamed, retired, and restored. Retired members remain in history and balances but are excluded from normal active-member choices. Active members are displayed with the current user first and the others alphabetically; retired members are separated.

Member metadata can contain phone, email, notes, and settlement handles for IBAN, Wero, Lydia, Revolut, Wise, PayPal, Venmo, Cash App, Bitcoin, and Cardano. This metadata is encrypted with the group key. The UI provides copyable values and links where a payment method supports one.

### Claiming and relinking

A device joins or recovers a group by linking itself to a member root. Claiming a virtual member is the primary join path; recovering an existing real member and joining as a new member are also available.

A device has one effective link. A newer self-authored link replaces its previous claim, so an incorrect claim can be repaired without deleting history. Member roots remain stable for balances, entries, names, and metadata regardless of which devices currently claim them.

A device may only assert its own link. Other group operations must be authored by an identity already recognized as a member; invalid or unauthorized events are ignored during deterministic replay.

### Merging duplicate members

Members can be merged after a preview and type-to-confirm step. The selected target remains; active entries and settlement preferences that refer to the source are rewritten, transfers that would become self-transfers are deleted, and the source is retired. The resulting changes remain individually visible in history.

## Ledger

### Entry kinds

Partage supports three entry kinds:

| Kind | Meaning | Participants |
|---|---|---|
| Expense | Shared cost paid on behalf of beneficiaries. | One or more payers; one or more beneficiaries. |
| Transfer | Direct payment between two members. | One sender and a different recipient. |
| Income | Money received on behalf of beneficiaries. | One receiver; one or more beneficiaries. |

All entries have an amount, currency, date, optional notes, and optional labelled URL attachments. Expense and income descriptions are required; transfer descriptions are optional.

Expenses also support multiple payer amounts and an optional category: Food, Transport, Accommodation, Entertainment, Shopping, Groceries, Utilities, Healthcare, or Other. Historical expense locations are preserved and displayed, although the current entry form does not create or edit them.

Attachments are links, not uploaded receipt files. Their labels and URLs are encrypted as entry content.

### Splits and validation

Expense and income beneficiaries can be split in either mode:

- **Shares:** each selected member has a positive number of shares. Integer minor units are divided proportionally, with deterministic remainder distribution so allocations sum to the entry total.
- **Exact amounts:** every selected member has an explicit amount, and their sum must equal the entry total.

An expense can have one or more payers. Multiple payer amounts must sum exactly to the expense total. Amounts must be positive, required participants must be selected, and a transfer cannot send to the same member it comes from.

### Multi-currency entries

Supported currencies are EUR, USD, GBP, CHF, JPY, AUD, CAD, NZD, BRL, and ARS. Amounts are stored as integers in each currency's smallest unit; JPY has zero fractional digits and the others have two. Display formatting follows the selected English or French locale.

Every group has one default currency. An entry in another currency must also store a positive equivalent amount in the group currency. The form can fetch an indicative rate when available, but the user remains responsible for the stored equivalent. Balances and settlement plans use the stored group-currency amount, never a later market rate.

### Versions, deletion, and duplication

Every entry belongs to a version chain. Editing creates a new complete version linked to its predecessor. The deepest valid chain wins; concurrent versions at the same depth use a deterministic identifier tie-break. All accepted versions remain available to the audit trail.

Deletion and restoration are events over the entry root. Deleted entries are omitted from balances and hidden by default, with an option to display and restore them.

Duplicating an entry opens a pre-filled form with today's date and creates a new, unrelated entry chain.

## Balances and settlement

### Balance semantics

All calculations use integer minor units in the group's default currency.

| Entry kind | Credit contribution | Debt contribution |
|---|---|---|
| Expense | Amounts paid by payers. | Amounts allocated to beneficiaries. |
| Transfer | Amount sent by the sender. | Amount received by the recipient. |
| Income | Amounts allocated to beneficiaries. | Total amount received by the receiver. |

A member's net balance is total credit minus total debt. A positive value means the group owes the member; a negative value means the member owes the group. Deleted entries do not contribute. Linked device identifiers resolve to stable member roots before aggregation.

### Settlement plan

Partage derives a complete set of suggested transfers from current balances. A debtor's ordered preferred recipients are tried before the remaining creditors are matched greedily. Members can record a suggestion directly as a transfer and see the recipient's available payment methods.

The displayed plan is anchored at the latest non-transfer ledger change. Recording transfers adjusts that plan without unnecessarily reordering untouched suggestions, while preserving the current balance flow.

## Entries and activity views

The Entries view supports:

- case-insensitive search across descriptions, notes, and involved member names;
- person filters requiring every selected person to be involved;
- category, entry-kind, currency, and date-preset filters;
- OR matching within those non-person dimensions and AND across dimensions;
- deleted-entry visibility; and
- direct links to individual entries.

Date presets are Today, Yesterday, Last 7 days, Last 30 days, This month, and Last month.

The activity feed is derived from accepted history, shown newest first and grouped by date. It includes entry, member, group-metadata, and settlement-preference changes. Entry modifications identify changed fields and retain historical participant allocations, attachments, and stored locations. Activities can be filtered by activity family, actor, and involved members, and entry activities link back to the entry.

Unknown events from newer clients appear as update-required activity rather than being discarded from storage.

## Invitations and joining

An invitation has the shape:

```text
https://<app-domain>/join/<group-id>#<group-key>[.<attestation>]
```

The group identifier is sent in the URL path. The encryption key is in the fragment, which browsers do not send in HTTP requests. Anyone who obtains the complete link can read the group and authenticate to its relay, so links must be shared through trusted channels.

The optional fragment tail attests to the inviter's pushed history head. A joiner that understands the attestation refuses a relay history that does not reach it. Unknown tail formats remain ignorable for forward compatibility.

The invite view offers a QR code, copy action, Web Share integration when available, and a warning about trusted sharing. Opening an invite creates a browser identity if necessary, downloads and verifies the history, then offers member claiming, recovery, or creation of a new member with a unique display name.

## Import and export

### Partage backup

A group can be exported as a compressed `.partage` backup containing its group key, summary, and complete event history. It is a sensitive portable copy of the group and must be protected like an invite link.

Import verifies the file and event signatures, rejects a duplicate local group identifier, and preserves unknown event data. Invalid events are dropped and reported. A device that is not represented in the imported group opens it read-only and can recover or join from that local history without obtaining another invite.

### Spreadsheet export

A one-way CSV export contains one row per active expense, transfer, or income with dates, amounts, currencies, participants, category/location where applicable, notes, and creator. It is intended for spreadsheets and accounting, not re-import.

### Splitwise import

Partage imports English-language Splitwise group CSV exports into a new group. The user chooses the group identity/default currency and can provide conversion rates for other currencies. Payments become transfers. Because Splitwise exports member net amounts rather than every original allocation, Partage reconstructs splits while preserving each row's balance effect and reports skipped malformed rows.

## Offline operation and synchronization

### Local durability

The full raw event log, group key, sync position, and unsynchronized state are stored in IndexedDB. Local changes apply immediately while offline. When the first group is created, joined, or imported, Partage asks the browser for persistent storage to reduce eviction risk and reports whether it was granted.

A browser export is the durable backup under the user's control. Clearing browser data without a backup or another replica can permanently lose both identity and local history.

### Event and convergence contract

Events are signed, immutable envelopes sorted by client timestamp and event identifier. Event identifiers provide a deterministic total order, and authors clamp new timestamps after the latest history they have observed. Replay validates references, version chains, lifecycle transitions, and author permissions; invalid events do not affect state.

An envelope is preserved in its received JSON form so unknown fields and payloads survive storage, export, and synchronization. A newer event that cannot be decoded is retained and ignored for state until the app is updated. Malformed envelopes or records that cannot be decrypted are skipped and reported without blocking later synchronization.

### Synchronization contract

The relay stores encrypted, optionally compressed batches. A device pushes unsynchronized events, pulls later relay records using a cursor, deduplicates by event identifier, and receives live-update hints over WebSocket. Push records have content-derived identities so retrying after a lost response does not create another relay record.

Cursor reset and relay-incarnation changes trigger a safe full pull. Sync only adds events to a local replica; no relay response can make the client discard local history. After detecting missing relay history, an honest client re-pushes the events it still holds.

### Relay retention, recovery, and compaction

The hosted relay is a cache with these current limits:

- groups inactive for 12 months are eligible for purge;
- a group is capped at 50 MB or 50,000 relay records;
- new data is rate-limited to approximately 5 MB per group per month; and
- individual encrypted records are capped at 1 MB.

Any authenticated member's synchronization refreshes group activity. A surviving replica can resurrect a purged group through the normal proof-of-work creation flow and restore its history. Long-idle groups are surfaced locally so users can make an archival export.

Compaction re-batches the same signed envelopes; it never replaces history with a state snapshot. A proposal and approvals are part of the signed log. Execution requires the proposer and a majority threshold based on non-retired involved authors, while new joiners verify the manifest and approvals. Relay-side races are rejected transactionally. Unauthorized relay truncation cannot delete an existing member's local history and is healed by re-push.

## Encryption and security

### Cryptographic boundary

Partage uses:

| Purpose | Primitive |
|---|---|
| Group content encryption | AES-256-GCM with a random 12-byte IV |
| Event signatures | ECDSA P-256 with SHA-256 |
| Hashing and proof of work | SHA-256 |

Each group has one symmetric key shared through invite links and stored locally. It is not rotated within a group.

Every authored event is signed over its envelope. Self-creation and self-link events introduce public signing keys; already known keys cannot be replaced by a later event. Group creation is the genesis exception because no prior group key registry exists. Clients verify signatures before applying received events. A device joining from empty state necessarily trusts the earliest key introduction in the history it receives, so the trusted-group model does not prevent an existing member from poisoning that initial view with a backdated introduction.

Breaking changes to signature algorithms require an explicit recovery path for events rejected by older clients. Breaking envelope changes require a schema-version gate. Adding fields is safe only while raw-envelope preservation and signature canonicalization remain intact.

### Relay visibility and authentication

The relay can observe group identifiers, author device identifiers, relay sequence/receive times, encrypted record sizes, request frequency, and network addresses. A shared actor identifier may be correlatable across groups hosted by the same relay. The relay cannot read names, entries, balances, member metadata, signing keys carried inside encrypted envelopes, or other group content.

Relay access uses a bearer secret derived one-way from the group key. The relay stores a second hash as verifier and compares presented credentials in constant time. A leaked bearer grants relay access but does not reveal the group key or decrypt history. Because all key holders share relay credentials, the relay authenticates the group rather than individual members.

### Compromised-member model and migration

A device compromise exposes its signing key and every group key stored on it. Past and future read access to those groups cannot be revoked. A valid key holder can also author attributed events and can deny relay service by consuming group quotas.

Partage protects history rather than promising to prevent all malicious writes:

- there is no member-triggered relay route that deletes a whole group;
- destructive compaction is authorized by signed consensus and verified by clients;
- local replicas never discard history in response to relay state and can heal truncation;
- signature failures and rate-cap failures raise high-confidence local warnings;
- cursor resets and compaction-manifest mismatches remain advisory diagnostics because benign recovery and concurrency can cause them; and
- a local suspicion audit can flag foreign payment-detail changes and devices whose authorship pattern resembles a graft onto an established member.

Suspicion findings are heuristic and local. They can be dismissed per implicated identity and are withheld from the device they implicate.

The response to confirmed compromise is migration to a new group and key. Migration re-verifies and re-homes the old history, archives the old local group, and requires fresh out-of-band invitations. The migrator can exclude all events authored by selected identities or, for a leaked legitimate identity, exclude a tail using relay ingestion order rather than author-controlled timestamps. A preview of the surviving members, entries, and balances gates confirmation. Exclusion is unilateral and can remove legitimate history, so it is a deliberate curation decision rather than automatic repair.

### Push-notification exception

Push notifications are optional and use a separately configured external push service. The sending client determines affected members after a successful sync and excludes the actor.

Push is not zero-knowledge: group name, actor display name, and event kind are sent in plaintext to the push service. Subscription topics include opaque group and member identifiers, and the external notify endpoint is not authenticated by the Partage group bearer. Deployments without a configured push service hide notification controls.

## Progressive Web App, language, and accessibility

Partage can be installed on Android, iOS, macOS, and desktop browsers. It caches the application shell for offline use, reconnects and synchronizes after network recovery, and surfaces available application updates.

English and French are supported. Browser locale chooses the initial language, which can be changed from public, join, and About views. Translation sources are Fluent (`.ftl`) files compiled into Elm at build time. Currency, number, and date presentation follows the selected language and each currency's precision.

The interface is mobile-first and responsive. Forms have visible or accessible labels and validation errors; navigation uses links where appropriate; balance colors are accompanied by text; and the offline status is announced to assistive technology.

## Usage and cost information

Usage statistics remain local. Partage tracks estimated storage use, observed transferred bytes, and the tracking start date. The About page derives an informational infrastructure-cost estimate that can be reset. It is not billing and is never uploaded as analytics.

## Relay implementation contract

An alternative relay implementation must preserve these boundaries:

- store only relay metadata and opaque encrypted records;
- authenticate access with the shared group bearer verifier;
- gate public group creation with the signed proof-of-work challenge;
- append idempotently and page records with monotonic cursors;
- signal cursor/incarnation resets rather than silently hiding missing history;
- enforce record, group, and rate limits distinctly so clients can explain failures;
- notify live clients without exposing group content;
- compact transactionally without modifying encrypted records outside the submitted replacement set; and
- never add a member-triggered whole-group deletion capability.

The shipped relay supports a self-hosted SQLite process and Cloudflare Durable Objects. Endpoint shapes, database columns, operator observability, and deployment configuration are implementation concerns documented by source, conformance tests, and [DEPLOY.md](DEPLOY.md), not part of this feature specification.
