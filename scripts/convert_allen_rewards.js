// Converts lib/data/allen/*.json (raw crawled reward data) into
// SCHEMA.md-conformant lib/data/{cube,jiho}_reward_rules.json.
// Re-run this whenever Allen supplies a new crawl export.
//
// Usage: node scripts/convert_allen_rewards.js

const fs = require('fs');
const path = require('path');

const DATA_DIR = path.join(__dirname, '..', 'lib', 'data');
const ALLEN_DIR = path.join(DATA_DIR, 'allen');

const GENERIC_CONSTRAINT = '實際回饋依當期公告為準';

// Keywords that indicate a trailing "(...)" is a genuine constraint/qualifier
// rather than part of the merchant's identity (e.g. "(日本)" on "7-ELEVEN(日本)"
// disambiguates *which* 7-ELEVEN, it is not a constraint — must stay in the name).
const CONSTRAINT_BRACKET_KEYWORDS = [
  '限', '不含', '僅', '需', '限定', '週', '街邊店', '儲值', '電子票券', '結帳',
];

function normalizeMerchantName(raw) {
  const match = raw.trim().match(/^(.*?)\s*[\(（](.+?)[\)）]\s*$/);
  if (match) {
    const bracketContent = match[2].trim();
    const looksLikeConstraint = CONSTRAINT_BRACKET_KEYWORDS.some((kw) =>
      bracketContent.includes(kw)
    );
    if (looksLikeConstraint) {
      return { name: match[1].trim(), bracketNote: bracketContent };
    }
  }
  return { name: raw.trim(), bracketNote: null };
}

function buildRuleId(cardId, scheme, name, level) {
  const slug = (s) =>
    s
      .toString()
      .toLowerCase()
      .replace(/[^a-z0-9一-鿿]+/g, '_')
      .replace(/^_+|_+$/g, '');
  return [cardId, slug(scheme), slug(name), level ? slug(level) : null]
    .filter(Boolean)
    .join('_')
    .slice(0, 120);
}

// ---------- CUBE ----------

const CUBE_LEVEL_MAP = {
  'Level 1': 'level_1',
  'Level 2': 'level_2',
  'Level 3': 'level_3',
};

// 慶生月 stays deferred — its real gate is "is it currently the cardholder's
// birthday month," a time-based condition our required_conditions design
// (a static Set<String> of flags on a card's profile) can't express, unlike
// 童樂匯 below. 童樂匯 un-deferred 2026-08-06 once required_conditions
// existed to model its real gate (see CUBE_CONDITION_SCHEMES).
const CUBE_DEFERRED_SCHEMES = new Set(['慶生月']);

// Schemes gated behind a boolean flag on the card's profile, checked via
// required_conditions rather than being always eligible. 童樂匯 requires
// the "童樂匯" add-on to be active on the card — modeled as a new
// CubeCardProfile.hasKidsClub flag (see lib/models/card_profiles/cube_card_profile.dart).
const CUBE_CONDITION_SCHEMES = {
  童樂匯: ['kids_club'],
};

// Confirmed with Allen 2026-08-06: every remaining CUBE scheme except
// 童樂匯 (台塑家/全支付 included) requires switching to that benefit
// program. 童樂匯's required_action is an unconfirmed assumption, same
// pattern as 台塑家/全支付 were before they got confirmed.

