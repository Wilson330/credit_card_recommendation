#!/usr/bin/env node
/**
 * 把 lib/data/merchants.json 轉成 merchants / merchant_aliases / merchant_tags
 * 三張表的 INSERT script。
 *
 *   node scripts/mysql/build_merchants_sql.js
 *     → 產生 scripts/mysql/seed_merchants.sql
 *
 * 與 build_seed_sql.js（card_rewards）同一套作法：產生可重跑的 .sql，開頭清空
 * 三張表再整批灌入（內容完全衍生自 merchants.json，清空重來才會跟來源一致）。
 *
 * merchants.json 本身由 scripts/build_merchants.js 從 Allen 的回饋資料產生，
 * 所以完整的重建鏈是：
 *   build_merchants.js → merchants.json → build_merchants_sql.js → seed_merchants.sql
 */

const fs = require('fs');
const path = require('path');

const SOURCE_JSON = path.join(__dirname, '..', '..', 'lib', 'data', 'merchants.json');
const OUTPUT_SQL = path.join(__dirname, 'seed_merchants.sql');

const REQUIRED_FIELDS = [
  'merchant_id', 'canonical_name', 'display_name', 'primary_category',
  'tags', 'aliases', 'channel', 'country', 'active',
];

/**
 * 別名正規化，必須與 Dart 端 MerchantResolver 的 normalize() 完全一致
 *（trim + 轉小寫 + 去掉所有空白），否則 DB 反查的結果會和 App 不同。
 * 若哪天 resolver 的正規化規則改了，這裡要同步改。
 */
function normalizeAlias(value) {
  return String(value).trim().toLowerCase().replace(/\s+/g, '');
}

function quote(value) {
  const escaped = String(value)
    .replace(/\\/g, '\\\\')
    .replace(/'/g, "\\'")
    .replace(/\n/g, '\\n')
    .replace(/\r/g, '\\r')
    .replace(/\x00/g, '\\0')
    .replace(/\x1a/g, '\\Z');
  return `'${escaped}'`;
}

function sqlNullableStr(value) {
  return value === null || value === undefined || value === '' ? 'NULL' : quote(value);
}

function main() {
  const merchants = JSON.parse(fs.readFileSync(SOURCE_JSON, 'utf8'));
  if (!Array.isArray(merchants) || merchants.length === 0) {
    throw new Error(`${path.basename(SOURCE_JSON)} 讀不到資料或不是陣列`);
  }

  const merchantRows = [];
  const aliasRows = [];
  const tagRows = [];
  const seenIds = new Set();

  for (const m of merchants) {
    for (const field of REQUIRED_FIELDS) {
      if (m[field] === undefined || m[field] === null) {
        throw new Error(`merchant_id=${m.merchant_id} 缺少欄位 ${field}`);
      }
    }
    if (seenIds.has(m.merchant_id)) {
      throw new Error(`merchant_id=${m.merchant_id} 重複`);
    }
    seenIds.add(m.merchant_id);

    merchantRows.push(
      `  (${quote(m.merchant_id)}, ${quote(m.canonical_name)}, ${quote(m.display_name)}, ` +
      `${quote(m.primary_category)}, ${sqlNullableStr(m.subcategory)}, ${quote(m.channel)}, ` +
      `${quote(m.country)}, ${m.active ? 1 : 0})`
    );

    // 同一商家內別名去重（大小寫/空白不同但正規化後相同的，只留一筆）
    const seenAlias = new Set();
    for (const alias of m.aliases || []) {
      const norm = normalizeAlias(alias);
      if (!norm || seenAlias.has(norm)) continue;
      seenAlias.add(norm);
      aliasRows.push(`  (${quote(m.merchant_id)}, ${quote(alias)}, ${quote(norm)})`);
    }

    const seenTag = new Set();
    for (const tag of m.tags || []) {
      if (!tag || seenTag.has(tag)) continue;
      seenTag.add(tag);
      tagRows.push(`  (${quote(m.merchant_id)}, ${quote(tag)})`);
    }
  }

  const parts = [];
  parts.push('-- 這個檔案是產生出來的，不要手動編輯。');
  parts.push(`-- 來源：lib/data/merchants.json（${merchants.length} 家商家）`);
  parts.push('-- 重新產生：node scripts/mysql/build_merchants_sql.js');
  parts.push('');
  parts.push('USE credit_card_app;');
  parts.push('');
  parts.push('-- 先清子表再清主表（外鍵順序）；整批取代，對齊 merchants.json');
  parts.push('DELETE FROM merchant_aliases;');
  parts.push('DELETE FROM merchant_tags;');
  parts.push('DELETE FROM merchants;');
  parts.push('');
  parts.push('INSERT INTO merchants');
  parts.push('  (merchant_id, canonical_name, display_name, primary_category, subcategory, channel, country, active)');
  parts.push('VALUES');
  parts.push(`${merchantRows.join(',\n')};`);
  parts.push('');
  parts.push('INSERT INTO merchant_aliases (merchant_id, alias, normalized_alias) VALUES');
  parts.push(`${aliasRows.join(',\n')};`);
  parts.push('');
  parts.push('INSERT INTO merchant_tags (merchant_id, tag) VALUES');
  parts.push(`${tagRows.join(',\n')};`);
  parts.push('');

  fs.writeFileSync(OUTPUT_SQL, parts.join('\n'), 'utf8');

  console.log(`已寫出 ${path.relative(process.cwd(), OUTPUT_SQL)}`);
  console.log(`  merchants:        ${merchantRows.length}`);
  console.log(`  merchant_aliases: ${aliasRows.length}`);
  console.log(`  merchant_tags:    ${tagRows.length}`);
}

main();
