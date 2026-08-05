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

// Deferred per user decision 2026-07-30 (round 2): skip these schemes for v1.
const CUBE_DEFERRED_SCHEMES = new Set(['慶生月', '童樂匯']);

// Confirmed with Allen 2026-08-06: every remaining CUBE scheme (台塑家/
// 全支付 included) requires switching to that benefit program — there is
// no non-switchable scheme left, so required_action is unconditional now.

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
        constraints,
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
const JIHO_CONDITION_SCHEMES = new Set([
  '國內一般消費',
  '國外一般消費',
  '日本一般消費',
  '日本交通卡儲值',
]);

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
        const { name, bracketNote } = normalizeMerchantName(rawName);
        const constraints = [GENERIC_CONSTRAINT];
        if (bracketNote) constraints.push(bracketNote);
        if (isCondition) {
          constraints.push('此列為使用情境代稱（非真實商家），為 v1 暫時性簡化，待重構為條件式規則');
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
