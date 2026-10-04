#!/usr/bin/env python3
"""
初次遷移:把現行資料灌進 v2 資料表(docs/DB_DESIGN.md 第 6 節)。

來源:
  - lib/data/merchants.json                       店家、分類、國別、別名
  - lib/data/allen/card_rewards_export_0908.json  爬蟲回饋資料(方案、費率、點名店家)
  - 本檔的設定區                                   卡片、方案屬性、一般消費費率、分類涵蓋

用法(先在 scripts/mysql/my.local.cnf 設好連線):
  python scripts/db/migrate_v2.py --dry-run    只印報告,不寫入
  python scripts/db/migrate_v2.py              寫入(v2 表必須是空的)
  python scripts/db/migrate_v2.py --reset      清空 v2 表後重新寫入(user_cards 有資料時拒絕執行)

這是一次性的遷移工具,不是日常的爬蟲匯入流程(DB_DESIGN.md 第 5 節,之後另外實作)。
DB 成為正本之後就不該再用 --reset,否則人工修改會被蓋掉。
"""

import argparse
import configparser
import json
import re
import sys
from collections import Counter, defaultdict
from decimal import Decimal
from pathlib import Path

import mysql.connector

ROOT = Path(__file__).resolve().parents[2]
CNF_PATH = ROOT / 'scripts' / 'mysql' / 'my.local.cnf'
MERCHANTS_JSON = ROOT / 'lib' / 'data' / 'merchants.json'
CRAWL_JSON = ROOT / 'lib' / 'data' / 'allen' / 'card_rewards_export_0908.json'

# =============================================================================
# 設定區
# =============================================================================

# card_name 必須與爬蟲資料一致(匯入時用它對照)
CARDS = [
    ('cathay_cube', '國泰世華', 'CUBE卡'),
    ('ubot_jiho', '聯邦銀行', '吉鶴卡'),
    ('esun_unicard', '玉山銀行', 'Unicard'),
]

GENERIC_NOTE = '實際回饋依當期公告為準'

# 一般方案(有點名店家的方案)。名稱照爬蟲,屬性人工設定。
# CUBE 的方案都要切換權益方案才適用(2026-08-06 與 Allen 確認;童樂匯為假設,見 notes)
SCHEMES = {
    'CUBE卡': {
        '全支付': {},
        '台塑家': {},
        '樂饗購': {},
        '玩數位': {},
        '趣旅行': {},
        '集精選': {},
        '童樂匯': {
            'required_condition': 'kids_club',
            'notes': ['是否需另行切換方案尚未與官網條款或 Allen 確認'],
        },
    },
    'Unicard': {
        '百大特店': {},
    },
    '吉鶴卡': {
        '國內人氣餐廳': {},
        '國內日系特店': {},
        '日本熱門商店': {},
        '日本交通卡儲值': {},
    },
}


def required_action_for(card_name, scheme_name):
    if card_name == 'CUBE卡':
        return f'需切換至{scheme_name}權益方案'
    return None


# 一般消費類方案(is_default = 1)。費率人工設定,或取自爬蟲中某個方案的列。
DEFAULT_SCHEMES = [
    {
        'card': 'CUBE卡', 'name': '一般消費',
        'rates': {'Level 1': 0.3, 'Level 2': 0.3, 'Level 3': 0.3},
        'notes': ['不含保費'],
    },
    {
        'card': 'Unicard', 'name': '一般消費',
        'rates': {'簡單選': 0.3, '任意選': 0.3, 'UP選': 0.3},
    },
    {
        'card': 'Unicard', 'name': '一般消費(自動扣繳)',
        'required_condition': 'auto_debit',
        'rates': {'簡單選': 1.0, '任意選': 1.0, 'UP選': 1.0},
        'notes': ['需設定自動扣繳信用卡帳款'],
    },
    {
        'card': '吉鶴卡', 'name': '一般消費',
        'from_crawl_scheme': '國內一般消費',
    },
]

