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

// Schemes confirmed by the user as switchable benefit programs (require an
// explicit "switch to this program" action). Everything else in the raw
// data is an assumption flagged in SCHEMA.md, not a confirmed fact.
const CUBE_SWITCHABLE_SCHEMES = new Set(['樂饗購', '玩數位', '趣旅行', '集精選']);

// Deferred per user decision 2026-07-30 (round 2): skip these schemes for v1.
const CUBE_DEFERRED_SCHEMES = new Set(['慶生月', '童樂匯']);

function convertCube() {
  const raw = JSON.parse(
    fs.readFileSync(path.join(ALLEN_DIR, 'cube_ALL_LEVELS_rewards.json'), 'utf8')
  );

  const rules = [];

  for (const [rawLevel, schemes] of Object.entries(raw)) {
    const level = CUBE_LEVEL_MAP[rawLevel];
    if (!level) {
      console.warn(`[cube] unknown level key "${rawLevel}", skipping`);
      continue;
    }

    for (const [scheme, merchants] of Object.entries(schemes)) {
      if (CUBE_DEFERRED_SCHEMES.has(scheme)) continue;

      const isSwitchable = CUBE_SWITCHABLE_SCHEMES.has(scheme);
      // level-invariant schemes (rate doesn't change 1/2/3) get applicable_level: null
      // so one rule row covers all levels instead of duplicating 3x.
      const isLevelVariant = isSwitchable; // matches what we observed in the raw data

      for (const [rawName, rate] of Object.entries(merchants)) {
        const { name, bracketNote } = normalizeMerchantName(rawName);
        const constraints = [GENERIC_CONSTRAINT];
        if (bracketNote) constraints.push(bracketNote);
        if (!isSwitchable) {
          constraints.push('此方案是否需另行申請/切換，待與官網條款確認');
        }

        rules.push({
          rule_id: buildRuleId('cube', scheme, name, isLevelVariant ? level : null),
          card_id: 'cathay_cube',
          rule_type: 'merchant',
          match_value: name,
          applicable_level: isLevelVariant ? level : null,
          reward_rate: rate,
          benefit_label: scheme,
          required_action: isSwitchable ? `需切換至${scheme}權益方案` : null,
          constraints,
          is_synthetic_condition: false,
          active: true,
        });
      }
    }
  }

  // de-dupe rows that are identical across levels for level-invariant schemes
  // (raw data repeats them per level even though the rate doesn't change)
  const seen = new Set();
  const deduped = rules.filter((r) => {
    if (r.applicable_level !== null) return true; // keep all level-variant rows
    const key = `${r.card_id}|${r.benefit_label}|${r.match_value}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });

  deduped.push({
    rule_id: 'cube_default',
    card_id: 'cathay_cube',
    rule_type: 'default',
    match_value: '*',
    applicable_level: null,
    reward_rate: 0.3,
    benefit_label: '一般消費',
    required_action: null,
    constraints: [
      '此為沿用先前 mock 資料的預設回饋率，尚未在 Allen 提供的資料中找到官方一般消費基準，待確認',
    ],
    is_synthetic_condition: false,
    active: true,
  });

  return deduped;
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
