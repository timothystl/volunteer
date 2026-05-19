# CLAUDE.md — TLC ChMS App

Read this at the start of every session. Update NOTES.md (and this file if needed) as items are discovered, fixed, or queued.

---

## What This App Is

**TLC Gather** — the Church Management System (ChMS) for Timothy Lutheran Church. Built on **Cloudflare Workers + D1 (SQLite)**. Single-page admin app assembled from per-tab modules under `src/frontend/` (shell in `src/html-chms.js`). API routes live in domain modules under `src/` — all delegated from `src/api-chms.js` — plus `src/api-admin.js` (auth, users, scheduler).

The same Worker also serves the **public volunteer signup site** at `volunteer.timothystl.org`, assembled from per-ministry modules under `src/public/`.

**Live at:**
- `https://chms.timothystl.org` — admin app (old `volunteer.timothystl.org/chms` redirects here)
- `https://volunteer.timothystl.org` — public ministry signup
- Brand: TLC Gather (navy/teal/gold three-pillar system: People / Ministry / Giving). PWA icons under `icons/`.

---

## Key Files

| File | Purpose |
|------|---------|
| `manual.html` | Standalone operator reference manual (all 14 sections, no external CSS) |
| `tlc-volunteer-worker.js` | Worker entry point — routes all requests |
| `src/api-admin.js` | Auth, user management, scheduler API |
| `src/api-chms.js` | ACL checks, dashboard, delegation to domain modules |
| `src/api-people.js` | People CRUD, archive, Brevo sync, photo upload, follow-ups |
| `src/api-giving.js` | Giving entries, batches, quick entry |
| `src/api-households.js` | Households, organizations, tags, funds |
| `src/api-reports.js` | Reports, engagement queue, prayer requests, reconcile tools |
| `src/api-import.js` | Import/sync, config, register, export, Breeze sync |
| `src/api-utils.js` | Shared utilities (disambiguateHHName, isoWeekKey) |
| `src/html-chms.js` | Admin SPA shell (~300 lines) — imports & concatenates the per-tab modules below |
| `src/frontend/*.js` | Per-tab admin modules: `html-head.js`, `html-tabs.js`, `js-core.js`, `js-{settings,dashboard,people,register,households,giving,reports,export-import,attendance,volunteers}.js` |
| `src/html-templates.js` | Login page HTML + assembly of `PUBLIC_HTML` (volunteer.timothystl.org) from `src/public/` modules |
| `src/public/{head,landing,footer,scripts}.js` | Public site shell: head/CSS, landing card grid, footer, JS |
| `src/public/ministries/*.js` | One file per ministry detail page (worship, education, acceptance, outreach, wol, lasm, cfna, transportation, events, general) |
| `src/auth.js` | Cookie auth, PBKDF2 password hashing, helpers |
| `icons/` | PWA icons (16/32/180/192/512/512-maskable) + `tlc-gather-icon.svg` source |
| `NOTES.md` | Full backlog, resolved issues, recent changes |
| `wrangler.toml` | Cloudflare Worker config |

---

## Architecture Notes

- **Auth**: Cookie-based HMAC-SHA256. Login checks `app_users` table first (per-user DB accounts), falls back to `ADMIN_PASSWORD` env-var for break-glass admin access only.
- **Roles**: `admin | finance | staff | member` — enforced in `api-chms.js` ACL block; domain modules receive pre-computed `isAdmin/isFinance/isStaff/canEdit` flags.
- **Photos**: Stored in R2 bucket `tlc-chms-photos`; served via `/admin/r2photo/` proxy.
- **Breeze ChMS sync**: `POST /admin/api/import/breeze` (bulk) and `POST /admin/api/import/breeze-sync-person` (per-person). See NOTES.md for field ID quirks.
- **D1 param limit**: ~100 per statement. Use chunked queries for large IN/NOT IN lists.

---

## Multi-App Architecture — Current State & Options

The church currently runs three separate Cloudflare Worker apps:

| App | Purpose | Key Services |
|-----|---------|-------------|
| **ChMS** (this app) | People, giving, households, attendance | D1, R2, Breeze API |
| **Scheduler** | Volunteer scheduling for services | Resend (emails to volunteers) |
| **Website admin** | Website content, news/events, newsletter | Brevo (newsletter to subscribers) |

### The Question
These apps share a common subject (church members/people) but are currently siloed. EM1/EM2/SMS, plus SC1 (native scheduler), raise the question of how tightly to integrate them.

### Options

**Option A — Keep separate, add direct integrations (recommended near-term)**
Each app stays its own Worker. ChMS talks directly to Brevo and Resend APIs via their REST APIs (no inter-app calls needed). Scheduler stays separate until SC1 is scoped. Website admin stays separate (content management is a different concern from membership).
- Pros: No migration risk, can ship EM1/EM2 quickly, each app fails independently
- Cons: Person data is duplicated across apps; Brevo/Resend config duplicated

**Option B — ChMS as people source-of-truth; other apps call ChMS API**
Other apps query ChMS for member data instead of maintaining their own. Scheduler checks ChMS for volunteer info; website admin pulls member emails from ChMS for newsletter sync.
- Pros: One source of truth for people data, no drift
- Cons: Adds cross-Worker API calls and auth between apps; breaking ChMS breaks others
- This is the right long-term direction but requires adding a service API layer to ChMS

**Option C — Absorb scheduler into ChMS (SC1)**
Move all scheduler logic into this app. Reuse ChMS person records, D1 DB, and Resend config already in ChMS. Most natural merge since scheduler is tightly coupled to people/roles.
- Pros: Single login, shared person data, one deployment
- Cons: Large effort; scheduler may have its own DB schema and frontend
- SC1 is already on the backlog — this would be the implementation approach

**Option D — Full merge of all three apps**
Combine ChMS + Scheduler + Website admin into one Worker.
- Not recommended: website admin (CMS/content) is a genuinely different domain from membership management. Merging adds complexity without much benefit.

### Recommended Path
1. ~~**Now**: Build EM1/EM2~~ ✅ Done (v83/v84).
2. **Next**: Absorb Scheduler into ChMS (SC1, Option C) — backend already merged, UI integration remaining.
3. **Long term**: Consider a thin "people API" in ChMS that website admin and any future apps can query (Option B) — but only when the pain of duplicated data is actually felt.

### Prerequisites for EM1/EM2
- `RESEND_API_KEY` — **already in this worker** (used by `src/api-scheduler.js`)
- `EMAIL_FROM` — **already in this worker** (e.g. `Timothy Lutheran <noreply@timothystl.org>`)
- `BREVO_API_KEY` — **already in this worker** (added 2026-04-20)
- `BREVO_LIST_ID` — **already in this worker** (added 2026-04-20)

### EM1 — Done (v84)
Brevo sync built: "Add to Newsletter" button on profile, bulk sync + reconciliation view in Settings, auto-sync on member email change.

### EM2 — Done (v83)
Birthday/anniversary emails built: daily cron at 9am Central, Resend, dedup via audit_log, admin test buttons in Settings.

---

## Current Backlog Status

Full detail in `NOTES.md`. Summary:

- **Phases 1–5c**: All complete as of 2026-04-16 (v25).
- **Phase 6**: H1 (Organizations) and H3 (Household giving) done as of 2026-04-17 (v26). Remaining: N2 Scheduler integration, I1 Subdomain rename.
- **Anything added below this line was noted mid-session and not yet scheduled.**

---

## Development Phases

Use this as the session-to-session roadmap. Complete one phase fully before starting the next. Each phase has a clear goal, bounded scope, and "done" criteria.

---

### Phase 1 — Housekeeping & Data Verification ✅ DONE 2026-04-24
**Goal:** Zero-risk cleanup and data confirmation. No code changes to prod logic.

- [x] **IN6** — `SECRETS.md` written: all 7 secrets + 3 bindings documented with purpose and rotation steps.
- [x] **IN10** — D1 backup/restore runbook written (see `## D1 Backup & Restore` section below).
- [x] **G11** — Verified. All four entries confirmed correct.
- [x] **G12** — Verified. Leah Sieveking fund change confirmed correct.
- [x] **G13** — Verified. Ghost fund entries resolved, no duplicates.
- [x] **G14** — Verified. Old entry gone, General Fund entry correct.
- [x] **G15** — Verified. Ron Rall split amounts correct.
- [x] **G16** — Verified. Kathy Carr TUB Bees fund correct.

