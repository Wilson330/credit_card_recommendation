# CreditCardRewardLogic (Swift port)

This is a **from-scratch Swift port** of this repo's Flutter/Dart reward-calculation
logic (`lib/models`, `lib/services`), written by Claude by translating the tested Dart
implementation. **It has never been compiled or run** — there is no Swift/Xcode toolchain
available in the environment that produced it. Treat it as a careful first draft that
needs to actually build in Xcode before anyone trusts it. See `HANDOFF_PROMPT.md` for a
prompt to hand to an AI agent (or read yourself) that explains the full context and asks
it to get this compiling and passing its tests.

## What this is (and isn't)

- **Is**: the reward-calculation *logic* and *data* — merchant matching, category rules,
  conditional eligibility, the top-3 ranking — as a self-contained Swift Package with no
  UI of its own.
- **Isn't**: a replacement for `ContentView.swift`. That UI stays as-is; this package is
  meant to be called FROM it, replacing the `performSearch()` function's network call to
  `app.py`/MySQL with a local, on-device computation.
- **Isn't** a MySQL client. This reads three bundled JSON files (see `Sources/CreditCardRewardLogic/Resources/`)
  entirely on-device — no network call, no backend server, works offline. That was a
  deliberate decision for this testing phase (see HANDOFF_PROMPT.md's "why JSON not MySQL"
  section) — MySQL can come back later once there's an actual reason to need a server
  (e.g. the admin merchant-curation workflow, user accounts).

## Structure

```
swift_port/
  Package.swift
  Sources/CreditCardRewardLogic/
    Models/             CardRewardRule, Merchant, MerchantQueryContext, RewardEvaluationResult
    Services/           MerchantMatcher, RuleMatcher, MerchantResolver,
                         RewardRulesRepository, MerchantRepository
    Evaluators/          CubeRewardEvaluator, JihoRewardEvaluator, RecommendationOrchestrator
    Resources/           cube_reward_rules.json, jiho_reward_rules.json, merchants.json
                         (copies — regenerate from the main repo's scripts/ and re-copy
                         here whenever the data changes, see "Keeping data in sync" below)
  Tests/CreditCardRewardLogicTests/
    RuleMatcherTests, MerchantResolverTests, EvaluatorTests
```

Every source file has a doc comment pointing at the Dart file it was ported from — if
anything here looks wrong, that Dart file plus its test file is the tie-breaker for what
the *intended* behavior is, since that side has actually been run and tested.

## Integration options

**Option A — local Swift Package dependency (recommended):** In Xcode, File → Add Package
Dependencies → Add Local... → select this `swift_port` folder. Then `import CreditCardRewardLogic`
in `ContentView.swift`. Cleanest option — no files to copy/merge into the existing project,
and you get the bundled JSON resources automatically.

**Option B — copy the source files directly:** if you'd rather not add a package
dependency, you can copy everything under `Sources/CreditCardRewardLogic/` straight into
the Xcode project. If you do this, the JSON files need to be added to the app target
with "Copy Bundle Resources" checked, and every `Bundle.module` reference in
`RewardRulesRepository.swift`/`MerchantRepository.swift` needs to change to `Bundle.main`
(or whatever bundle the JSON files actually end up in) — `Bundle.module` is specifically
an SPM mechanism and only works when this stays a package.

## Wiring into `ContentView.swift`

1. At app launch (e.g. your `App`'s `init()`, or a `.task` on the root view), call:
   ```swift
   try? RewardRulesRepository.shared.load()
   try? MerchantRepository.shared.load()
   ```
   Both are idempotent and synchronous (no network, just reading bundled JSON) — safe
   to call more than once, no `await` needed.

2. Replace `performSearch()`'s network call with:
   ```swift
   private func performSearch() {
       guard !searchStoreText.isEmpty else { return }

       var userCards: [UserCardInput] = []
       if hasCubeCard {
           userCards.append(.cube(CubeCardInput(
               level: cubeLevel.replacingOccurrences(of: "Level ", with: "level_"),
               isNewCardHolder: false, // CUBE has no new-customer flag in this app's UI
               hasKidsClub: hasKidsClub
           )))
       }
       if hasJihoCard {
           userCards.append(.jiho(JihoCardInput(isNewCardHolder: isJihoNewUser)))
       }
       // hasUnicard / hasCTBC: no data yet — see "What's NOT ported" below.

       let results = RecommendationOrchestrator.evaluate(
           merchantName: searchStoreText,
           userCards: userCards
       )

       searchResults = results.compactMap { result in
           let info = getCardInfo(name: result.cardName)
           return MockCard(
               bankName: info.bank,
               cardName: result.cardName,
               baseRate: 0.0,
               rewardRate: result.rewardRate,
               imageUrl: info.image,
               cardLevel: nil,   // RewardEvaluationResult doesn't carry this back —
                                 // add a `level` field to it if the UI needs to show it
               schemeName: result.matchedTags.first
           )
       }
   }
   ```
   **Important gotcha**: your `cubeLevel` `@AppStorage` stores `"Level 1"` / `"Level 2"` /
   `"Level 3"` (see `AddCardSheetView`), but the bundled data uses `"level_1"` / `"level_2"` /
   `"level_3"` (snake_case). The `.replacingOccurrences` above is a quick fix — a small
   dedicated mapping function would be more robust if the picker labels ever change.

3. `isSearching`/`ProgressView` can go away — this is synchronous and local now, no
   loading state needed (though you could keep the UI structure and just always resolve
   instantly if you'd rather not restructure that part yet).

## What's NOT ported (and why)

- **Unicard (玉山銀行) / 商旅鈦金卡 (中國信託)**: `ContentView.swift` already has UI for these,
  left as-is per 2026-08-06 decision — but there's no crawled reward data or evaluator
  for either card yet. `RecommendationOrchestrator` will simply produce no result for a
  card with no matching case in `UserCardInput`, the same "skip, don't crash" behavior the
  Dart reference implementation has for an unregistered card. Add a data file + evaluator
  + `UserCardInput` case for each once real data exists.
- **User accounts** (`/api/register`, `/api/login`): out of scope for this pass — no
  ported equivalent, no UI change needed since ContentView.swift doesn't currently gate
  anything behind login either.
- **The Japan-specific new-customer/payment-method jiho rows** (e.g. "新戶日本實體消費(行動支付)"):
  still unreachable — they need to know payment method and whether the transaction is
  physically in Japan, and no UI (ours, or `ContentView.swift`) collects that at search
  time. See `SCHEMA.md`'s `is_synthetic_condition` notes in the main repo.
- **慶生月** (birthday-month CUBE scheme): deferred — its gate is "is it currently the
  cardholder's birthday month," a time-based condition, not a static profile flag.

## Keeping data in sync

The three JSON files under `Resources/` are **copies**, not symlinks (Swift Packages can't
reliably bundle files outside their own directory tree). Whenever `scripts/convert_allen_rewards.js`
or `scripts/build_merchants.js` regenerate the main repo's `lib/data/*.json`, re-copy the
three files into `swift_port/Sources/CreditCardRewardLogic/Resources/` to keep this port
current. There's no build step wiring this up automatically (yet) — a small script to do
that copy is a reasonable follow-up if this becomes a recurring chore.

## Running the tests

`swift test` from this directory, or Product → Test in Xcode after opening `Package.swift`.
These are a faithful port of the Dart test suite (`test/rule_matcher_test.dart`,
`test/merchant_resolver_test.dart`, `test/evaluators_test.dart`) — if they don't compile
or don't pass, something was lost in translation and should be fixed against the Dart
original + its tests as the source of truth, not by guessing.