function convertCube() {
  const raw = JSON.parse(
    fs.readFileSync(path.join(ALLEN_DIR, 'cube_ALL_LEVELS_rewards.json'), 'utf8')
  );

  // Pass 1: collect each (scheme, merchant)'s rate per level, since whether
  // a rule needs one row (rate constant across levels) or three (rate
  // varies) can only be known after seeing all three levels — deciding
  // this from which scheme it is (as an earlier version of this script did)
  // was wrong: 台塑家/全支付 are switchable but level-invariant, so tying
  // the two together produced duplicate rows with no actual difference.
  const byKey = new Map();

  for (const [rawLevel, schemes] of Object.entries(raw)) {
    const level = CUBE_LEVEL_MAP[rawLevel];
    if (!level) {
      console.warn(`[cube] unknown level key "${rawLevel}", skipping`);
      continue;
    }

    for (const [scheme, merchants] of Object.entries(schemes)) {
      if (CUBE_DEFERRED_SCHEMES.has(scheme)) continue;

      for (const [rawName, rate] of Object.entries(merchants)) {
        const { name, bracketNote } = normalizeMerchantName(rawName);
        const key = `${scheme}|||${name}`;
        if (!byKey.has(key)) {
          byKey.set(key, { scheme, name, bracketNote, ratesByLevel: {} });
        }
        byKey.get(key).ratesByLevel[level] = rate;
      }
    }
  }

  // Pass 2: emit one row if the rate is constant across levels, three rows
  // (one per level) if it actually varies.
  const rules = [];

  for (const { scheme, name, bracketNote, ratesByLevel } of byKey.values()) {
    const constraints = [GENERIC_CONSTRAINT];
    if (bracketNote) constraints.push(bracketNote);

    const requiredConditions = CUBE_CONDITION_SCHEMES[scheme] || [];
    if (requiredConditions.length > 0) {
      constraints.push(
        `此方案是否需另行申請/切換，required_action 為假設值，尚未與官網條款或 Allen 確認`
      );
    }

    const distinctRates = new Set(Object.values(ratesByLevel));
    const isLevelVariant = distinctRates.size > 1;
    const requiredAction = `需切換至${scheme}權益方案`;

    if (isLevelVariant) {
      for (const [level, rate] of Object.entries(ratesByLevel)) {
        rules.push({
          rule_id: buildRuleId('cube', scheme, name, level),
          card_id: 'cathay_cube',
          rule_type: 'merchant',
          match_value: name,
          applicable_level: level,
          reward_rate: rate,
          benefit_label: scheme,
          required_action: requiredAction,
          required_conditions: requiredConditions,
          constraints,
          is_synthetic_condition: false,
          active: true,
        });
      }
    } else {
      rules.push({
        rule_id: buildRuleId('cube', scheme, name, null),
        card_id: 'cathay_cube',
        rule_type: 'merchant',
        match_value: name,
        applicable_level: null,
        reward_rate: Object.values(ratesByLevel)[0],
        benefit_label: scheme,
        required_action: requiredAction,
        required_conditions: requiredConditions,
        constraints,
        is_synthetic_condition: false,
        active: true,
      });
    }
  }

  // Not derived from Allen's crawl — these two category-type rules encode
  // a broad clause Allen confirmed 2026-08-06 by hand: 樂饗購 also covers
  // any domestic restaurant (not just the ~44 named merchants above), and
  // 趣旅行 also covers any domestic hotel (not just the named hotel
  // brands). The rate at each level is inferred, not separately
  // confirmed — but every named merchant under a given (scheme, level)
  // in the raw data shares exactly one rate (verified: Level 1 = 2.0,
  // Level 2 = 3.0, Level 3 = 3.3 for both schemes, no variation), so
  // assuming the broad clause pays the same as the named list is a safe
  // inference, not a guess pulled from nowhere.
  // match_value must be an actual tag string from merchants.json's
  // tags[] (see scripts/build_merchants.js's DINING()/HOTEL() helpers),
  // not a primary_category value — RuleMatcher checks tags.contains(),
  // not primary_category equality.
  const CATEGORY_RULES = [
    { scheme: '樂饗購', tag: 'restaurant', rates: { level_1: 2.0, level_2: 3.0, level_3: 3.3 } },
    { scheme: '趣旅行', tag: 'lodging', rates: { level_1: 2.0, level_2: 3.0, level_3: 3.3 } },
  ];
  for (const { scheme, tag, rates } of CATEGORY_RULES) {
    for (const [level, rate] of Object.entries(rates)) {
      rules.push({
        rule_id: buildRuleId('cube', scheme, `category_${tag}`, level),
        card_id: 'cathay_cube',
        rule_type: 'category',
        match_value: tag,
        applicable_level: level,
        reward_rate: rate,
        benefit_label: scheme,
        required_action: `需切換至${scheme}權益方案`,
        required_conditions: [],
        constraints: [
          GENERIC_CONSTRAINT,
          '廣義分類條款，已於 2026-08-06 與 Allen 確認存在，適用費率為推論值（比照同方案具名商家費率）',
        ],
        is_synthetic_condition: false,
        active: true,
      });
    }
  }

  rules.push({
    rule_id: 'cube_default',
    card_id: 'cathay_cube',
    rule_type: 'default',
    match_value: '*',
    required_conditions: [],
    applicable_level: null,
    reward_rate: 0.3,
    benefit_label: '一般消費',
    required_action: null,
    constraints: [
      GENERIC_CONSTRAINT,
      '一般消費基礎回饋率 0.3%，已於 2026-08-06 與 Allen 確認',
    ],
    is_synthetic_condition: false,
    active: true,
  });

  return rules;
}

// ---------- JIHO ----------

// Schemes whose entries are genuinely named merchants.
const JIHO_MERCHANT_SCHEMES = new Set(['國內日系特店加碼', '國內日系餐廳優惠', '日本熱門商店']);

