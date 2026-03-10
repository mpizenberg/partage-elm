# Migration Plan: Current UI → Warm Minimal Design

Local-first bill-splitting PWA. Migrating from blue/utilitarian design to warm minimal aesthetic.
The example UI in `../partage-design/design-1-warm-minimal/` is inspiration, not an exact spec.

---

## Design System Foundations

### Size Scales

All size scales use 7 levels: **xs, sm, md, lg, xl, 2xl, 3xl**.

| Scale | Purpose |
|---|---|
| **Font** | Text sizes. `md` is the default body size. |
| **Spacing** | Padding, gaps, margins. |
| **Radius** | Border rounding. Usually ~50% of the corresponding sizing. |
| **Sizing** | Fixed dimensions for interactive elements (buttons, avatars, icons, etc.). |

Borders are all **1px** thick by default.

### Color Palette

The theme is built from **6 colors**, each defined as a scale of **15 steps**.

| Color | Purpose |
|---|---|
| **Base** | Main background, text, general content |
| **Primary** | Highlights, accent color, CTAs |
| **Secondary** | Alternative to primary, design flexibility |
| **Success** | Positive feedback, confirmations |
| **Warning** | Cautionary content, non-critical warnings |
| **Danger** | Errors, destructive actions |

Inspired by the warm minimal example:
- **Base** — warm neutrals (off-white `#FFF8F0` bg, dark gray `#2D2D2D` text)
- **Primary** — coral `#E8725C`
- **Secondary** — TBD (muted complement or analogous)
- **Success** — sage green `#6B9080`
- **Warning** — TBD (warm amber)
- **Danger** — muted red `#C4655A`

#### Color Scale Steps (per color)

**Background:**
- **bg** — main background
- **bg-subtle** — slightly darker alternate, for depth

**Tint:**
- **tint** — subtle element backgrounds
- **tint-subtle** — subtler, for "pressed" states
- **tint-strong** — stronger, for "hovered" states

**Accent:**
- **accent** — dividers, borders, small UI elements
- **accent-subtle** — for "pressed" states
- **accent-strong** — for "hovered" states

Accent colors are not for backgrounds or text — no contrast guarantee. Use for colored decorative elements only.

**Solid:**
- **solid** — solid elements (buttons, badges)
- **solid-subtle** — for "pressed" states
- **solid-strong** — for "hovered" states
- **solid-text** — contrasting text color over solid backgrounds (accessibility)

**Text:**
- **text** — primary text color, accessible over bg and tint
- **text-subtle** — secondary text, accessible over bg and tint

**Shadow:**
- **shadow** — darker shade for shadow coloring (typically used with alpha, e.g. `rgb(shadow / 0.25)`)

### Shell & Navigation

Three page layout types:

| Layout | Used for | Header | Bottom |
|---|---|---|---|
| **Home** | Home page | App title, minimal | No tabs |
| **Tabbed** | Group pages (Balance, Entries, Members, Activity) | Group name, navigation | Bottom tab bar |
| **Standard** | All other pages (Setup, About, NewGroup, forms, details) | Back button + title | No tabs |

Language selection moves from header to the About page.

---

## Step 1: Design Tokens (`UI.Theme`)

Rework all tokens. This is the foundation everything else depends on.

- Define 6-color palette with 15-step scales (base, primary, secondary, success, warning, danger)
- Define 4 size scales at 7 levels each (font, spacing, radius, sizing)
- Add font family (Inter + system fallbacks)
- Add font weights (regular 400, medium 500, semibold 600, bold 700)
- Add letter-spacing tokens
- Add shadow tokens (standard, large, accent, knob) using the shadow color step
- Add z-index tokens (content, fab, tab-bar, toast)
- Set borders to 1px default

**Impact:** Every file using `Theme.*` will need review, but changing tokens first means subsequent steps automatically pick up the new values.

---

## Step 2: Shell & Navigation (`UI.Shell`)

Rebuild the app shell and navigation for the 3 layout types.

- **Home shell** — app title header, no tab bar, standard bottom padding
- **Tabbed shell** — group name header with navigation, bottom-fixed tab bar (icons + labels, primary-colored active state), extra bottom padding for tab bar
- **Standard shell** — page header with back button + title/subtitle, no tab bar
- Mobile-focused max-width (430px, centered)
- Remove language selector from header

---

## Step 3: Base Components (`UI.Components`)

Rebuild component library with warm minimal style. Take inspiration from the example components.

**New components:**
- Avatar (circular, initials, color variants)
- Chip (selectable pill, for filters)
- Toggle (switch control)
- FAB (floating action button)
- SearchBar
- Card wrapper (white bg, border, shadow, rounded)
- Section label (uppercase, small, tertiary)
- Balance badge (positive/negative/settled)
- Expand trigger (collapsible section header with animated chevron)
- Horizontal separator

**Reworked components:**
- `balanceCard` — dark "your balance" card + member balance cards with avatars
- `entryCard` — new layout with category tags, date grouping
- `memberRow` — avatar + expandable action buttons
- `settlementRow` — from→to flow with amounts

**Updated components:**
- `pwaBanners` — warm styling
- Toast system — warm colors

**Interaction:**
- Smooth transitions (200–300ms, custom bezier easing)
- Hover/pressed states using tint and accent scale steps

---

## Step 4: Home Page

Restyle to match the warm minimal home design.

- App title "Partage" large and bold
- Notification section with toggle
- Group cards (member count, creation date, balance badge)
- Archived groups (expandable section)
- Action buttons: Import Group, Join Group (outline style)
- Primary "Create Group" button
- Footer with About link

---

## Step 5: Balance Tab

Rebuild the balance view.

- "Your Balance" prominent card (dark bg, large amount, contrasting text)
- Other members section with avatar-based balance cards
- Expandable member cards with "Record transfer" action
- Settlement plan (from→to flow with amounts)
- Collapsible settlement preferences with radio selection

---

## Step 6: Entries Tab

Rebuild entries list with filter UX and new card layout.

- Summary row (entry count + total amount)
- Filter button → toggleable chip-based filter panel
- Search bar
- Entries grouped by date with separator headers
- Entry cards: description|amount, date+category tag, payer→recipients
- FAB for "new entry"

---

## Step 7: New Entry Form

Restyle the complex form.

- Mode toggle (Expense/Transfer) as pill selector
- Styled field labels with required indicator (*)
- Custom select dropdowns with chevron
- Custom checkboxes and radio buttons for payer/split
- Transfer mode: visual from→to member picker
- Consistent spacing and card grouping

---

## Step 8: Members Tab

Rebuild members page.

- Push notification toggle
- Group info card with description and links
- Invite section (Copy link, Share, QR code buttons)
- Member list with avatars and expandable action cards
- "You" member with distinct styling (dark background)
- Retired members (collapsible section)
- "Add Member" primary button

---

## Step 9: Remaining Pages & Polish

Update simpler pages and cross-cutting concerns.

- Setup, About (+ language selector moved here), Join, NewGroup, 404 pages
- Entry Detail, Member Detail, Edit Member, Edit Group pages
- Toast system (warm styling)
- Design System showcase page (update to reflect new tokens/components)
- Animation polish and interaction consistency

---

## Execution Notes

- **Steps 1–3** are foundational — tokens, shell, components. Must be done first, in order.
- **Steps 4–8** are the 5 prototype pages. Can be done in any order. Balance and Entries are the most complex.
- **Step 9** is cleanup for pages not in the prototype set.
- Each step may temporarily break the build. Mitigate by keeping old token aliases during transition, or by bundling Steps 1–3 together.
