"""一次性遷移:把資料庫改成 v3 結構並灌入資料(docs/DB_DESIGN.md 第 10 節步驟 2、3)。

用法(在專案根目錄,先備份資料庫):
  python -m backend.migrate_v3 --yes

會做的事:
  1. 記下現有使用者的卡片設定(v2 的 card_level、user_card_conditions)
  2. 移除 v2 的店家、方案、使用者卡片資料表(users 與 card_rewards 不動)
  3. 執行 scripts/mysql/schema_v3.sql
  4. 從 lib/data/merchants.json 灌入店家與別名,修正國別、合併 55688
  5. 用 0908 爬蟲檔建立爬蟲原名對照
  6. 把使用者卡片設定轉成 config 寫回
  7. 用匯入流程(importer)灌入方案、回饋率、點名店家

DB 成為正本之後不要再執行,否則人工修改會被蓋掉。之後新的爬蟲資料用 backend.importer。
"""

import argparse
import json
import re
import sys

from .config import REPO_ROOT, load_settings
from .db import connect
from .importer import apply_import, load_ignore_names, plan_import, print_report
from .rules import load_rules
from .text import non_merchant_reason, normalize, split_constraint

SCHEMA_V3 = REPO_ROOT / 'scripts' / 'mysql' / 'schema_v3.sql'
MERCHANTS_JSON = REPO_ROOT / 'lib' / 'data' / 'merchants.json'
CRAWL_JSON = REPO_ROOT / 'lib' / 'data' / 'allen' / 'card_rewards_export_0908.json'

# 爬蟲中同一家店的不同寫法 → merchants.json 中的店名
# 前四筆與 scripts/build_merchants.js 的 MERCHANT_MERGES 相同(merchants.json 就是用它產生的)
MERCHANT_MERGES = {
    '大阪環球影城(USJ)': '大阪環球影城',
    '東京迪士尼樂園': '東京迪士尼',
    'YAYOI彌生軒': 'YAYOI 彌生軒',
    '7-ELEVEN 實體門市': '7-ELEVEN (7-11) 實體門市',
    '55688': '台灣大車隊',               # 台灣大車隊的叫車 App
    # 同一家店在 CUBE 與 Unicard 的名單中寫法不同。不合併的話,搜尋其中一個名字
    # 只會拿到一張卡的方案,另一張卡的點名回饋會漏掉
    '新光三越百貨': '新光三越',
    '遠東SOGO百貨': '遠東SOGO',
    'Global Mall環球購物中心': '環球購物中心',
    'Coupang 酷澎(台灣)': 'Coupang酷澎',
    'Mitsui Shopping Park LaLaport': 'LaLaport',
    'MITSUI OUTLET PARK': '三井OUTLET',
    '高鐵': '台灣高鐵',
    '全聯福利中心 實體門市': '全聯福利中心',
    '淘寶網': '淘寶',
    '卡多摩嬰童館': '卡多摩',
    '台灣壽司郎': '壽司郎',
    '微風百貨': '微風廣場',
    '萬家福/樂家康': '家樂福',
}
# 使用者會打的叫法,但不是爬蟲原名,所以額外加成別名
EXTRA_ALIASES = {
    '台灣大車隊': ['55688'],
    '台灣高鐵': ['高鐵'],
    'LaLaport': ['三井LaLaport', 'Mitsui Shopping Park LaLaport'],
    '三井OUTLET': ['MITSUI OUTLET PARK'],
    '家樂福': ['萬家福', '樂家康', 'Carrefour'],
}
# 國別修正:在很多國家都有據點的店填 global
COUNTRY_FIXES = {'全球迪士尼飯店': 'global', '東橫INN': 'global'}
# 分類修正:這些店出現在慶生月名單上,被 build_merchants.js 依方案自動分類成餐廳。
# 分類會影響樂饗購的「國內所有餐廳」涵蓋,分錯就會拿到不該拿的回饋
CATEGORY_FIXES = {
    '新光三越': 'department_store',
    'Nintendo': 'digital',
    'PlayStation': 'digital',
    '巴哈姆特動畫瘋': 'digital',
    'FunNow': 'digital',
}

V2_TABLES = [
    'user_card_conditions', 'user_cards', 'scheme_merchants', 'scheme_categories', 'scheme_rates',
    'card_schemes', 'cards', 'merchant_source_names', 'merchant_aliases', 'merchants',
]


def sql_statements(path):
    """把 .sql 檔拆成一句一句(去掉 -- 註解)。"""
    text = re.sub(r'--[^\n]*', '', path.read_text(encoding='utf-8'))
    return [s.strip() for s in text.split(';') if s.strip()]


def existing_tables(cur):
    cur.execute('SHOW TABLES')
    return {row[0] for row in cur.fetchall()}


def read_user_cards(cur, rules, tables):
    """讀出現有使用者卡片,轉成 v3 的 config。"""
    if 'user_cards' not in tables:
        return []
    cur.execute('SHOW COLUMNS FROM user_cards')
    columns = {row[0] for row in cur.fetchall()}
    if 'config' in columns:   # 已經是 v3
        cur.execute('SELECT user_id, card_id, config FROM user_cards')
        return [(u, c, json.loads(cfg)) for u, c, cfg in cur.fetchall()]

    conditions = {}
    if 'user_card_conditions' in tables:
        cur.execute('SELECT user_id, card_id, condition_key FROM user_card_conditions')
        for u, c, key in cur.fetchall():
            conditions.setdefault((u, c), set()).add(key)

    cur.execute('SELECT user_id, card_id, card_level FROM user_cards')
    converted = []
    for user_id, card_id, level in cur.fetchall():
        card = rules.cards.get(card_id)
        if card is None:
            print(f'  略過使用者 {user_id} 的卡 {card_id}:不在 cards.yaml')
            continue
        config = {}
        if card.rate_by:
            config[card.rate_by] = level if level in card.options else card.options[0]
        for key in card.toggles:
            config[key] = key in conditions.get((user_id, card_id), set())
        converted.append((user_id, card_id, config))
    return converted


