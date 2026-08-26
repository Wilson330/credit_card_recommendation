# Handoff prompt for Allen's AI agent

Copy everything below the line into a prompt for whatever AI coding agent Allen is using
on his Mac. It's written to stand alone — the agent reading it hasn't seen this
conversation and has only `app.py`, `ContentView.swift`, and whatever else lives in
Allen's project.

---

## Context

Two people are building one iOS app together. Allen built a SwiftUI UI (`ContentView.swift`)
and a Flask + MySQL backend (`app.py`) that searches a `card_rewards` table. His teammate
(Wilson) independently built out the actual reward-recommendation *logic* and *data* in a
Flutter/Dart prototype, with a much richer data model than the flat MySQL table `app.py`
queries. For this next test build, the two sides are merging: Wilson's Dart logic has been
hand-ported to a Swift Package called `CreditCardRewardLogic` (in the `swift_port/` folder
delivered alongside this prompt), meant to be dropped into Allen's Xcode project and called
directly from `ContentView.swift`, replacing `performSearch()`'s HTTP call to
`app.py`/MySQL.

**This port was written by an AI (Claude) with no Swift toolchain available to compile or
run it.** It's a careful line-by-line translation of a Dart implementation that IS fully
tested (47+ passing tests), but the Swift side itself has never been built. Getting it to
compile, fixing whatever's wrong, and running its test suite is exactly the kind of task
this handoff is asking Allen's agent to help with.

## Is this "backend" or "frontend"?

Neither, really — it's an **on-device business-logic layer**, bundled into the same app
binary as the UI, with no server process and no network call. Concretely:

- It's not "frontend" in the sense of `ContentView.swift` — it has no views, no `@State`,
  nothing SwiftUI-specific. It's plain Swift structs/enums/functions that take a merchant
  name + which cards the user holds, and return reward rates.
- It's not "backend" in the sense of `app.py` — there's no server, no port to listen on,
  no client/server boundary at all. It reads three JSON files bundled inside the app and
  computes locally, synchronously, offline.

Practically: think of it as replacing the *body* of `performSearch()` (currently an HTTP
call out to Flask) with a local function call. The `/api/search_rewards` endpoint and the
whole Flask/MySQL stack become unnecessary for this feature once this is wired in — MySQL
would only still be useful for `app.py`'s user-account endpoints (`/api/register`,
`/api/login`), which are out of scope for this iteration and haven't been touched.

**Why Swift and not Python**: Python can't run natively inside a shipped iOS app (no
interpreter in the App Store binary, no reasonable embedding story for this kind of
feature). The logic has to live in a language that compiles into the iOS binary — Swift is
the only realistic choice here, not a stylistic preference.

## Why JSON instead of MySQL, for now

Wilson's data model is intentionally richer than `app.py`'s flat `card_rewards` table
(`bank_name, card_name, card_level, scheme_name, merchant_name, reward_rate`). It has three
separate concerns:

1. **`merchants.json`** — a merchant directory independent of any card (canonical name,
   aliases, category tags like `restaurant`/`chain_store`, etc.) — ~300 Taiwan merchants
   right now.
2. **`cube_reward_rules.json` / `jiho_reward_rules.json`** — one JSON file per card, each
   row is a rule: `rule_type` (`merchant` | `category` | `default`), a `match_value`, a
   `reward_rate`, optional `applicable_level` (CUBE's rate can depend on which of 3 levels
   the card is switched to), and `required_conditions` (see below).
3. The matching logic itself: two-tier merchant-name matching, category-tag fallback via
   the merchant directory, then a default rate — see "Core logic" below.

Re-modeling all of that as MySQL tables/joins is real work with a lot of judgment calls
(normalize merchants into their own table? how to represent `required_conditions`? keep
`applicable_level` as a column or a separate table?). Rather than guess at that redesign
blind, the decision was to ship this test build against the same JSON files the Dart app
already uses — bundled read-only inside the iOS app, no server needed — and defer the
MySQL schema design to a follow-up once there's a concrete reason to need a real backend
(e.g., wanting to update reward rules without shipping an app update, or bringing back user
accounts). When that day comes, `MerchantRepository`/`RewardRulesRepository` in this Swift
package are the two places to swap from "load bundled JSON" to "fetch from an API backed
by MySQL" — the `Merchant`/`CardRewardRule` structs are exactly the shape the eventual
MySQL rows should preserve, since the matching logic depends on those fields.

## Core logic to know about

- **Rule lookup order**: for a given card + search query, check `merchant`-type rules
  first, then `category`-type rules, then `default`-type rules. Within a tier, highest
  `reward_rate` wins ties.