# 爬蟲中整個方案略過,以及原因(出現在報告中)
SKIPPED_SCHEMES = {
    ('CUBE卡', '慶生月'): '依時間的條件(生日月),登入功能完成後再納入',
    ('CUBE卡', '固定回饋'): '一般消費改用人工設定 0.3%(爬蟲為 1.2%,已確認不採用);海外消費需要地點資訊',
    ('吉鶴卡', '國外一般消費'): '需要地點資訊',
    ('吉鶴卡', '日本消費'): '需要地點/付款方式資訊',
}

# 方案涵蓋的店家分類
SCHEME_CATEGORIES = [
    ('CUBE卡', '樂饗購', 'dining'),
    ('CUBE卡', '趣旅行', 'hotel'),
]

# =============================================================================
# 店名處理:與 scripts/build_merchants.js 完全一致,merchants.json 就是用它產生的
# =============================================================================

MERCHANT_MERGES = {
    '大阪環球影城(USJ)': '大阪環球影城',
    '東京迪士尼樂園': '東京迪士尼',
    'YAYOI彌生軒': 'YAYOI 彌生軒',
    '7-ELEVEN 實體門市': '7-ELEVEN (7-11) 實體門市',
}

CONSTRAINT_BRACKET_KEYWORDS = ['限', '不含', '僅', '需', '限定', '週', '街邊店', '儲值', '電子票券', '結帳']
BRACKET_RE = re.compile(r'^(.*?)\s*[\(（](.+?)[\)）]\s*$')

COUNTRY_NAMES = {
    '日本', '韓國', '美國', '中國', '香港', '新加坡', '馬來西亞', '泰國', '越南',
    '菲律賓', '澳洲', '紐西蘭', '加拿大', '英國', '法國', '德國', '義大利', '西班牙', '澳門',
}
BUCKET_RE = re.compile(r'(一般消費|海外實體消費|日幣消費|飯店住宿|行動支付|保費)')
PAYMENT_RE = re.compile(r'(支付|錢包|Wallet|iPASS|icash|悠遊付|Pay$|PAY$)')


def non_merchant_reason(name):
    """不是店家的列回傳原因,是店家回傳 None。"""
    n = name.strip()
    if n in COUNTRY_NAMES:
        return '國別'
    if BUCKET_RE.search(n):
        return '一般消費/地點/保費類'
    if PAYMENT_RE.search(n):
        return '付款工具'
    return None


def parse_source_name(raw):
    """原始店名 → (merchants.json 中的店名, 括號中的限制說明或 None)"""
    name = raw.strip()
    note = None
    m = BRACKET_RE.match(name)
    if m and any(kw in m.group(2).strip() for kw in CONSTRAINT_BRACKET_KEYWORDS):
        name = m.group(1).strip()
        note = m.group(2).strip()
    return MERCHANT_MERGES.get(name, name), note


def normalize(s):
    """與 DB 產生欄位相同:去頭尾空白、轉小寫、移除半形與全形空白"""
    return s.strip().lower().replace(' ', '').replace('　', '')


def mode_rate(rates):
    """出現最多次的回饋率;同票取較低者,避免高估"""
    counts = Counter(rates)
    top = max(counts.values())
    return min(r for r, c in counts.items() if c == top)


# =============================================================================
# 建立遷移計畫(純計算,不碰資料庫)
# =============================================================================