---

### Phase 2 — Code Quality Prep ✅ DONE 2026-04-24
**Goal:** Reduce noise and isolate Breeze logic before the big refactor. No behavior changes.

- [x] **IN12** — Dead-code sweep: removed debug `console.log` from Breeze per-person sync and dead `setFdTag` function (no callers). Done 2026-04-24 (v113).
- [x] **IN5** — Extract Breeze API client into `src/breeze.js` (consolidates field-ID quirks, enables mocking for IN11). Done 2026-04-24 (v114).

**Done when:** No `console.log` artifacts in prod files; all Breeze HTTP calls live in `src/breeze.js`.

---

### Phase 3 — Infrastructure Safety ✅ DONE 2026-04-24
**Goal:** Establish a staging environment and clean up the Worker name before any further risky changes.

- [x] **IN9** — Staging environment live at `https://breeze-proxy-worker-staging.timothystl.workers.dev/chms`. Separate `wrangler.staging.toml` config (avoids wrangler v4 route inheritance bug). D1: `tlc-volunteer-db-staging`, KV: staging RSVP_STORE, shared R2, crons disabled. Deploy: `wrangler deploy --config wrangler.staging.toml`. Done 2026-04-24.
- [x] **IN1** — Worker renamed to `tlc-chms`. Added `chms.timothystl.org` as dedicated ChMS subdomain (root serves app directly; `volunteer.timothystl.org/chms` redirects). `tlc-newsletter-admin` service binding updated to `tlc-chms`. Old `breeze-proxy-worker` deleted. Done 2026-04-24.

**Done when:** Staging URL exists and responds; prod Worker is named `tlc-chms`. ✅ Phase 3 complete 2026-04-24.

---

### Phase 4 — Refactoring ✅ DONE 2026-04-25
**Goal:** Break the two monolith files into maintainable modules. No behavior changes.

- [x] **IN4** — Split `api-chms.js` into domain modules: `src/api-people.js`, `src/api-giving.js`, `src/api-households.js`, `src/api-reports.js`, `src/api-import.js`, `src/api-utils.js` — all delegated from `api-chms.js`. Done 2026-04-24 (v114–v118).
- [x] **IN3** — Split `html-chms.js` into per-tab frontend modules under `src/frontend/`: `html-head.js`, `html-tabs.js`, `js-core.js`, `js-settings.js`, `js-dashboard.js`, `js-people.js`, `js-register.js`, `js-households.js`, `js-giving.js`, `js-reports.js`, `js-export-import.js`, `js-attendance.js`, `js-volunteers.js`. `html-chms.js` reduced from 9,443 → 311 lines. Done 2026-04-25 (v120).

**Done when:** `html-chms.js` and `api-chms.js` no longer exist as monoliths; IDE can syntax-highlight and navigate the embedded JS/CSS.

---

### Phase 5 — Test Harness ✅ DONE 2026-04-25
**Goal:** Regression coverage for the highest-risk logic, now that code is modular enough to test.

- [x] **IN11** — Vitest setup; 37 tests across 3 files. Done 2026-04-25 (v121).
  - `test/utils.test.js` — `disambiguateHHName` (8 cases: falsy head, Family suffix, case-insensitive, plain name, org names)
  - `test/auth.test.js` — `hashPassword`/`verifyPassword` (7 cases: format, round-trip, wrong password, empty, unique salts, malformed stored, unicode)
  - `test/csv-import.test.js` — `parseFundSplits`, `givingEntryId`, `isGivingDup` (22 cases: nan/blank, numeric prefix, multi-fund split, colon format, nth-occurrence dedup)
  - `parseFundSplits`, `givingEntryId`, `isGivingDup` extracted from `api-import.js` to `api-utils.js` as exported functions

**Done when:** `npm test` passes; CI runs tests on every PR.

---

### Phase 6 — New Features
**Goal:** Add capabilities that have been scoped and are ready to build.

- [ ] **G3** — Gift entry workflow improvements (user has detail — schedule a dedicated scoping session first)
- [x] **R4** — Member tenure report: closed — `member_since`/`join_date` not available in Breeze field mapping; deferred indefinitely. (2026-05-01)
- [x] **BR1** — Reverse sync (app → Breeze): auto-push on person create, auto-update on contact field change. Done 2026-04-26 (v133).

**Done when:** Each item either shipped or formally deferred with a reason.

---

### Phase 7 — Large Features (needs scoping first)
**Goal:** Substantial new capabilities that require design decisions before coding starts.

- [x] **R6** — Per-person attendance tracking: closed — out of scope for now; service-total tracking is sufficient. (2026-05-01)
- [x] **IN2** — App merge strategy: closed — Decision: Option C (absorb scheduler, leave website admin separate) is the right long-term direction but not active work; website admin stays separate. No action needed until SC1 is revisited. (2026-05-01)
- [ ] **PM1** — Person merge: deduplicate records by moving giving, tags, and household membership to the canonical record then deleting the duplicate; needs a confirmation UI with diff view. (noted 2026-04-26)
- [ ] **PL1b** — Pledge tracking: new `pledges` table (person, year, amount); pledge vs. actual giving shown on profile and in a Giving Insights section. (noted 2026-04-26)

**Done when:** Each item either has a design doc / scoping decision logged here, or is in active implementation.

---

### Phase 8 — Critical Security Fixes (deploy immediately)
**Goal:** Eliminate SQL injection, broken auth fallback, and missing role guards. Zero behavior change for legitimate users. Ship as a single hotfix PR.

- [ ] **SEC1** — SQL injection: `api-households.js` line ~19 — `hhMemberType` query param interpolated directly into SQL. Fix: validate against allowlist `['member','visitor','regular_attender','friend']` and use `.bind()`. (`api-households.js`)
- [x] **SEC2** — SQL injection: `api-people.js` line ~766 — `entry.field` interpolated into column position. Closed — strict allowlist check immediately before the interpolation (`allowedFields.includes(entry.field)`) makes injection impossible in practice. Style could be improved to a `switch`, but no exploitable path exists. (2026-05-19)
- [ ] **SEC3** — SQL injection: `api-reports.js` line ~433 — prayer CSV export builds `WHERE pr.status = '${statusParam}'` by string concatenation. Replace with a parameterized bind. (`api-reports.js`)
- [ ] **SEC4** — Auth fallback: `api-chms.js` line ~476 — `role || 'admin'` grants full admin to any unauthenticated request that passes the outer router. Fix: `if (!role) return json({ error: 'Unauthorized' }, 401)`. (`api-chms.js`)
- [ ] **SEC5** — Missing role guard: `api-giving.js` — all write handlers accept `isFinance`/`isAdmin` flags but never check them. Add `if (!isFinance) return json({ error: 'Access denied' }, 403)` at the top of each write handler (create batch, add entry, edit entry, delete entry, quick-entry). (`api-giving.js`)
- [ ] **SEC6** — Missing role guard: `api-people.js` line ~264 — `POST /people/bulk-member-type` has no `isStaff` check. Finance-role users can silently bulk-change membership types. Fix: add `if (!isStaff) return json({ error: 'Access denied' }, 403)`. (`api-people.js`)
- [ ] **SEC7** — Missing role guard: `api-people.js` line ~756 — `POST /audit/undo` has no role check; any staff user can undo any field change on any person. Fix: require `isAdmin`. (`api-people.js`)
- [ ] **SEC8** — Missing role guard: `api-utils.js` line ~268 — `POST /utils/validate-address` is reachable by any authenticated user including `member` role, enabling quota exhaustion on the USPS/Lob API. Fix: add `if (!canEdit) return json({ error: 'Access denied' }, 403)`. (`api-utils.js`)

**Done when:** All eight items fixed, `npm test` passes, manual smoke test of auth + giving + audit-undo confirms correct 403 behavior.

---

### Phase 9 — XSS Fixes
**Goal:** Eliminate all cross-site scripting vectors. None of these change any feature behavior.