// Schemes whose "merchant_name" is actually a condition label (new customer /
// payment method / currency), not a real merchant. Per user decision
// 2026-07-30 (round 2): "先跑通就好" — keep as pseudo-merchant rows for v1,
// flagged with is_synthetic_condition so this compromise stays visible.
//
// 2026-08-06: one row escapes that fate — "新戶自動扣繳加碼(國內一般消費)"
// is a pure customer-eligibility bump (JihoCardProfile.isNewCardHolder
// already exists), so it's modeled properly below as a conditioned
// default rule instead of a pseudo-merchant. The rest of these rows stay
// is_synthetic_condition because they also depend on payment method or
// being physically in Japan — inputs no search bar (ours or Allen's UI)
// currently collects, so they'd stay unreachable even with
// required_conditions modeling. Not solved today, just now precisely
// scoped to what's actually still missing (an input, not a rule format).
const JIHO_CONDITION_SCHEMES = new Set([
  '國內一般消費',
  '國外一般消費',
  '日本一般消費',
  '日本交通卡儲值',
]);

// raw crawled name -> required_conditions, handled as a conditioned
// default rule (rule_type: 'default', match_value: '*') rather than a
// pseudo-merchant row.
const JIHO_CONDITION_TO_REQUIRED_CONDITIONS = {
  '新戶自動扣繳加碼(國內一般消費)': ['new_customer'],
};

function convertJiho() {
  const raw = JSON.parse(fs.readFileSync(path.join(ALLEN_DIR, 'jiho_rewards.json'), 'utf8'));

  const rules = [];

  for (const [level, schemes] of Object.entries(raw)) {
    // jiho only has "Standard" in the raw data; not level-dependent like CUBE.
    for (const [scheme, merchants] of Object.entries(schemes)) {
      const isCondition = JIHO_CONDITION_SCHEMES.has(scheme);
      if (!isCondition && !JIHO_MERCHANT_SCHEMES.has(scheme)) {
        console.warn(`[jiho] unclassified scheme "${scheme}", treating as merchant rules`);
      }

      for (const [rawName, rate] of Object.entries(merchants)) {
        const requiredConditions = JIHO_CONDITION_TO_REQUIRED_CONDITIONS[rawName];

        if (requiredConditions) {
          rules.push({
            rule_id: buildRuleId('jiho', scheme, rawName, null),
            card_id: 'ubot_jiho',
            rule_type: 'default',
            match_value: '*',
            applicable_level: null,
            reward_rate: rate,
            benefit_label: scheme,
            required_action: null,
            required_conditions: requiredConditions,
            constraints: [GENERIC_CONSTRAINT],
            is_synthetic_condition: false,
            active: true,
          });
          continue;
        }

        const { name, bracketNote } = normalizeMerchantName(rawName);
        const constraints = [GENERIC_CONSTRAINT];
        if (bracketNote) constraints.push(bracketNote);
        if (isCondition) {
          constraints.push('此列為使用情境代稱（非真實商家），待補上情境所需的輸入（例如支付方式、所在國家）才能真正判斷');
        }

        rules.push({
          rule_id: buildRuleId('jiho', scheme, name, null),
          card_id: 'ubot_jiho',
          rule_type: 'merchant',
          match_value: name,
          applicable_level: null,
          reward_rate: rate,
          benefit_label: scheme,
          required_action: null,
          required_conditions: [],
          constraints,
          is_synthetic_condition: isCondition,
          active: true,
        });
      }
    }
  }

  rules.push({
    rule_id: 'jiho_default',
    card_id: 'ubot_jiho',
    rule_type: 'default',
    match_value: '*',
    applicable_level: null,
    reward_rate: 1.0,
    benefit_label: '國內一般消費',
    required_action: null,
    required_conditions: [],
    constraints: [GENERIC_CONSTRAINT],
    is_synthetic_condition: false,
    active: true,
  });

  return rules;
}

// ---------- run ----------

const cubeRules = convertCube();
const jihoRules = convertJiho();

fs.writeFileSync(
  path.join(DATA_DIR, 'cube_reward_rules.json'),
  JSON.stringify(cubeRules, null, 2) + '\n',
  'utf8'
);
fs.writeFileSync(
  path.join(DATA_DIR, 'jiho_reward_rules.json'),
  JSON.stringify(jihoRules, null, 2) + '\n',
  'utf8'
);

console.log(`cube_reward_rules.json: ${cubeRules.length} rules`);
console.log(`jiho_reward_rules.json: ${jihoRules.length} rules`);