- **Merchant-name matching is two-tier**: tier 1 is exact match on the normalized name
  (lowercased, whitespace stripped) and always wins if found. Tier 2 is a conservative
  substring match (either side contains the other, minimum 2 characters) used only when no
  exact match exists — this exists so "全家" finds a rule written as "全家便利商店 實體門市"
  without a giant synonym table, but a exact match like "全家" itself is never displaced by
  some unrelated higher-rate rule like "全家福超市" that happens to substring-match.
- **Merchant aliases feed matching two ways**, and this distinction is exactly the bug we
  had to fix once, so it's worth being careful about it: (a) an alias resolves to a
  merchant's category tags for `category`-type rules, AND (b) resolves to the merchant's
  canonical name, which is ALSO checked (alongside the raw search text) against
  `merchant`-type rules' exact/substring match. Missing (b) means a real per-merchant rate
  (e.g. 7-11's actual card rate) silently gets skipped in favor of a worse default whenever
  the user searches by an alias instead of the exact name on file.
- **`required_conditions`**: a rule only qualifies if every string in its
  `required_conditions` array is present in the caller-supplied "active conditions" set for
  that search (e.g. `"kids_club"`, `"new_customer"`). This is how conditional promos work
  (a 童樂匯 family-theme-park bonus only applies if the user has told the app they belong to
  that program) without needing pseudo-merchant hacks. A card's evaluator is responsible
  for building this set from whatever profile flags the UI collects for that card (e.g.
  CUBE's "has kids club" toggle, jiho's "new cardholder" toggle) — see
  `CubeRewardEvaluator.swift`/`JihoRewardEvaluator.swift` in the port.
- **`applicable_level`**: some CUBE rules only apply at a specific membership level
  (`level_1`/`level_2`/`level_3`); a rule with `applicable_level: null` applies at any
  level. Whether a given (scheme, merchant) pair actually varies by level had to be
  determined empirically from Allen's crawled data, not assumed — don't assume a new
  scheme is level-invariant just because a similar-sounding one is.

## Known gaps in this pass (not bugs — deliberately out of scope)

- **Unicard / 商旅鈦金卡**: `ContentView.swift`'s UI already has entries for these two
  cards, left untouched — but there's no crawled reward data or Swift evaluator for either
  yet. The ported `RecommendationOrchestrator` simply won't produce a result for a card it
  has no data for, same "skip silently" behavior the Dart app has for any unregistered
  card type. This is real, needed follow-up work whenever that data becomes available —
  not something to paper over with fake numbers.
- **User accounts** (`/api/register`, `/api/login`): shelved for this pass. No Swift
  equivalent was ported; `ContentView.swift` doesn't currently gate anything behind login
  either, so nothing needs to change there yet.
- **Time-of-year and payment-method/location-conditioned promos** (CUBE's 慶生月
  birthday-month bonus; jiho's Japan-specific payment-method rows): still unreachable in
  both the Dart original and this port, since no UI collects the needed input (current
  date vs. cardholder birthday; payment method; whether the transaction is physically in
  Japan) at search time. Not a porting gap — genuinely not implemented anywhere yet.

## What this handoff is asking for

1. **Get `swift_port/` building** inside Allen's Xcode project — see `swift_port/README.md`
   for the two integration options (local SPM package dependency, or copying source files
   directly) and exactly what needs to change in `ContentView.swift`'s `performSearch()`.
   Expect real compile errors — this was never built before, only reasoned through by
   analogy with the tested Dart code.
2. **Run `swift test`** (or Xcode's Test navigator) on the ported test suite in
   `swift_port/Tests/` and get it green. If a test's *expectation* looks wrong rather than
   the *code*, the Dart original (`test/rule_matcher_test.dart`,
   `test/merchant_resolver_test.dart`, `test/evaluators_test.dart`, all in the main repo,
   not included in this folder) is the source of truth for intended behavior — check there
   before changing an assertion.
3. Once it builds and wires into `ContentView.swift`, do a manual pass in the simulator:
   search a known merchant per card (see `swift_port/README.md`'s test cases for known
   good/bad examples), toggle the CUBE 童樂匯 and jiho new-customer switches and confirm
   the rate changes, and try an unknown merchant name to confirm the default rate path
   works.
4. **Do not remove or weaken the MySQL password handling as a side effect of this work** —
   `app.py`'s `DB_CONFIG` currently has a plaintext password committed in a way that got
   shared outside the usual channels; that's a separate cleanup (rotate the credential,
   move it to an environment variable / secrets manager) that should happen regardless of
   this integration, but isn't part of this specific task.

Ping Wilson with anything that looks like a genuine logic disagreement rather than a
translation bug — the Dart side is the one that's actually been tested against real data,
so a mismatch is more likely a porting mistake than an intentional Swift-side design
choice, but it's worth confirming rather than assuming either way.