- [ ] **XSS1** — `esc()` does not encode single quotes → stored XSS in onclick attributes across `js-people.js`, `js-dashboard.js`, `js-households.js`. Every pattern like `onclick="fn('+p.id+',\''+esc(p.email)+'\', ...)"` is exploitable by any person whose name/email contains a single quote followed by JS. Fix: either add `'` → `&#39;` to `esc()` in `js-core.js` (simplest — fixes all call sites at once) **or** refactor all onclick string args to use `data-*` attributes and read them in the handler (preferred long-term). The `reviewArchive` pattern on `js-dashboard.js` line ~511 is the one correct example to follow.
- [ ] **XSS2** — `pvField()` in `js-people.js` line ~584 — puts raw DB values (including values written by Breeze sync) directly into `innerHTML` without `esc()`. Fix: wrap `val` in `esc()` inside `pvField`; create a `pvFieldHtml()` variant for callers that intentionally pass pre-built HTML (links, badges).
- [ ] **XSS3** — Organization website href in `js-households.js` line ~306 allows `javascript:` protocol injection. A stored `javascript:alert(1)` URL executes for any admin viewing that organization. Fix: `var safeUrl = /^https?:\/\//i.test(o.website) ? o.website : '';` before building the anchor.
- [ ] **XSS4** — `printRegister()` in `js-register.js` lines ~233–253 builds a full HTML document in a new window with all record fields (name, father, mother, sponsors, notes, officiant, place, etc.) concatenated raw. `renderRegisterList()` correctly uses `esc()` — bring `printRegister()` to parity.

**Done when:** All four items fixed; verify with a test person whose name contains `<script>` and `'` that no JS executes in any view.

---

### Phase 10 — High-Priority Bug Fixes
**Goal:** Fix correctness bugs that cause wrong data, silent failures, or broken UI. No schema changes required.

- [x] **BF1** — Hard-delete orphaned rows. Done 2026-05-19 (v218). Added `DELETE FROM giving_entries`, `DELETE FROM follow_up_items`, and `DELETE FROM audit_log WHERE entity_type='person'` inside the hard-delete block. (`api-people.js`)
- [x] **BF2** — Anniversary email partial send dedup. Done 2026-05-19 (v218). Track `atLeastOneSent`; write audit log if at least one email succeeded regardless of partial failure. (`api-emails.js`)
- [x] **BF3** — Anniversary audit log null `household_id`. Done 2026-05-19 (v218). Extract `hhKey = p1.household_id || p1.id` and use it consistently in all anniversary audit log `.bind()` calls. (`api-emails.js`)
- [x] **BF4** — Birthday emails sent to deceased. Done 2026-05-19 (v218). Added `AND (deceased=0 OR deceased IS NULL)` to birthday email query. (`api-emails.js`)
- [x] **BF5** — Register CSV/TSV import broken by `String.raw` double-escaping. Done 2026-05-19 (v218). Fixed all affected patterns: `split('\\t')` → `split('\t')`, `/\\r\\n/g` → `/\r\n/g`, `/\\s+/g` → `/\s+/g`, `/\\d/` → `/\d/` in all date-parsing regexes, `\\.?` → `\.?`, etc. (`src/frontend/js-register.js`)
- [x] **BF6** — Closed — `'sunday'` is correct; the backend stores `service_type='sunday'` for regular Sunday services. The documented enum `regular|special|midweek` was incorrect in the original review finding. Chart works as intended. (2026-05-19)
- [x] **BF7** — People Insights block titles show "undefined". Done 2026-05-19 (v218). Moved `var scopeLabel` declaration to before Block 1. (`src/frontend/js-reports.js`)
- [x] **BF8** — Fund create active flag always 1. Done 2026-05-19 (v218). Changed `b.active?1:1` to `b.active==null?1:b.active?1:0`. (`api-households.js`)
- [x] **BF9** — Soft-delete leaves `status='active'`. Done 2026-05-19 (v218). Soft-delete now sets both `active=0` and `status='archived'`. (`api-people.js`)
- [x] **BF10** — Anniversary audit log null `household_id` (write side). Done 2026-05-19 (v218). Covered by BF3 fix — `hhKey` used in all write paths. (`api-emails.js`)
- [x] **BF11** — Closed — already correct. The profile-view tag chip render (line ~909) sets `data-picked="1"` when `on` is true. The `getSelectedTagIds` bug (FH7) is a separate issue in the person edit *modal* picker (`openPersonEdit`), tracked under FH7. (2026-05-19)
- [x] **BF12** — `normalizePhone()` crashes on non-string. Done 2026-05-19 (v218). Changed guard to `if (!raw || typeof raw !== 'string') return ''`. Closes **BUG1**. (`api-utils.js`)
- [x] **BF13** — `followupEditNotes` onclick notes injection. Done 2026-05-19 (v218). Store notes in `data-notes` on the row element; `followupEditNotes(id)` reads `row.dataset.notes` instead of taking a string argument. (`src/frontend/js-dashboard.js`)
- [x] **BF14** — Closed — intentional. Each Sunday creates 2 service records (8am + 10:45am), so `d.inserted / 2` correctly reports Sunday count, not service count. Never produces a fraction because the API always inserts in pairs. (2026-05-19)

**Done when:** All fourteen items fixed, `npm test` passes, manual verification of: attendance chart renders, People Insights titles show scope, birthday emails skip deceased, register import processes a real CSV.

---

### Phase 11 — Performance & N+1 Query Fixes
**Goal:** Eliminate patterns that will timeout the Cloudflare Worker under real data volumes (>200 people, >50 tags, >100 services) and remove unnecessary repeat round-trips in the frontend.

- [x] **PF1** — `api-admin.js` lines ~286–343 — bulk-fetch all slots, people, roles, fill-counts in 3 queries total instead of 2N+2M serial calls. Done 2026-05-19 (v219).
- [x] **PF2** — `api-import.js` line ~226 — attendance sync batches Breeze API calls with `Promise.allSettled` in groups of 25; DB updates collected then flushed via `db.batch()`. Done 2026-05-19 (v219).
- [x] **PF3** — `api-import.js` lines ~1830–1888 — pre-scan pass 1 collects all new batches/funds, bulk-creates them before the main insert loop. Done 2026-05-19 (v219).
- [x] **PF4** — `api-import.js` lines ~2093–2184 — tag-sync `phase=list` pre-loads all local tags into Maps, batches all UPDATE/INSERT statements. Done 2026-05-19 (v219).
- [x] **PF5** — `api-people.js` line ~270 — `bulk-member-type` chunks IDs at 89 to stay under D1 param limit. Done 2026-05-19 (v219).
- [x] **PF6** — `api-households.js` lines ~124–131 — `fix-heads` fetches best candidate per household in one aggregated query, batches all UPDATEs. Done 2026-05-19 (v219).
- [x] **PF7** — `api-utils.js` lines ~415–418 — `normalize-phones` collects all changes then fires as a single `db.batch()`. Done 2026-05-19 (v219).
- [x] **PF8** — `api-reports.js` lines ~619–635 — 5-year trend runs all 5 queries in parallel with `Promise.all`. Done 2026-05-19 (v219).
- [x] **PF9** — `api-reports.js` line ~1149 — giving-by-method replaces correlated subquery with explicit `JOIN giving_batches`. Done 2026-05-19 (v219).
- [x] **PF10** — `api-people.js` lines ~169–174 — household_size filter uses pre-aggregated JOIN subquery instead of per-row correlated subqueries. Done 2026-05-19 (v219).
- [x] **PF11** — `js-giving.js` line ~25 — `filterBatchSearch` caches last batch list and filters client-side without API call. Done 2026-05-19 (v219).
- [x] **PF12** — Closed — current pattern (calling both `openBatch` and `loadBatches` after entry add/delete) is correct. Both refreshes are needed: `openBatch` updates the entry table, `loadBatches` updates the batch sidebar total. No change needed. (2026-05-19)
- [x] **PF13** — `api-people.js` lines ~255–257 and ~417–419 — tag inserts on create/update use `db.batch()`. Done 2026-05-19 (v219).

**Done when:** All items fixed; verify that a full Breeze attendance sync, a tag sync, and a 500-person giving-by-method report all complete within the 30-second Worker limit.

---

### Phase 12 — Frontend Hygiene & API Consistency
**Goal:** Bring all API calls through the `api()` helper (for 401-redirect handling), eliminate redundant network round-trips, and fix low-severity UX/logic bugs.