def build_plan():
    merchants_json = json.loads(MERCHANTS_JSON.read_text(encoding='utf-8'))
    crawl = json.loads(CRAWL_JSON.read_text(encoding='utf-8'))

    report = defaultdict(list)
    card_by_name = {name: cid for cid, _, name in CARDS}

    # ---- 店家 ----
    merchants = [
        {
            'name': m['canonical_name'],
            'primary_category': m['primary_category'],
            'country': m['country'],
            'active': 1 if m['active'] else 0,
        }
        for m in merchants_json
    ]
    merchant_names = {m['name'] for m in merchants}

    # ---- 別名 ----
    # 爬蟲原名的變體(MERCHANT_MERGES)改放對照表,不放別名(DB_DESIGN.md 3.7)
    merge_variants = set(MERCHANT_MERGES)
    owner_of_name = {normalize(m['name']): m['name'] for m in merchants}
    candidate_aliases = []  # (店名, 別名)
    alias_owners = defaultdict(set)
    for m in merchants_json:
        seen = set()
        for alias in m['aliases']:
            if alias in merge_variants:
                continue
            key = normalize(alias)
            if key in seen:
                continue
            seen.add(key)
            candidate_aliases.append((m['canonical_name'], alias))
            alias_owners[key].add(m['canonical_name'])

    aliases = []
    for merchant_name, alias in candidate_aliases:
        key = normalize(alias)
        name_owner = owner_of_name.get(key)
        if name_owner and name_owner != merchant_name:
            report['別名衝突(略過)'].append(f'「{alias}」是「{merchant_name}」的別名,但等於另一家店「{name_owner}」的名稱')
            continue
        if len(alias_owners[key]) > 1:
            report['別名衝突(略過)'].append(f'「{alias}」同時是多家店的別名:{"、".join(sorted(alias_owners[key]))}')
            continue
        aliases.append((merchant_name, alias))

    # ---- 爬蟲原名對照 ----
    source_names = {}  # 原始店名 → 店名
    for raw in sorted({r['merchant_name'] for r in crawl}):
        if non_merchant_reason(raw):
            continue
        key, _ = parse_source_name(raw)
        if non_merchant_reason(key):
            continue
        if key in merchant_names:
            source_names[raw] = key
        else:
            report['對不到店家的爬蟲店名'].append(raw)

    # ---- 方案 ----
    crawl_by_scheme = defaultdict(list)
    for r in crawl:
        if r['card_name'] not in card_by_name:
            raise SystemExit(f'爬蟲中有未設定的卡片「{r["card_name"]}」,請先加進 CARDS')
        crawl_by_scheme[(r['card_name'], r['scheme_name'])].append(r)

    default_from_crawl = {
        (d['card'], d['from_crawl_scheme']): d for d in DEFAULT_SCHEMES if 'from_crawl_scheme' in d
    }

    schemes = []  # 每個方案:card, name, is_default, action, condition, notes, rates, members
    for d in DEFAULT_SCHEMES:
        schemes.append({
            'card': d['card'], 'name': d['name'], 'is_default': 1,
            'required_action': None,
            'required_condition': d.get('required_condition'),
            'notes': [GENERIC_NOTE] + d.get('notes', []),
            'rates': dict(d.get('rates', {})),
            'members': [],
        })
    default_index = {(s['card'], s['name']): s for s in schemes}

    for (card, scheme_name), rows in sorted(crawl_by_scheme.items()):
        if (card, scheme_name) in SKIPPED_SCHEMES:
            report['略過的方案'].append(
                f'{card}・{scheme_name}({len(rows)} 列):{SKIPPED_SCHEMES[(card, scheme_name)]}')
            continue

        if (card, scheme_name) in default_from_crawl:
            target = default_index[(card, default_from_crawl[(card, scheme_name)]['name'])]
            by_level = defaultdict(list)
            for r in rows:
                by_level[r['card_level']].append(r['reward_rate'])
            for level, rates in by_level.items():
                target['rates'][level] = mode_rate(rates)
            continue

        meta = SCHEMES.get(card, {}).get(scheme_name)
        if meta is None:
            report['未設定的方案(略過)'].append(f'{card}・{scheme_name}({len(rows)} 列)')
            continue

        schemes.append(build_merchant_scheme(card, scheme_name, meta, rows, source_names, report))

    # ---- 分類涵蓋 ----
    scheme_keys = {(s['card'], s['name']) for s in schemes}
    for card, scheme_name, category in SCHEME_CATEGORIES:
        if (card, scheme_name) not in scheme_keys:
            raise SystemExit(f'SCHEME_CATEGORIES 指到不存在的方案:{card}・{scheme_name}')

    for s in schemes:
        if not s['rates']:
            raise SystemExit(f'方案沒有任何費率:{s["card"]}・{s["name"]}')

    return {
        'merchants': merchants,
        'aliases': aliases,
        'source_names': source_names,
        'schemes': schemes,
        'categories': SCHEME_CATEGORIES,
        'report': report,
    }