def load_merchants(cur):
    merchants = json.loads(MERCHANTS_JSON.read_text(encoding='utf-8'))
    merged_away = {v for v in MERCHANT_MERGES if any(m['canonical_name'] == v for m in merchants)}

    ids = {}
    for m in merchants:
        name = m['canonical_name']
        if name in merged_away:
            continue
        cur.execute(
            'INSERT INTO merchants (name, primary_category, country, active) VALUES (%s, %s, %s, %s)',
            (name, CATEGORY_FIXES.get(name, m['primary_category']), COUNTRY_FIXES.get(name, m['country']),
             1 if m['active'] else 0))
        ids[name] = cur.lastrowid
    print(f'  店家:{len(ids)} 家(合併掉 {len(merged_away)} 家:{"、".join(sorted(merged_away)) or "無"})')

    # 別名:merchants.json 的別名去掉爬蟲原名的寫法,加上額外別名,再擋掉會撞名的
    by_norm_name = {normalize(n): n for n in ids}
    candidates = []
    for m in merchants:
        name = MERCHANT_MERGES.get(m['canonical_name'], m['canonical_name'])
        if name not in ids:
            continue
        # merchants.json 的別名裡混有爬蟲原名的寫法(例如「大阪環球影城(USJ)」),那些改放對照表;
        # EXTRA_ALIASES 是刻意要給使用者搜尋的,即使也出現在 MERCHANT_MERGES 仍要保留(例如 55688)
        for alias in m['aliases']:
            if alias not in MERCHANT_MERGES:
                candidates.append((name, alias))
        if m['canonical_name'] == name:
            candidates.extend((name, alias) for alias in EXTRA_ALIASES.get(name, []))
    owners = {}
    for name, alias in candidates:
        owners.setdefault(normalize(alias), set()).add(name)
    added, seen = 0, set()
    for name, alias in candidates:
        key = normalize(alias)
        if (name, key) in seen:
            continue
        seen.add((name, key))
        other = by_norm_name.get(key)
        if other and other != name:
            print(f'  略過別名「{alias}」({name}):等於另一家店「{other}」的名稱')
            continue
        if len(owners[key]) > 1:
            print(f'  略過別名「{alias}」:同時屬於 {"、".join(sorted(owners[key]))}')
            continue
        cur.execute('INSERT INTO merchant_aliases (merchant_id, alias) VALUES (%s, %s)', (ids[name], alias))
        added += 1
    print(f'  別名:{added} 個')
    return ids


def load_source_names(cur, ids, crawl):
    mapped, unmatched = 0, []
    for raw in sorted({r['merchant_name'] for r in crawl}):
        if non_merchant_reason(raw):
            continue
        name, _ = split_constraint(raw)
        if non_merchant_reason(name):
            continue
        name = MERCHANT_MERGES.get(name, name)
        if name in ids:
            cur.execute('INSERT INTO merchant_source_names (source_name, merchant_id) VALUES (%s, %s)',
                        (raw, ids[name]))
            mapped += 1
        else:
            unmatched.append(raw)
    print(f'  爬蟲原名對照:{mapped} 筆' + (f',對不到 {len(unmatched)} 筆:{"、".join(unmatched)}' if unmatched else ''))


def main(argv=None):
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--yes', action='store_true', help='確認要移除 v2 資料表並重建')
    args = parser.parse_args(argv)
    if not args.yes:
        parser.error('這會移除並重建資料表,確認已備份後加上 --yes 執行')

    settings = load_settings()
    rules = load_rules(settings.cards_yaml)
    crawl = json.loads(CRAWL_JSON.read_text(encoding='utf-8'))
    conn = connect(settings)
    cur = conn.cursor()
    try:
        tables = existing_tables(cur)
        print('1. 讀取現有使用者卡片')
        user_cards = read_user_cards(cur, rules, tables)
        print(f'  {len(user_cards)} 張')

        print('2. 移除 v2 資料表')
        cur.execute('SET FOREIGN_KEY_CHECKS = 0')
        for table in V2_TABLES:
            if table in tables:
                cur.execute(f'DROP TABLE {table}')
        cur.execute('SET FOREIGN_KEY_CHECKS = 1')

        print('3. 建立 v3 資料表')
        for stmt in sql_statements(SCHEMA_V3):
            cur.execute(stmt)

        print('4. 灌入店家與別名')
        ids = load_merchants(cur)
        print('5. 建立爬蟲原名對照')
        load_source_names(cur, ids, crawl)

        print('6. 寫回使用者卡片設定')
        for user_id, card_id, config in user_cards:
            cur.execute('INSERT INTO user_cards (user_id, card_id, config) VALUES (%s, %s, %s)',
                        (user_id, card_id, json.dumps(config, ensure_ascii=False)))
            print(f'  使用者 {user_id}:{card_id} {config}')
        conn.commit()

        print('7. 匯入方案資料\n')
        plan = plan_import(conn, rules, crawl, load_ignore_names())
        print_report(conn, rules, plan)
        if plan.fatal:
            raise SystemExit(1)
        apply_import(conn, plan)
        conn.commit()
        print('\n遷移完成。')
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == '__main__':
    main()