- [ ] **FH1** — `js-volunteers.js` — all 16+ `fetch()` calls bypass the `api()` helper. Session expiry silently fails or returns raw JSON instead of redirecting to login. Replace all `fetch(url, { credentials: 'same-origin' })` with `api(url)` / `api(url, opts)`. (`src/frontend/js-volunteers.js`)
- [ ] **FH2** — `js-export-import.js` — `runBreezeGivingSync`, `runBreezeGivingAll`, `importGivingCSV`, `importPeopleCSV` use raw `fetch()`. Same fix as FH1. (`src/frontend/js-export-import.js`)
- [ ] **FH3** — `js-people.js` lines ~984–1173 — photo upload/delete/copy endpoints use raw `fetch()` (FormData upload path). Add 401 detection and consistent error propagation matching the `api()` helper pattern; at minimum add `.catch` error display for `usePVPhotoFrom`. (`src/frontend/js-people.js`)
- [ ] **FH4** — `js-people.js` lines ~313–327 — `applyBulkTags` makes 2N sequential API calls (GET + PUT per person). Add a `POST /admin/api/people/bulk-tags` endpoint (body: `{ tag_ids, person_ids, mode: 'add|remove|set' }`) and call it as a single round-trip. (`api-people.js` + `src/frontend/js-people.js`)
- [x] **FH5** — Closed — `createHouseholdFromPerson` reads directly from form fields; no intermediate GET person call exists. Original finding was incorrect. (2026-05-19)
- [ ] **FH6** — `js-dashboard.js` line ~679 and `js-people.js` lines ~937, ~1449 — `markSeenToday`, `savePvTags`, `confirmAddToHh` send the full `_currentPvPerson` snapshot via PUT, overwriting fields changed concurrently. Use `pvBuildPersonPatch` (or a dedicated PATCH endpoint) so only the intended field is sent. (`src/frontend/js-dashboard.js`, `js-people.js`)
- [ ] **FH7** — `js-people.js` lines ~1980–1988 — `getSelectedTagIds` detects selected chips via `el.style.borderColor` string comparison (fragile across browsers). `toggleTagPick()` already sets `el.dataset.picked = '1'`. Fix: `if (el.dataset.picked === '1') ids.push(parseInt(el.dataset.tid))`. (`src/frontend/js-people.js`)
- [ ] **FH8** — `js-people.js` lines ~2017–2036 — `gender` and `marital_status` are assigned twice in `savePerson`; the first assignment (lines ~2017–2018) is dead code. Remove the duplicate lines. (`src/frontend/js-people.js`)
- [ ] **FH9** — `js-attendance.js` resize handler line ~123 — Christmas marker hardcoded to `2026` inside the resize redraw path (`var cx2=xAtDate2(2026,12,25)`). The main `renderAttendanceChart` function already draws markers correctly per year. Fix: replace the hardcoded `2026` in the resize handler with the chart's actual year range. (`src/frontend/js-attendance.js`)
- [x] **FH10** — Closed — resize handlers properly call `document.removeEventListener` for both `mousemove` and `mouseup` inside the `mouseup` callback. No accumulation occurs. (2026-05-19)
- [ ] **FH11** — `js-households.js` lines ~15–26 and ~278–317 — `loadHouseholds` and `loadOrganizations` have no `.catch()` handlers; the "Loading…" status is never cleared on error. Add `.catch(function() { setStatus('h-status', 'Error loading.', 'err'); })`. Same gap in `openHouseholdDetail`, `openBatch`. (`src/frontend/js-households.js`, `js-giving.js`)
- [ ] **FH12** — `js-export-import.js` lines ~69–86 — `doSendBatch` promise chain: the no-email early-exit path returns `undefined`, which the downstream `.then(r => r && r.ok ? ...)` treats as a failure, silently inflating the failed count. Fix the promise chain so skipped-no-email rows increment `skipped` not `failed`. (`src/frontend/js-export-import.js`)
- [ ] **FH13** — `js-export-import.js` line ~743 — `runBreezeTagSync` uses the deprecated global `event` object; when called programmatically after a people import, it disables the wrong button and never restores its label. Fix: accept an explicit `btnEl` parameter and pass `this` from the onclick. (`src/frontend/js-export-import.js`)
- [ ] **FH14** — `js-volunteers.js` line ~241 — volunteer "To:" display receives an already-HTML-entity-encoded name/email (from the onclick attribute), then assigns it to `.textContent`, showing `&amp;` literals. Fix: pass raw values through `data-*` attributes and read them in `volOpenSendEmail`. (`src/frontend/js-volunteers.js`)
- [x] **FH15** — Closed — intentional by design. Empty fields are excluded from the payload so they don't overwrite existing stored values (documented with a comment in the code). This is correct UX: blank = "leave unchanged". (2026-05-19)

**Done when:** All items fixed; verify volunteers tab works after session expiry (redirect to login), bulk tag apply sends one request, and giving batch search filters without a network call.

---

### Phase 13 — Low-Priority Polish & Robustness
**Goal:** Minor correctness gaps, dead code, hardcoded values, and defense-in-depth improvements. Low risk; no urgency.

- [ ] **LP1** — `api-people.js` lines ~490, 495, 502 — archive audit log builds person name as `"${first} ${last}"` which produces `"null Smith"` if either field is null. Fix: `[person.first_name, person.last_name].filter(Boolean).join(' ')`. (`api-people.js`)
- [ ] **LP2** — `api-people.js` line ~758 — audit undo `b.id` is not validated as an integer; a non-numeric value returns 404 instead of 400. Fix: `if (!Number.isInteger(b.id)) return json({ error: 'Invalid id' }, 400)`. (`api-people.js`)
- [ ] **LP3** — `api-emails.js` line ~84 — `reply_to` address is hardcoded as `office@timothystl.org` in `sendResend`. Move to `env.REPLY_TO_EMAIL` or a `chms_config` key so it can change without a deploy. (`api-emails.js`)
- [ ] **LP4** — `api-import.js` line ~413 — `register/clear` only accepts `baptism|confirmation|wedding`; `funeral` and `anniversary` type entries can never be cleared. Add those types to the allowlist or document the intentional restriction. (`api-import.js`)
- [ ] **LP5** — `api-import.js` lines ~654–670 — CSV parser does not handle `""` escaped double-quotes per RFC 4180; Breeze notes fields with embedded quotes would be mangled. Fix: when inside a quoted field and the next char is also `"`, consume both as one literal quote. (`api-import.js`)
- [ ] **LP6** — `api-import.js` line ~1747 — `ghostFundContribs` diagnostic runs a full `giving_entries` table scan after every sync even when there are no placeholder funds. Add `LIMIT 50` to bound the scan. (`api-import.js`)
- [ ] **LP7** — `api-utils.js` line ~251 — Census geocoder fallback returns `deliverable: true` for any geocoded address even though it does no delivery-point validation (DPV). Add `source: 'census'` to the response so callers can show a caveat. (`api-utils.js`)
- [ ] **LP8** — `api-admin.js` line ~155 — break-glass `env.ADMIN_PASSWORD` still works if a DB user named `"admin"` is deactivated; interaction is undocumented. Add a comment clarifying the behavior. (`api-admin.js`)
- [ ] **LP9** — `api-people.js` lines ~694, 740 — `GET /followup` and `GET /audit` have no inner role guards; they rely solely on the outer ACL in `api-chms.js`. Add `if (!isStaff)` guards for defense-in-depth, matching the pattern used elsewhere. (`api-people.js`)
- [ ] **LP10** — `js-settings.js` line ~135 — `deleteUser` receives username as a JS string arg through the onclick; a username containing a backslash or crafted content could mislead the `confirm()` dialog. Fix: look up the username from `_usersData[id]` inside `deleteUser` instead of accepting it as a string argument. (`src/frontend/js-settings.js`)
- [ ] **LP11** — `js-giving.js` line ~20 — `_pendingOpenBatchId` is not cleared on API error; on the next successful `loadBatches` call it opens a stale batch ID. Fix: clear it before the `api()` call or in a `.catch`. (`src/frontend/js-giving.js`)
- [ ] **LP12** — `js-households.js` line ~410 — `createHouseholdFromPerson` POST is missing the `Content-Type: application/json` header. Add `headers: { 'Content-Type': 'application/json' }` consistent with every other POST in the codebase. (`src/frontend/js-households.js`)
- [ ] **LP13** — `js-dashboard.js` lines ~591, 595 — `dateStr` fallback puts `p.dob` directly in `innerHTML` when the date format is unexpected. Fix: `esc(p.dob || '')`. (`src/frontend/js-dashboard.js`)
- [ ] **LP14** — `js-volunteers.js` lines ~653–656 — stray `</script></body></html>` at the end of the template string. Remove; it is dead markup inside the assembled SPA. (`src/frontend/js-volunteers.js`)
- [ ] **LP15** — `js-core.js` lines ~58–65 and ~173–176 — `openPersonDetail` and `goToProfile` are near-duplicates. Make `openPersonDetail` a thin wrapper around `goToProfile`. (`src/frontend/js-core.js`)
- [ ] **LP16** — `js-export-import.js` line ~834 — chunk import error halts without reporting how many rows were processed before the failure. Update the status message to: `"Imported X of Y rows before error on chunk N."` (`src/frontend/js-export-import.js`)
- [ ] **LP17** — `js-attendance.js` — non-Sunday inline edit row has no delete button and no notes field, even though the form exists for special/midweek services that may need deletion. Add delete button to the non-Sunday edit path. (`src/frontend/js-attendance.js`)

