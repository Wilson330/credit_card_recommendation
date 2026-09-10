#!/usr/bin/env node
/**
 * 把 Allen 匯出的回饋資料轉成 card_rewards 的 INSERT script。
 *
 *   node scripts/mysql/build_seed_sql.js
 *     → 產生 scripts/mysql/seed_card_rewards.sql
 *
 * 之所以走「產生 .sql 再灌」而不是 LOAD DATA INFILE：
 *   1. MySQL 8 預設 local_infile=OFF，用 LOAD DATA LOCAL INFILE 還要另外開伺服器設定
 *   2. 匯出的 CSV 有 UTF-8 BOM，LOAD DATA 會把 BOM 一起吃進第一個欄位
 *   3. 資料只有一千多筆，產生的 .sql 也才幾百 KB，直接灌完全不費事
 *
 * 讀 .json 而不是 .csv：兩份是同一批資料，但 JSON 不用自己處理引號跳脫跟 BOM。
 *
 * 產出的 script 是「整批取代」語意 —— 開頭會 TRUNCATE。這張表的內容完全衍生自
 * 匯出檔，不是使用者資料，所以重灌時清空重來才會跟 Allen 那邊一致
 *（上游刪掉的資料才不會變成孤兒留在表裡）。
 */

const fs = require('fs');
const path = require('path');

const SOURCE_JSON = path.join(__dirname, '..', '..', 'lib', 'data', 'allen', 'card_rewards_export_0908.json');
const OUTPUT_SQL = path.join(__dirname, 'seed_card_rewards.sql');

/** 這批資料每一列都必須有的欄位，缺一個就代表匯出格式變了，寧可停下來也不要灌半套資料進去。 */
const REQUIRED_FIELDS = [
  'id',
  'bank_name',
  'card_name',
  'card_level',
  'scheme_name',
  'merchant_name',
  'reward_rate',
  'updated_at',
];

/**
 * MySQL 字串跳脫。這裡是我們自己產生的一次性 seed script、輸入來自可信的匯出檔，
 * 不是在處理使用者輸入，但該跳脫的還是要跳脫 —— 商家名稱裡真的出現一個單引號
 * （像 "Levi's"）就會直接讓整份 script 語法爆掉。
 */
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

function main() {
  const rows = JSON.parse(fs.readFileSync(SOURCE_JSON, 'utf8'));

  if (!Array.isArray(rows) || rows.length === 0) {
    throw new Error(`${path.basename(SOURCE_JSON)} 讀不到資料或不是陣列`);
  }

  const seenIds = new Set();
  for (const row of rows) {
    for (const field of REQUIRED_FIELDS) {
      if (row[field] === undefined || row[field] === null || row[field] === '') {
        throw new Error(`id=${row.id} 缺少欄位 ${field}，匯出格式可能變了`);
      }
    }
    // id 是 PRIMARY KEY，重複的話灌到一半才會炸，不如現在就講清楚是哪一筆
    if (seenIds.has(row.id)) {
      throw new Error(`id=${row.id} 重複出現，匯出檔的 id 應該要唯一`);
    }
    seenIds.add(row.id);
  }

  const values = rows.map((row) => {
    const cells = [
      Number(row.id),
      quote(row.bank_name),
      quote(row.card_name),
      quote(row.card_level),
      quote(row.scheme_name),
      quote(row.merchant_name),
      Number(row.reward_rate).toFixed(2),
      quote(row.updated_at),
    ];
    return `  (${cells.join(', ')})`;
  });

  const header = [
    '-- 這個檔案是產生出來的，不要手動編輯。',
    `-- 來源：lib/data/allen/${path.basename(SOURCE_JSON)}`,
    '-- 重新產生：node scripts/mysql/build_seed_sql.js',
    `-- 共 ${rows.length} 筆`,
    '',
    'USE credit_card_app;',
    '',
    '-- 整批取代：這張表完全衍生自匯出檔，清空重灌才會跟上游一致',
    'TRUNCATE TABLE card_rewards;',
    '',
    'INSERT INTO card_rewards',
    '  (id, bank_name, card_name, card_level, scheme_name, merchant_name, reward_rate, updated_at)',
    'VALUES',
  ].join('\n');

  fs.writeFileSync(OUTPUT_SQL, `${header}\n${values.join(',\n')};\n`, 'utf8');

  // 順手回報一下這批資料有哪些卡，資料換版時比較容易注意到內容變了
  const breakdown = new Map();
  for (const row of rows) {
    const key = `${row.card_name} (${row.card_level})`;
    breakdown.set(key, (breakdown.get(key) || 0) + 1);
  }

  console.log(`已寫出 ${path.relative(process.cwd(), OUTPUT_SQL)}：${rows.length} 筆`);
  for (const [key, count] of [...breakdown.entries()].sort()) {
    console.log(`  ${String(count).padStart(5)}  ${key}`);
  }
}

main();