def build_merchant_scheme(card, scheme_name, meta, rows, source_names, report):
    levels = sorted({r['card_level'] for r in rows})
    rate = defaultdict(dict)       # 店名 → {等級: 回饋率}
    notes = defaultdict(set)       # 店名 → 括號限制說明

    for r in rows:
        raw = r['merchant_name']
        reason = non_merchant_reason(raw)
        if reason:
            report['方案內非店家的列(略過)'].append(f'{card}・{scheme_name}・{r["card_level"]}:{raw}({reason})')
            continue
        name = source_names.get(raw)
        if name is None:
            continue  # 已列在「對不到店家的爬蟲店名」
        _, note = parse_source_name(raw)
        if note:
            notes[name].add(note)
        level = r['card_level']
        prev = rate[name].get(level)
        if prev is not None and prev != r['reward_rate']:
            report['同方案重複店家'].append(
                f'{card}・{scheme_name}・{level}:{name} 有 {prev}% 與 {r["reward_rate"]}%,取較高者')
        rate[name][level] = max(prev or 0, r['reward_rate'])

    base = {
        level: mode_rate([by_level[level] for by_level in rate.values() if level in by_level])
        for level in levels
    }

    members = []
    for name, by_level in sorted(rate.items()):
        if set(by_level) != set(levels):
            report['例外不一致(略過該店)'].append(
                f'{card}・{scheme_name}:{name} 只出現在部分等級 {sorted(by_level)}')
            continue
        if all(by_level[lv] == base[lv] for lv in levels):
            override = None
        elif len(set(by_level.values())) == 1:
            override = next(iter(by_level.values()))
        else:
            report['例外不一致(略過該店)'].append(
                f'{card}・{scheme_name}:{name} 各等級回饋率 {by_level} 無法用單一例外回饋率表示')
            continue
        members.append({'name': name, 'override': override, 'notes': sorted(notes[name]) or None})

    return {
        'card': card, 'name': scheme_name, 'is_default': 0,
        'required_action': required_action_for(card, scheme_name),
        'required_condition': meta.get('required_condition'),
        'notes': [GENERIC_NOTE] + meta.get('notes', []),
        'rates': base,
        'members': members,
    }


# =============================================================================
# 寫入資料庫
# =============================================================================

V2_TABLES_IN_DELETE_ORDER = [
    'scheme_merchants', 'scheme_categories', 'scheme_rates', 'card_schemes',
    'merchant_source_names', 'merchant_aliases', 'merchants', 'cards',
]


def connect():
    if not CNF_PATH.exists():
        raise SystemExit(f'找不到 {CNF_PATH},請先從 my.local.cnf.example 複製並填入密碼')
    cnf = configparser.RawConfigParser()
    cnf.read(CNF_PATH, encoding='utf-8')
    c = cnf['client']
    return mysql.connector.connect(
        host=c.get('host', '127.0.0.1'),
        user=c.get('user', 'root'),
        password=c.get('password', ''),
        database='credit_card_app',
        charset='utf8mb4',
        collation='utf8mb4_unicode_ci',
    )


def reset_v2_tables(conn):
    cur = conn.cursor()
    cur.execute('SELECT COUNT(*) FROM user_cards')
    if cur.fetchone()[0] > 0:
        raise SystemExit('user_cards 已有資料,拒絕 --reset(會連帶影響使用者的卡片)')
    for table in V2_TABLES_IN_DELETE_ORDER:
        cur.execute(f'DELETE FROM {table}')
    conn.commit()
    for table in ('merchants', 'card_schemes'):
        cur.execute(f'ALTER TABLE {table} AUTO_INCREMENT = 1')


def to_decimal(x):
    return Decimal(str(x)).quantize(Decimal('0.01'))


def to_json(notes):
    return json.dumps(notes, ensure_ascii=False) if notes else None