**Done when:** All items resolved; each either fixed or formally documented as intentional with a reason.

---

## Queued Items (add new ones here during sessions)

<!-- Add items here as they come up. Format: - [ ] Description (noted YYYY-MM-DD) -->

### Branding / Public Site (2026-05)
- [x] **BR2** — TLC Gather rebrand. Done 2026-05 (PRs #454–#457). Three-pillar identity (People/Ministry/Giving), Cormorant Garamond + DM Sans, navy/teal/gold tokens, sidebar mark + wordmark lockup, topbar pill driven by `showTab()`, PWA icons + manifest under `icons/`.
- [x] **VS1** — Public volunteer page (`volunteer.timothystl.org`): added Transportation Ministry signup card. Done 2026-05 (PR #452).
- [x] **VS2** — `PUBLIC_HTML` split into per-section modules under `src/public/`, mirroring the IN3 split of `html-chms.js`. Each ministry is now a ~100-line file editable without sub-agent. Done 2026-05 (PR #453).
- [x] **BX1** — `member_type` case bug: Breeze returns "Member" (capitalized). All write sites now lowercase at the JS binding level + defensive `LOWER()` pass at end of each batch sync. Done 2026-05.

### Auth / Login
- [ ] **AU1** — Forgot password flow: add email field to each user account in admin; add "Forgot password?" link on login page that sends a reset email via Resend. (noted 2026-05-01)

### Settings
- [x] **ST1** — Hide testing sections in Settings tab from non-admin users (birthday/anniversary/SMS test buttons, etc.) — done 2026-05-01 (v165). Added `require-admin` class to EM2 and SMS1 import-cards.

### People List
- [x] **PL1** — Members-first people list: default view shows Members only; "Members" toggle button in toolbar switches to all-types view. Done 2026-04-20 (v82).
- [x] **PL2** — Archive/Deceased people: `status` column (`active|archived|deceased`) added; archived/deceased hidden from default list; "Archived" toggle button in toolbar; Archive/Deceased/Reactivate buttons on profile; anniversary cards exclude deceased. Done 2026-04-20 (v81).

### Giving / Finance
- [x] **G1** — Fund import: pre-fetches `/api/funds` from Breeze to resolve real names; retroactively renames any "Breeze Fund XXXXX" placeholders on next sync. Done 2026-04-17.
- [x] **G2** — Edit individual gifts from person profile: click batch number → opens that batch; click a gift row → modal to edit that individual gift (amount, fund, date, method, check #, note). Done 2026-04-17 (v27).
- [ ] **G3** — Overall gift entry workflow improvements (user has more detail — revisit in dedicated session). (noted 2026-04-17)
- [x] **G9** — Late-entry contributions: 45-day grace window added to sync — Dec contributions logged in Jan are now imported with their actual Dec contribution date. seenIds guard prevents double-import. Audit log limit raised to 10000. Done 2026-04-19 (v71).
- [x] **G4** — Reopen batch button is broken/dead — fixed 2026-04-17 (v37).
- [x] **G5** — Export data: persons, giving (year-by-year), and register data. Done 2026-04-17 (v38).
- [x] **G6** — Giving CSV import reconciliation fixes (v47, v51, 2026-04-17): (1) Negative entries (refunds/adjustments) were silently dropped — fixed. (2) "nan" fund name (blank exported by Excel) now maps to General Fund. (3) Float person IDs (`43826663.0`) now stripped. (4) Split-fund multi-row payments: Breeze exports one row per fund with same Payment ID; second row was treated as duplicate and fund allocation dropped — fixed with nth-occurrence tracking. Import now shows expandable list of skipped payment IDs as diagnostic.
- [x] **G7** — Giving by Fund report now groups funds by numeric code prefix (e.g., all "40085 *" variants under one collapsible group with subtotal). Done 2026-04-17 (v48).
- [x] **G17** — Giving by Fund report enhancements: (1) Total Givers count shown below report title. (2) "Reconcile Orphans" button fetches Breeze giving/list for the report's date range and removes stale DB entries (same safety logic as sync orphan pass — only deletes if a current replacement exists for same person+date). Endpoint: `POST /admin/api/giving/reconcile-orphans`. Use to fix the 2025 discrepancy ($547,367 app vs $537,624 Breeze): run the report for 1/1/2025–12/31/2025, click Reconcile Orphans. Done 2026-04-21 (v86).
- [x] **G19** — Force Remove Orphans. Diagnose confirmed all 43 entries of the 2025 discrepancy were "orphan" class (valid `breeze_id`, missing from Breeze's current giving/list). Root cause: Breeze's `bulk_contributions_deleted` event references the batch, not the payment IDs, so the sync's dedup never sees them as deleted. New admin-only `POST /admin/api/giving/force-remove-orphans` (`{start, end, confirm_count, confirm_cents}`) deletes those rows without the "current replacement exists" safety check. Guards: confirmation count/cents must match server recomputation; refuses if giving/list < 100 payments (truncation); only touches `breeze_id != ''` rows; writes an `audit_log` row `force_remove_orphans` with the removed id list. Red "Force Remove N" button shown on Diagnose view (admin only). Done 2026-04-21 (v89).
- [x] **G20** — Sync removes orphans automatically. The conservative same-person+same-date "current replacement" gate on the sync's orphan cleanup pass was leaving permanent extras whenever Breeze edits changed the contribution date or fully deleted a payment via `bulk_contributions_deleted`. Removed the gate: any DB row whose `breeze_id` is absent from `giving/list` for the window is deleted. Safeguards: skip cleanup if `giving/list` returned `>= 10000` rows (truncation) or if `> 50%` of in-window rows would go (likely API failure). Split-suffix `pid-N` legacy rows are matched against their base pid. Done 2026-04-27 (v148).
- [x] **G18** — Reconcile Diagnose tool. The 2025 discrepancy (+$9,743.50 across 4 funds, 43 entries) persisted after v86's Reconcile Orphans and after a full delete+resync. New read-only `GET /admin/api/giving/reconcile-diagnose?from=...&to=...` returns every DB entry in the range classified by whether its `breeze_id` still exists in Breeze's giving/list, plus per-fund extras totals, classification counts, twin-row detection (person+date+amount siblings with different `breeze_id`), and a `missing_from_db` inverse list. "Diagnose" button on Giving by Fund report renders the results table; "Export Extras CSV" dumps the extras for review. Surgical tool — no mutations — to identify *what* the 43 extras are before choosing a permanent fix. Candidates to expect: entries with empty `breeze_id` (manual/quick-entry — Reconcile Orphans can't see them), split-suffix rows `pid-2`/`pid-3` from the legacy CSV importer, or duplicate imports where audit-log `object_json` and giving/list `id` disagree. Done 2026-04-21 (v88).
- [x] **G8** — Re-import all giving years (2022–2026) after G6 fixes. Completed 2026-04-17 — all years 2021–2026 verified correct.
- [x] **G10** — Correction pass bug fixed (v85, 2026-04-21). Added orphan cleanup pass: after sync, DB entries in the window whose `breeze_id` no longer appears in giving/list are deleted if a current replacement exists for the same person+date. The supplement pass (v74) already imports the corrected version; this cleans up the stale old entry. Handles all cases where Breeze creates a new payment ID on edit.
- [x] **G11** — Verified 2026-04-24. All four entries (Anne Gonzalez, Pat Hunt, Horst Herrmann, John Hagan) confirmed correct after sync.
- [x] **G12** — Verified 2026-04-24. Leah Sieveking fund change confirmed correct.
- [x] **G13** — Verified 2026-04-24. Sue Koch and Thanh Nguyen ghost fund entries resolved; no duplicates.
- [x] **G14** — Verified 2026-04-24. Entry 488482959 gone; 514675972 (General Fund) correct.
- [x] **G15** — Verified 2026-04-24. Ron Rall split confirmed ($3,735.45 General + $1,500 PNG Mission).
- [x] **G16** — Verified 2026-04-24. Kathy Carr TUB Bees fund confirmed correct.

### Dashboard
- [x] **DB5** — Last worship card: show both services AND the combined total on a single card (not two separate cards). Done 2026-04-17 (v27).
- [x] **DB6** — Dashboard customization: ability to add, remove, and reorder/move cards on the dashboard. Done 2026-04-20 (v79) — show/hide cards via "⚙ Customize" button; preferences in localStorage.
- [x] **DB7** — Anniversary dashboard spouse pairing misses some households — fixed 2026-04-17 (v42). Secondary household lookup finds partner when only one spouse has anniversary_date set.
- [x] **DB8** — Anniversary pairing: further fixes 2026-04-17 (v49, v50). (v49) Secondary lookup broadened beyond head/spouse family_role. (v50) Removed member_type filter from secondary lookup — common pattern is one member + one visitor spouse; visitor was excluded and partner showed solo.

### Households / Data Quality
- [x] **HQ4** — Household head robustness scan: Settings card shows count of headless households; "Fix Household Heads" promotes spouse or first member. API: GET /admin/api/households/no-head-count and POST /admin/api/households/fix-heads. Done 2026-04-17 (v46).

### Photos
- [x] **PH1** — Household picture: upload photo for a household via hh-modal upload button → R2 → DB. Done 2026-04-17 (v46).
- [x] **PH2** — Crop profile picture: add a crop/resize tool when uploading a profile photo. Done 2026-04-20 (v79).
- [x] **PH3** — Black bar appearing above some household cards — fixed 2026-04-17 (v45). Wrapped photo img in a container div with background:var(--linen); onerror hides the whole container.

### People / Filters
- [x] **PF1** — Filter people by missing data fields: checkboxes organized by category with AND logic. Done 2026-04-17 (v46).
- [x] **PF2** — Filter people by positive attributes: age range and gender added to filter drawer (2026-05-01, v165). Gender radio (Any/Male/Female/Not set) and Age Range radio (Any/Under 18/18-29/30-44/45-64/65+) — both backend and frontend wired. Household type and sacramental status deferred (less commonly needed).

### Attendance / Reports
- [x] **AT1** — Attendance table collapse/expand toggle. Done 2026-04-17 (v46).
- [x] **AT2** — Attendance graph direction fixed: ORDER BY ASC so oldest dates plot left. Done 2026-04-17 (v46).
- [x] **AT3** — Attendance graphs: drag to resize charts. Done 2026-04-20 (v79).
- [x] **AT4** — Year-over-year giving/attendance report: overlapping graphs to compare current year vs prior year on the same chart. Done 2026-04-20 (v79) — Giving Trend tile in Reports tab; YoY attendance was already implemented.
- [x] **AT5** — Christmas/Easter markers on attendance chart + separate Special/Midweek bar chart. Done 2026-04-23 (v109). Easter/Christmas dashed markers on Sunday chart use `xAtAnyDate` interpolation so Dec 24/25 always render even when not Sunday. New `renderSpecialServicesChart` below the main chart shows amber (special) and purple (midweek) bars; midweek/special services excluded from Sunday average. New "+ Special" button adds `service_type=special` or `midweek` entries.
- [x] **AT6** — Attendance by Service report: multi-year comparison. Date Range / Multi-Year toggle buttons on tile; year checkboxes (last 5 years, 2 most recent pre-checked); `years=` param on API runs parallel D1 queries; `renderMultiYearServiceChart` draws grouped bar chart (X = service times, one bar per year). Done 2026-04-24 (v112).

### Communications / Email
- [x] **EM1** — Brevo newsletter sync: (1) "Add to newsletter" button on person profile → Brevo Contacts API, (2) bulk sync in Settings, (3) auto-sync on person save if email changes, (4) reconciliation view shows ChMS vs Brevo comparison with "Add All Missing" button. Done 2026-04-20 (v84).
- [x] **EM2** — Automated birthday/anniversary emails via Resend. Daily cron (`0 14 * * *`), birthday to member, anniversary to couple (shared email → one combined email). Dedup via audit_log. Admin test buttons in Settings. Done 2026-04-20 (v83).
- [x] **SMS1** — Birthday/anniversary SMS via Brevo Transactional SMS. `sms_opt_in` column added to `people` (`migrations/0002_add_sms_opt_in.sql`). `normalizePhone()` (E.164), `sendBrevoSms()`, `sendBirthdayTexts()`, `sendAnniversaryTexts()` in `src/api-emails.js`. Admin test buttons in Settings. Cron sends daily alongside emails. Person edit form: SMS opt-in checkbox. Done 2026-04-24 (v112).

### Scheduler
- [x] **SC1** — Scheduler integrated as a tab inside the ChMS SPA. `/scheduler?embedded=1` hides own header/tabs; ChMS sidebar "Scheduler" tab lazy-loads it in an iframe. Done 2026-04-21 (v92, fully working at v98).
- [x] **SC2** — Inline scheduler into ChMS SPA (no iframe). Done 2026-04-23 (v111). New `src/scheduler-inline.js` transforms `SCHEDULER_HTML` at module load time: CSS scoped with `.sched-root`, HTML stripped of login screen and header, conflicting IDs renamed (`sched-tab-*`, `sched-current-month-label`, `sched-app-content`), JS has 4 renamed functions (`schedFmtDate/ShowTab/SavePerson/DeletePerson`), `checkAuth()` + INIT block deferred to `window.schedInitScheduler()` (called on first Scheduler tab visit). Standalone `/scheduler` route unchanged.

### Breeze Integration
- [x] **BR1** — Reverse sync (app → Breeze). Done 2026-04-26 (v133). Auto-push new people to Breeze on create (no `breeze_id`); auto-update Breeze when name/contact fields change on people who have a `breeze_id`. `updatePerson` added to `breeze.js`. Field-ID discovery/building extracted to shared helpers. Manual "Push to Breeze" button remains as fallback.

### Reports / Insights (noted 2026-04-22)
- [x] **R1** — Age group breakdown across Membership Summary, Giving. Done 2026-04-22 (v102). Default buckets: Under 18, 18–29, 30–44, 45–64, 65+, Unknown (no DOB). Membership Summary gets an "By Age Group" table with count + share %. Giving by Fund gets a "By Age Group" table with givers, gifts, total, avg/giver, share %. Attendance age-groups deferred — we only track service totals, not per-person attendance (would require R6).
- [x] **R2** — Giving insights report: top givers (top N by year), lapsed givers (gave in prior year, nothing this year), giving frequency distribution, average gift amount trends. Done 2026-04-22 (v99). New `GET /admin/api/reports/giving-insights?year=YYYY` endpoint; new "Giving Insights" tile in Reports tab. Renders four blocks: top 25 givers (clickable to profile), lapsed givers (prior-year donors absent this year, sortable by prior total), frequency histogram (1 / 2-5 / 6-12 / 13-26 / 27+ gifts per giver this year), and 5-year trend table (givers/gifts/total/avg gift/avg per giver).
- [x] **R3** — People insights report. Done 2026-04-23 (v110). New `GET /admin/api/reports/people-insights` endpoint; new "People Insights" tile. Six sections: new contacts bar chart (24 months), new people by year × member type cross-tab, age distribution bars (6 buckets), gender pie chart, household composition bars (single/couple/small/large/none), sacramental pipeline bars (members only: neither/baptized/confirmed/both).
- [x] **R4** — Member tenure report. Closed — `member_since`/`join_date` not in Breeze field mapping; deferred indefinitely. (2026-05-01)
- [x] **RI1** — People Insights: default scope to Members only. Done 2026-05-01 (v165). Backend accepts `scope=member|active` param (default `member`); frontend shows "Members Only / All Active" toggle buttons; all six chart block titles updated to reflect scope.
- [ ] **RI2** — People Insights: sacramental pipeline ("neither/baptized/confirmed/both") shows no data for all members — trace the baptism/confirmation field mapping from Breeze to `people` schema and fix. (noted 2026-05-01)
- [x] **R5** — Contact info completeness report: counts of people missing email / phone / address / dob / photo; drill-down list per category. Done 2026-04-22 (v99). New `GET /admin/api/reports/contact-completeness?scope=active|member&field=...` endpoint. New "Contact Completeness" tile renders progress bars (green = complete) for each field with scope toggle (all active vs. members only); clicking a row drills to the list of missing records (clickable to profile).
- [x] **R6** — Person-by-person attendance tracking. Closed — out of scope; service-total tracking is sufficient for now. (2026-05-01)
- [x] **R7** — Easter/Christmas markers on Giving Trend chart. Done 2026-04-22 (v99). Easter computed per-year via Meeus/Jones/Butcher Gregorian algorithm, rendered as dashed vertical line in that year's color with "E" label. Christmas is shared Dec 25 dashed line in warm-gray with "C" label. Legend updated to explain the markers.
- [x] **R8** — Giving × Attendance overlay chart. Done 2026-04-22 (v102). New `GET /admin/api/reports/giving-vs-attendance?from=&to=` endpoint. Groups both datasets by Sunday-of-week. New "Giving × Attendance" tile on Reports tab. Chart: green bars (attendance, left axis) + teal line (giving, right axis). Overview stats include Weeks, Total Attendance, Total Given, Avg per Attender, and Pearson correlation coefficient with a qualitative label (Strong+/Moderate+/Weak+/None/Weak−/etc.).
- [x] **R9** — Pie chart for Giving by Method. Done 2026-04-22 (v99). New reusable `renderPieChart(items, diameter)` helper (SVG slices with hover tooltips + legend). Added "Share by Method" block above the existing table on the Giving by Method report.
- [x] **R10** — Average giving stats overlay. Done 2026-04-22 (v102). Giving by Fund overview now has 5 tiles (added "Avg / Giver" = total / distinct givers, relabeled "Average Gift" → "Avg / Gift"). "Avg / Giver" also appears per age-group row in the new R1 table. Giving Insights already had both avg stats in its 5-year trend table (from v99). Giving Trend chart stats deferred — the per-year tile total in its legend already serves the year-level averages context.

### Bugs (noted 2026-05-01)
- [x] **BUG1** — `normalizePhone()` throws on non-string input. Fixed 2026-05-19 (v218) via BF12.
- [ ] **BUG2** — "Validate Address" button on person profile gives an error; also needs a global bulk-validate mode (run across all people, not just one at a time). Trace error first, then add bulk option.

### Engagement & Data Quality (noted 2026-04-22)
- [x] **FU1** — Prayer request tracking. Done 2026-04-23 (v107/v108). API dispatch bug fixed (prayer-requests and engagement routes were missing from api-admin.js dispatch list — all status changes returned 404). Cancel guard bug fixed in prayerSetStatus. Dashboard card now has Praying/Answered/Close buttons (working), + Add modal, and "↓ CSV" export button (`GET /admin/api/prayer-requests/export.csv?status=all|open|praying|active|answered|closed`). Website contact and prayer forms wired end-to-end via service binding (timothystl/website) — submissions create person records and prayer_requests rows in this DB.
- [x] **WC1** — Electronic contact card intake. Done 2026-04-23. Website contact form → admin worker → service binding → `/api/intake/connect-card` creates Visitor + follow_up_items row. Website prayer form → `/api/intake/prayer` creates prayer_requests row. Both confirmed working end-to-end.

### Infrastructure / Backend Cleanup (noted 2026-04-22)
- [x] **IN1** — Worker renamed to `tlc-chms`. Done 2026-04-24 (Phase 3).
- [x] **IN2** — App merge strategy decided: Option C (absorb scheduler, leave website admin separate). No active work needed now. Done 2026-05-01.
- [x] **IN3** — Split `html-chms.js` into per-tab modules. Done 2026-04-25 (v120). `html-chms.js` reduced from 9,443 → 311 lines; 13 string-fragment modules in `src/frontend/` (`html-head.js`, `html-tabs.js`, `js-core.js`, `js-settings.js`, `js-dashboard.js`, `js-people.js`, `js-register.js`, `js-households.js`, `js-giving.js`, `js-reports.js`, `js-export-import.js`, `js-attendance.js`, `js-volunteers.js`). Shell assembles them; `CHMS_HTML` unchanged byte-for-byte.
- [x] **IN4** — Split `api-chms.js` into domain modules. Done 2026-04-24 (v114–v118). `api-chms.js` now 533 lines (was 5,151); domains in `api-people.js`, `api-giving.js`, `api-households.js`, `api-reports.js`, `api-import.js`, `api-utils.js`.
- [x] **IN5** — Extract Breeze API client into `src/breeze.js`. Done 2026-04-24 (v114). New `makeBreezeClient(env)` factory returns null when env vars missing; all 9 endpoints wrapped; raw `Response` objects returned so all caller error handling is unchanged. `subdomain` exposed on client for photo CDN URL construction. All 12 Breeze-calling handlers in `api-chms.js` updated; `filter_json` pre-encoding preserved.
- [x] **IN6** — Secrets inventory doc. Done 2026-04-24 — see `SECRETS.md`.
- [x] **IN7** — D1 schema migrations system. Done 2026-04-23. `migrations/` directory created with `0001_baseline.sql` (complete schema as of today). `wrangler.toml` updated with `migrations_dir = "migrations"`. **To add a new column going forward**: (1) create `migrations/NNNN_description.sql` with the `ALTER TABLE ADD COLUMN` statement, (2) also add the same statement to the `migrations` array in `src/db.js` with a try/catch (keeps cold-start safety net working), (3) run `wrangler d1 migrations apply tlc-volunteer-db --remote` to apply to prod.
- [x] **IN8** — Audit log retention / pruning. Done 2026-04-23. `pruneAuditLog(db)` added to `tlc-volunteer-worker.js`, called from the existing `0 14 * * *` daily cron. Retention: `birthday_email_sent` / `anniversary_email_sent` → 60 days; all other rows → 365 days. Logged under `audit_prune` in cron output.
- [x] **IN9** — Staging environment live at `https://breeze-proxy-worker-staging.timothystl.workers.dev/chms`. Separate `wrangler.staging.toml` config; D1: `tlc-volunteer-db-staging`, KV: staging RSVP_STORE, shared R2, crons disabled. Deploy: `wrangler deploy --config wrangler.staging.toml`. Done 2026-04-24.
- [x] **IN10** — D1 backup/restore runbook. Done 2026-04-24 — see `## D1 Backup & Restore` section in this file.
- [x] **IN11** — Test harness. Done 2026-04-25 (v121). Vitest; 37 tests in `test/`: `utils.test.js` (disambiguateHHName), `auth.test.js` (hashPassword/verifyPassword), `csv-import.test.js` (parseFundSplits/givingEntryId/isGivingDup). `npm test` passes.
- [x] **IN12** — Dead-code sweep. Done 2026-04-24 (v113). Removed debug `console.log('[Breeze Sync]…')` from per-person Breeze sync in `html-chms.js` and dead `setFdTag` function (comment said "keep for legacy callers" but no callers existed). Both `api-chms.js` and `html-chms.js` were otherwise clean — comments are explanatory, `console.error` calls are the intentional global error boundary.

---

## D1 Backup & Restore

### Recovery options

**Option 1 — Cloudflare Point-in-Time Recovery (PITR)**
Cloudflare retains D1 backups for ~30 days. This is the fastest path for recent accidental data loss.

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com) → Workers & Pages → D1 → `tlc-volunteer-db`
2. Click **Backups** tab → select a timestamp before the incident
3. Click **Restore** — this overwrites the live DB with the selected snapshot
4. Verify in the app (dashboard stats, spot-check a person record)

**Option 2 — Manual export via Wrangler (any-time snapshot)**
```bash
# Export the live DB to a local SQL file
wrangler d1 export tlc-volunteer-db --remote --output backup-$(date +%Y%m%d).sql

# Restore from that file to a fresh/existing DB
wrangler d1 execute tlc-volunteer-db --remote --file backup-20260424.sql
```

**Option 3 — Export to R2 for long-horizon retention (manual, monthly)**
```bash
# Export, then upload to the tlc-chms-photos bucket under a backups/ prefix
wrangler d1 export tlc-volunteer-db --remote --output /tmp/db-backup.sql
wrangler r2 object put tlc-chms-photos/backups/db-$(date +%Y%m%d).sql --file /tmp/db-backup.sql
```
R2 backups persist beyond the 30-day PITR window. Recommended before any risky migration or sync operation.

### Before any risky operation
Always export a snapshot before: running bulk giving sync, applying new migrations, or running Force Remove Orphans.

```bash
wrangler d1 export tlc-volunteer-db --remote --output pre-op-backup-$(date +%Y%m%d-%H%M).sql
```

---

## Code Review Standards

Before finalizing any code in this project, perform a structured five-pass review:

**Pass 1 — Logic & Bugs**
Check that every function does what its name says. Look for edge cases:
null/undefined values, empty inputs, unexpected data types, non-exhaustive
conditionals. Trace the logic path for failure scenarios, not just happy paths.

**Pass 2 — Privacy & Security**
Flag any exposed secrets, API keys, or credentials. Check that user input is
validated before use. Ensure personal data (names, contact info, financial
records) is handled with intentional access control. Never log sensitive data.

**Pass 3 — Performance**
Identify loops inside loops, unnecessary re-renders, unthrottled/undebounced
event handlers, synchronous operations that should be async, and repeated
data fetches that could be cached or combined.

**Pass 4 — Efficiency & Clarity**
Remove redundant variables and duplicate logic. Extract repeated patterns into
helper functions. Simplify overly complex conditionals. Code should read like
clear prose — if a line requires re-reading, rewrite it.

**Pass 5 — Dead Code & Cleanup**
Remove commented-out code, unused imports, leftover console.log statements,
and completed TODO comments. Leave no debugging artifacts in production code.

After each session, summarize what changed and why — treat this as a commit
message for future reference.

---

## Daily Code Review Checklist

Run through this at the end of any session before pushing, or at the start of a session when picking up from someone else.

### Security
- [ ] Every new API endpoint checks role (`isAdmin`, `isFinance`, `isStaff`, `canEdit`) before doing anything
- [ ] No raw user input passed into SQL — always use `.bind()` parameterized queries
- [ ] HTML output always runs through `esc()` — never concatenate raw user data into innerHTML
- [ ] No secrets or API keys hardcoded — all from `env.*` (Cloudflare secrets)
- [ ] New endpoints that touch giving data are gated behind `isFinance`

### Cloudflare Worker Limits
- [ ] No single DB query uses more than ~90 parameters in an IN/NOT IN — chunk if needed
- [ ] Any loop that does per-row DB queries is replaced with a bulk SELECT + JS grouping (avoid 30s timeouts)
- [ ] Large import/sync operations return early with `done: true` and let the frontend re-trigger if needed

### API Correctness
- [ ] New endpoints return `json({ error: '...' }, 4xx)` on bad input, not a 200 with an error field
- [ ] All new endpoints are wrapped in try/catch so uncaught exceptions return JSON, not Cloudflare's HTML error page
- [ ] New routes added to the correct file (`api-chms.js` for ChMS data, `api-admin.js` for auth/users/scheduler)

### Frontend Consistency
- [ ] New API calls use `api('/admin/api/...')` wrapper, not raw `fetch()`
- [ ] New modals have a unique ID and use `openModal(id)` / `closeModal(id)`
- [ ] `DEPLOY_VERSION` bumped in `src/frontend/js-core.js` on every commit that changes the frontend
- [ ] New tabs added to `showTab()` labels map and trigger their load function

### Data Integrity
- [ ] Any query returning a household name uses COALESCE fallback for `head_first_name` (not all members have `family_role='head'`)
- [ ] Giving amounts stored and retrieved as **integer cents**, converted to dollars only at display time (`/ 100`)
- [ ] New person/household fields default to `''` (empty string) not NULL where possible — avoids COALESCE boilerplate everywhere

### Before Every Push
- [ ] `DEPLOY_VERSION` is bumped
- [ ] `NOTES.md` Recent Changes has an entry for this version
- [ ] `CLAUDE.md` Queued Items updated — new items added, completed items checked off
- [ ] Pushed to the current session branch (per-session `claude/*` branch), not main

---

## Gotchas & Patterns

- **NEVER run `wrangler deploy` from a local terminal.** The GitHub Actions workflow (`deploy.yml`) deploys automatically when any PR merges to `main`. Running wrangler locally risks deploying stale code from the wrong folder and overwriting the correct production version. If a deploy looks wrong, re-run the Action from GitHub → Actions tab instead.
- **Local `~/Desktop/volunteer` folder is the old repo clone** — remote was originally `timothystl/volunteer`, renamed to `timothystl/chms`. If ever needed: `git remote set-url origin https://github.com/timothystl/chms.git`. But prefer GitHub Actions over local deploys entirely.
- `disambiguateHHName(name, headFirst)` — shared helper at top of `api-chms.js`. Always use COALESCE fallback in `head_first_name` subqueries (not all members have `family_role='head'`).
- **Breeze giving CSV format quirks**: (1) Split-fund donations appear as multiple rows with the same Payment ID (one row per fund). The importer handles this with nth-occurrence tracking (`pid`, `pid-2`, `pid-3`). (2) Sub-fund names like "40085 Christmas Offering" are stored as separate fund records — they are NOT rolled into "40085 General Fund". The Giving by Fund report groups them by numeric prefix. (3) Negative entries are valid (refunds/adjustments) and are imported. (4) "nan" fund name = blank field from Excel export → maps to General Fund. (5) Person IDs may have `.0` float suffix — stripped on import.
- **Anniversary secondary lookup**: only requires `active=1` and non-deceased — does NOT filter by `family_role` or `member_type`, since the qualifying person already passed those checks and their partner may be a visitor or have no role set.
- Dashboard birthday/anniversary: two separate cards since v23. Copy functions: `dashCopyBirthdays()` / `dashCopyAnniversaries()`. Anniversary rows are couple-paired by household+date in the API before returning.
- `api()` helper in frontend handles 401→redirect. Always use it instead of raw `fetch` for `/admin/api/*` calls.
- All modals have specific IDs (e.g. `person-modal`, `hh-modal`). There is no generic `modal-overlay`. Use `openModal(id)` / `closeModal(id)`.
- DEPLOY_VERSION is at the top of `src/frontend/js-core.js` (moved from `html-chms.js` after IN3 split). Bump it on every commit that changes the frontend.
- **Editing volunteer.timothystl.org**: do NOT search/edit `src/html-templates.js` for ministry copy — the public page is assembled from `src/public/` modules. To tweak a ministry, edit `src/public/ministries/<name>.js` directly. Global CSS lives in `src/public/head.js`; all JS (form handlers, routing) in `src/public/scripts.js`.
- **Brand tokens** (TLC Gather): `--color-navy:#1E2D4A`, `--color-teal:#2E7EA6`, `--color-gold:#C9973A`, `--color-cream:#F8F4EE`. Fonts: Cormorant Garamond (display) + DM Sans (head/body). Three-pillar pill system in topbar driven by `pillars` map in `js-core.js` `showTab()`.
- **member_type** is stored lowercased. Both Breeze write paths (per-person at line ~2442, bulk at line ~2777 of `api-import.js`) call `.toLowerCase()` before binding; a defensive `UPDATE … SET member_type=LOWER(member_type)` runs at end of each sync batch as a safety net. Frontend filters use `LOWER()` comparison.

---

## GitHub Repo

**Repo**: `timothystl/chms` (renamed from `timothystl/volunteer` 2026-04-25 — Worker is `tlc-chms`, D1 is `tlc-volunteer-db`)

## Dev Branch

Create a new branch for each session's work (pattern: `claude/<short-task>-<id>`). Do not push directly to main. Open a draft PR after pushing; GitHub Actions deploys on merge.