def write_plan(conn, plan):
    cur = conn.cursor()

    cur.executemany(
        'INSERT INTO cards (card_id, bank_name, card_name) VALUES (%s, %s, %s)', CARDS)
    card_id = {name: cid for cid, _, name in CARDS}

    merchant_id = {}
    for m in plan['merchants']:
        cur.execute(
            'INSERT INTO merchants (name, primary_category, country, active) VALUES (%s, %s, %s, %s)',
            (m['name'], m['primary_category'], m['country'], m['active']))
        merchant_id[m['name']] = cur.lastrowid

    cur.executemany(
        'INSERT INTO merchant_aliases (merchant_id, alias) VALUES (%s, %s)',
        [(merchant_id[name], alias) for name, alias in plan['aliases']])

    cur.executemany(
        'INSERT INTO merchant_source_names (source_name, merchant_id) VALUES (%s, %s)',
        [(raw, merchant_id[name]) for raw, name in plan['source_names'].items()])

    scheme_id = {}
    for s in plan['schemes']:
        cur.execute(
            'INSERT INTO card_schemes (card_id, scheme_name, is_default, required_action, required_condition, notes) '
            'VALUES (%s, %s, %s, %s, %s, %s)',
            (card_id[s['card']], s['name'], s['is_default'], s['required_action'],
             s['required_condition'], to_json(s['notes'])))
        sid = cur.lastrowid
        scheme_id[(s['card'], s['name'])] = sid

        cur.executemany(
            'INSERT INTO scheme_rates (scheme_id, card_level, reward_rate) VALUES (%s, %s, %s)',
            [(sid, level, to_decimal(rate)) for level, rate in sorted(s['rates'].items())])

        cur.executemany(
            'INSERT INTO scheme_merchants (scheme_id, merchant_id, rate_override, notes) VALUES (%s, %s, %s, %s)',
            [(sid, merchant_id[mb['name']],
              to_decimal(mb['override']) if mb['override'] is not None else None,
              to_json(mb['notes']))
             for mb in s['members']])

    cur.executemany(
        'INSERT INTO scheme_categories (scheme_id, category) VALUES (%s, %s)',
        [(scheme_id[(card, name)], category) for card, name, category in plan['categories']])


# =============================================================================
# 報告
# =============================================================================

def print_report(plan):
    print('=== 遷移計畫 ===')
    print(f'店家 {len(plan["merchants"])} 家,別名 {len(plan["aliases"])} 個,爬蟲原名對照 {len(plan["source_names"])} 筆')
    print(f'方案 {len(plan["schemes"])} 個,分類涵蓋 {len(plan["categories"])} 筆\n')

    print(f'{"卡片・方案":<24}{"類型":<6}{"條件":<12}{"點名店家":>6}{"例外":>4}  各等級回饋率')
    for s in plan['schemes']:
        kind = '一般' if s['is_default'] else '方案'
        overrides = sum(1 for m in s['members'] if m['override'] is not None)
        rates = '、'.join(f'{lv} {r}%' for lv, r in sorted(s['rates'].items()))
        print(f'{s["card"] + "・" + s["name"]:<24}{kind:<6}{s["required_condition"] or "-":<12}'
              f'{len(s["members"]):>6}{overrides:>4}  {rates}')

    for title, items in plan['report'].items():
        print(f'\n--- {title}({len(items)})---')
        limit = 15
        for item in items[:limit]:
            print(f'  {item}')
        if len(items) > limit:
            print(f'  …另有 {len(items) - limit} 筆')


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--dry-run', action='store_true', help='只印報告,不寫入')
    parser.add_argument('--reset', action='store_true', help='清空 v2 表後重新寫入')
    args = parser.parse_args()

    plan = build_plan()
    print_report(plan)
    if args.dry_run:
        print('\n(dry-run,未寫入)')
        return

    conn = connect()
    try:
        if args.reset:
            reset_v2_tables(conn)
        else:
            cur = conn.cursor()
            cur.execute('SELECT COUNT(*) FROM merchants')
            if cur.fetchone()[0] > 0:
                raise SystemExit('v2 表已有資料。這是初次遷移工具,要重來請加 --reset')
        # 連線預設 autocommit 關閉,以下所有寫入在同一個交易內,失敗時整批 rollback
        write_plan(conn, plan)
        conn.commit()
        print('\n已寫入資料庫。')
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == '__main__':
    main()
