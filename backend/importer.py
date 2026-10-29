"""爬蟲資料匯入(docs/DB_DESIGN.md 第 8 節,格式見 docs/CRAWL_FORMAT.md)。

用法(在專案根目錄,JSON 或 CSV 都可以):
  python -m backend.importer db/crawl/匯出檔.json --check     只檢查格式(不需要資料庫)
  python -m backend.importer db/crawl/匯出檔.json --dry-run   只看報告
  python -m backend.importer db/crawl/匯出檔.json             正式匯入

處理報告中「對不到店家的爬蟲店名」:
  python -m backend.importer --map "7-ELEVEN 實體門市" 12                        對到既有店家 #12
  python -m backend.importer --new "一蘭拉麵" --category dining --country TW    建立新店

處理報告中「未標記的列」,或不是店家的店名(寫進 db/crawl/labels.yaml):
  python -m backend.importer --label "國內一般消費" general
  python -m backend.importer --label "日本" category --note "百大特店含日本消費"
  python -m backend.importer --ignore "玉山Wallet愛心捐款"                      等於 --label 原文 ignore

處理完再重跑匯入即可。匯入只替換「本次爬蟲有出現的方案」的回饋率與點名店家;
店家本身不會被新增或刪除,新店一定要經過人確認(--new)。
"""

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from decimal import Decimal

from .config import load_settings
from .crawl import (LABEL_TYPES, LABELS_FILE, CrawlFileError, append_label, check_rows, classify,
                    load_labels, load_rows, row_in_effect)
from .db import connect
from .rules import RulesError, load_rules
from .text import normalize, split_constraint


# ---------------------------------------------------------------------------
# 匯入計畫:只讀資料庫,算出要寫入什麼
# ---------------------------------------------------------------------------

@dataclass
class SchemePlan:
    card_id: str
    scheme_name: str
    rates: dict                       # variant → Decimal
    members: list                     # [(merchant_id, rate_override 或 None, notes 清單)]


@dataclass
class ImportPlan:
    schemes: list = field(default_factory=list)
    report: dict = field(default_factory=lambda: defaultdict(list))
    unmapped: dict = field(default_factory=dict)    # 原始店名 → (card_id, scheme_name, 段落)
    unlabeled: dict = field(default_factory=dict)   # 依關鍵字猜的原文 → (猜的類型, card_id, scheme_name, 段落)
    fatal: list = field(default_factory=list)


def mode_rate(rates):
    """出現最多次的回饋率;同票取較低者,避免高估。"""
    counts = Counter(rates)
    top = max(counts.values())
    return min(r for r, c in counts.items() if c == top)


def plan_import(conn, rules, crawl_rows, labels=None, today=None):
    """labels:db/crawl/labels.yaml 的內容(load_labels());None 代表沒有任何標記。"""
    labels = labels or {}
    plan = ImportPlan()
    cur = conn.cursor()
    cur.execute('SELECT source_name, merchant_id FROM merchant_source_names')
    source_map = dict(cur.fetchall())

    in_effect = [row for row in crawl_rows if row_in_effect(row, today)]
    if len(in_effect) != len(crawl_rows):
        plan.report['不在有效期間的列(略過)'].append(
            f'{len(crawl_rows) - len(in_effect)} 列(valid_from 未到或 valid_to 已過)')

    groups = defaultdict(list)
    for row in in_effect:
        card = rules.by_crawl_name(row['card_name'])
        if card is None:
            msg = f'未設定的卡片:{row["card_name"]}(先在 cards.yaml 加入)'
            if msg not in plan.fatal:
                plan.fatal.append(msg)
            continue
        groups[(card.card_id, row['scheme_name'])].append(row)
    if plan.fatal:
        return plan

    for (card_id, scheme_name), rows in sorted(groups.items()):
        card = rules.cards[card_id]

        if scheme_name in card.skip_crawl_schemes:
            plan.report['略過的方案'].append(
                f'{card.name}・{scheme_name}({len(rows)} 列):{card.skip_crawl_schemes[scheme_name]}')
            _check_general(card, rows, plan)
            continue
        if scheme_name not in card.schemes:
            plan.report['未設定的方案(本次略過)'].append(
                f'{card.name}・{scheme_name}({len(rows)} 列),先在 cards.yaml 加入')
            continue

        rule = card.schemes[scheme_name]
        payment_crawl = {p.crawl_name for p in rule.payment_methods}
        payment_rates = defaultdict(dict)   # 行動支付的爬蟲名稱 → {variant: rate},只用來比對
        rate = defaultdict(dict)        # merchant_id → {variant: rate}
        notes = defaultdict(set)
        variants = set()
        for row in rows:
            raw = row['merchant_name']
            key = raw.strip()
            variant = row['card_level'] if card.rate_by else ''
            if card.rate_by and variant not in card.options:
                plan.report['未知的等級或方案(略過)'].append(f'{card.name}・{scheme_name}:{variant}')
                continue
            variants.add(variant)

            kind, source = classify(raw, labels, payment_crawl)
            if source == 'keyword':
                plan.unlabeled.setdefault(key, (kind, card_id, scheme_name, row.get('section')))
            where = f'{card.name}・{scheme_name}'
            note = labels[key].note if key in labels and labels[key].note else None
            if kind == 'ignore':
                continue
            if kind == 'payment_method':
                if key in payment_crawl:
                    payment_rates[key][variant] = Decimal(str(row['reward_rate']))
                else:
                    _report_once(plan, 'cards.yaml 沒有列出的行動支付(略過)',
                                 f'{where}:{key}' + (f'({note})' if note else '(要計算就加進 cards.yaml 該方案的 payment_methods)'))
                continue
            if kind == 'category':
                title = ('類別列:cards.yaml 已設定 covers,確認涵蓋範圍一致' if rule.covers
                         else '類別列:cards.yaml 沒有設定 covers,目前不計算')
                _report_once(plan, title, f'{where}:{key}' + (f'({note})' if note else ''))
                continue
            if kind == 'general':
                _report_once(plan, '方案內的一般消費列(略過)', f'{where}:{key}')
                continue

            merchant_id = source_map.get(raw)
            if merchant_id is None:
                plan.unmapped.setdefault(raw, (card_id, scheme_name, row.get('section')))
                continue
            _, note = split_constraint(raw)
            if note:
                notes[merchant_id].add(note)
            value = Decimal(str(row['reward_rate']))
            prev = rate[merchant_id].get(variant)
            if prev is not None and prev != value:
                plan.report['同方案重複店家'].append(
                    f'{card.name}・{scheme_name}・{variant or "-"}:店家 #{merchant_id} 有 {prev}% 與 {value}%,取較高者')
            rate[merchant_id][variant] = value if prev is None else max(prev, value)

        if not rate:
            plan.report['沒有任何店家的方案(略過)'].append(f'{card.name}・{scheme_name}')
            continue

        base = {v: mode_rate([r[v] for r in rate.values() if v in r]) for v in variants
                if any(v in r for r in rate.values())}
        _check_payment_methods(card, rule, payment_rates, base, plan)

        members = []
        for merchant_id, by_variant in sorted(rate.items()):
            if set(by_variant) != set(base):
                plan.report['例外不一致(略過該店)'].append(
                    f'{card.name}・{scheme_name}:店家 #{merchant_id} 只出現在部分等級 {sorted(by_variant)}')
                continue
            if all(by_variant[v] == base[v] for v in base):
                override = None
            elif len(set(by_variant.values())) == 1:
                override = next(iter(by_variant.values()))
            else:
                plan.report['例外不一致(略過該店)'].append(
                    f'{card.name}・{scheme_name}:店家 #{merchant_id} 各等級回饋率 {by_variant} 無法用單一例外表示')
                continue
            members.append((merchant_id, override, sorted(notes[merchant_id])))
        plan.schemes.append(SchemePlan(card_id, scheme_name, base, members))

    _compare_with_database(cur, rules, plan)
    return plan


def _report_once(plan, title, message):
    if message not in plan.report[title]:
        plan.report[title].append(message)


def _check_payment_methods(card, rule, payment_rates, base, plan):
    """爬蟲中的行動支付與 cards.yaml 比對。行動支付不寫入資料庫,計算時用方案的回饋率,
    所以回饋率跟方案不同時要提醒。"""
    for p in rule.payment_methods:
        found = payment_rates.get(p.crawl_name)
        if not found:
            plan.report['cards.yaml 有、爬蟲沒有的行動支付'].append(f'{card.name}・{rule.name}:{p.crawl_name}')
            continue
        plan.report['行動支付(依 cards.yaml 計算)'].append(f'{card.name}・{rule.name}:{p.name}')
        diff = {v: r for v, r in found.items() if base.get(v) != r}
        if diff:
            plan.report['行動支付回饋率與方案不同(以方案為準)'].append(
                f'{card.name}・{rule.name}:{p.crawl_name} 爬蟲 '
                + '、'.join(f'{v or "-"} {r}%' for v, r in sorted(diff.items()))
                + ',方案 ' + '、'.join(f'{v or "-"} {base.get(v)}%' for v in sorted(diff)))


def _check_general(card, rows, plan):
    """爬蟲中的一般消費列與 cards.yaml 比對,數字不同就提醒(不寫入資料庫)。"""
    tiers = {t.crawl_name: t for t in card.general if t.crawl_name}
    for row in rows:
        tier = tiers.get(row['merchant_name'])
        if tier is None:
            continue
        value = Decimal(str(row['reward_rate']))
        msg = f'{card.name}「{tier.name}」:爬蟲 {value}%,cards.yaml {tier.rate}%'
        if value != tier.rate and msg not in plan.report['一般消費與 cards.yaml 不同']:
            plan.report['一般消費與 cards.yaml 不同'].append(msg)


def _compare_with_database(cur, rules, plan):
    """跟資料庫目前的內容比較:消失的方案、離開名單的店家。"""
    present = {(s.card_id, s.scheme_name) for s in plan.schemes}
    cur.execute('SELECT card_id, scheme_name FROM card_schemes')
    for card_id, scheme_name in cur.fetchall():
        if card_id in rules.cards and (card_id, scheme_name) not in present:
            plan.report['資料庫有、本次爬蟲沒有的方案(保留不動)'].append(f'{card_id}・{scheme_name}')

    for s in plan.schemes:
        cur.execute(
            'SELECT sm.merchant_id, m.name FROM scheme_merchants sm '
            'JOIN card_schemes cs ON cs.scheme_id = sm.scheme_id '
            'JOIN merchants m ON m.merchant_id = sm.merchant_id '
            'WHERE cs.card_id = %s AND cs.scheme_name = %s', (s.card_id, s.scheme_name))
        old = dict(cur.fetchall())
        new = {m[0] for m in s.members}
        for merchant_id in sorted(set(old) - new):
            plan.report['離開方案名單的店家'].append(f'{s.card_id}・{s.scheme_name}:{old[merchant_id]}(#{merchant_id})')


# ---------------------------------------------------------------------------
# 寫入
# ---------------------------------------------------------------------------

def apply_import(conn, plan):
    """把計畫寫進資料庫;呼叫端負責 commit。"""
    cur = conn.cursor()
    for s in plan.schemes:
        cur.execute('INSERT IGNORE INTO card_schemes (card_id, scheme_name) VALUES (%s, %s)',
                    (s.card_id, s.scheme_name))
        cur.execute('SELECT scheme_id FROM card_schemes WHERE card_id = %s AND scheme_name = %s',
                    (s.card_id, s.scheme_name))
        (scheme_id,) = cur.fetchone()
        cur.execute('DELETE FROM scheme_rates WHERE scheme_id = %s', (scheme_id,))
        cur.execute('DELETE FROM scheme_merchants WHERE scheme_id = %s', (scheme_id,))
        cur.executemany(
            'INSERT INTO scheme_rates (scheme_id, variant, reward_rate) VALUES (%s, %s, %s)',
            [(scheme_id, v, r) for v, r in sorted(s.rates.items())])
        cur.executemany(
            'INSERT INTO scheme_merchants (scheme_id, merchant_id, rate_override, notes) VALUES (%s, %s, %s, %s)',
            [(scheme_id, mid, override, json.dumps(notes, ensure_ascii=False) if notes else None)
             for mid, override, notes in s.members])


# ---------------------------------------------------------------------------
# 對不到的店名:配對建議
# ---------------------------------------------------------------------------

# 依店名猜分類(只做建議)
_CATEGORY_PATTERNS = [
    (re.compile(r'(主題樂園|遊樂世界|文化村|科學園區|夢想樂園|動物園|水族|樂園$)'), 'theme_park'),
    (re.compile(r'(大飯店|飯店|酒店|度假|渡假|觀光|溫泉|旅館|Hotel|INN)', re.I), 'hotel'),
    (re.compile(r'(國際學校|雙語|美國學校|小學|國小|中學|高中|學校$)'), 'education'),
    (re.compile(r'(KTV|影城|電影院)'), 'entertainment'),
    (re.compile(r'(旅行社|旅遊$|假期|航空)'), 'travel'),
    (re.compile(r'(加油站)'), 'gas_station'),
    (re.compile(r'(百貨|購物中心|OUTLET|商場)', re.I), 'department_store'),
    (re.compile(r'(餐廳|咖啡|火鍋|燒肉|拉麵|壽司|牛排|食堂|麵|鍋)'), 'dining'),
]
_SCHEME_CATEGORY = {'國內人氣餐廳': 'dining', '慶生月': 'dining', '樂饗購': 'department_store'}


def suggest_for(conn, raw, scheme_name):
    name, _ = split_constraint(raw)
    key = normalize(name)
    cur = conn.cursor()
    cur.execute(
        'SELECT m.merchant_id, m.name, m.normalized_name FROM merchants m '
        'UNION ALL SELECT a.merchant_id, m.name, a.normalized_alias FROM merchant_aliases a '
        'JOIN merchants m ON m.merchant_id = a.merchant_id')
    hits = {}
    for merchant_id, mname, text in cur.fetchall():
        if len(text) >= 2 and len(key) >= 2 and (key in text or text in key):
            score = abs(len(text) - len(key))
            if merchant_id not in hits or score < hits[merchant_id][0]:
                hits[merchant_id] = (score, mname)
    if hits:
        best = sorted(hits.items(), key=lambda x: x[1][0])[:3]
        return '可能是既有店家:' + '、'.join(f'#{mid}「{v[1]}」' for mid, v in best)
    category = next((c for pattern, c in _CATEGORY_PATTERNS if pattern.search(name)),
                    _SCHEME_CATEGORY.get(scheme_name, '(無法判斷)'))
    country = 'JP' if '日本' in scheme_name else 'TW'
    return f'疑似新店,建議分類 {category}、國別 {country}'


# ---------------------------------------------------------------------------
# 報告
# ---------------------------------------------------------------------------

def print_report(conn, rules, plan):
    if plan.fatal:
        print('=== 無法匯入 ===')
        for line in plan.fatal:
            print(f'  {line}')
        return

    print('=== 匯入計畫 ===')
    print(f'{"卡片・方案":<22}{"點名店家":>6}{"例外":>4}  各等級回饋率')
    for s in plan.schemes:
        card = rules.cards[s.card_id]
        overrides = sum(1 for m in s.members if m[1] is not None)
        rates = '、'.join(f'{v or "-"} {r}%' for v, r in sorted(s.rates.items()))
        print(f'{card.name + "・" + s.scheme_name:<22}{len(s.members):>6}{overrides:>4}  {rates}')

    for title, items in plan.report.items():
        print(f'\n--- {title}({len(items)})---')
        for item in items[:15]:
            print(f'  {item}')
        if len(items) > 15:
            print(f'  …另有 {len(items) - 15} 筆')

    if plan.unlabeled:
        print(f'\n--- 未標記的列,依店名關鍵字判斷({len(plan.unlabeled)}),確認後寫進 {LABELS_FILE.name} ---')
        for raw, (kind, card_id, scheme_name, section) in sorted(plan.unlabeled.items()):
            where = f'{rules.cards[card_id].name}・{scheme_name}' + (f'・段落「{section}」' if section else '')
            print(f'  {raw}  [{where}] → 猜是 {kind}({LABEL_TYPES[kind]})')
        print('  處理方式:--label "原文" 類型 [--note "說明"],類型:' + '、'.join(LABEL_TYPES))

    if plan.unmapped:
        print(f'\n--- 對不到店家的爬蟲店名({len(plan.unmapped)}),這些列本次略過 ---')
        for raw, (card_id, scheme_name, section) in sorted(plan.unmapped.items()):
            where = f'{rules.cards[card_id].name}・{scheme_name}' + (f'・段落「{section}」' if section else '')
            print(f'  {raw}  [{where}]')
            print(f'      → {suggest_for(conn, raw, scheme_name)}')
        print('  處理方式:--map "店名" 店家編號 / --new "店名" --category 分類 --country 國別')
        print('  不是店家的話:--label "原文" 類型(一般消費、行動支付、類別、略過)')


# ---------------------------------------------------------------------------
# 指令
# ---------------------------------------------------------------------------

def cmd_map(conn, raw, merchant_id):
    cur = conn.cursor()
    cur.execute('SELECT name FROM merchants WHERE merchant_id = %s', (merchant_id,))
    row = cur.fetchone()
    if row is None:
        raise SystemExit(f'找不到店家 #{merchant_id}')
    cur.execute('INSERT INTO merchant_source_names (source_name, merchant_id) VALUES (%s, %s) '
                'ON DUPLICATE KEY UPDATE merchant_id = VALUES(merchant_id)', (raw, merchant_id))
    conn.commit()
    print(f'已建立對照:「{raw}」→ #{merchant_id}「{row[0]}」')


def cmd_new(conn, raw, category, country):
    name, _ = split_constraint(raw)
    cur = conn.cursor()
    cur.execute('SELECT merchant_id FROM merchants WHERE name = %s', (name,))
    existing = cur.fetchone()
    if existing:
        raise SystemExit(f'店名「{name}」已存在(#{existing[0]}),請改用 --map "{raw}" {existing[0]}')
    cur.execute('INSERT INTO merchants (name, primary_category, country) VALUES (%s, %s, %s)',
                (name, category, country))
    merchant_id = cur.lastrowid
    cur.execute('INSERT INTO merchant_source_names (source_name, merchant_id) VALUES (%s, %s)', (raw, merchant_id))
    conn.commit()
    print(f'已建立新店 #{merchant_id}「{name}」(分類 {category}、國別 {country}),並建立對照「{raw}」')


def cmd_label(raw, label_type, note=None):
    try:
        added = append_label(raw, label_type, note)
    except ValueError as e:
        raise SystemExit(str(e)) from e
    if not added:
        print(f'「{raw.strip()}」已經有標記,要修改請直接編輯 {LABELS_FILE.name}')
        return
    print(f'已標記「{raw.strip()}」為 {label_type}({LABEL_TYPES[label_type]}),寫入 {LABELS_FILE.name}')


def cmd_check(path, settings):
    """只檢查格式,不連資料庫。有錯誤時回傳 1。"""
    try:
        rows = load_rows(path)
    except (CrawlFileError, OSError) as e:
        print(f'無法讀取:{e}')
        return 1
    try:
        known = [c.crawl_name for c in load_rules(settings.cards_yaml).cards.values()]
    except (RulesError, OSError):
        known = []
    result = check_rows(rows, known)
    print(f'=== {path}:{len(rows)} 列 ===')
    for line in result.summary:
        print(f'  {line}')
    for title, items in (('錯誤(要修正才能匯入)', result.errors), ('警告(請確認)', result.warnings)):
        if items:
            print(f'\n--- {title}({len(items)})---')
            for item in items[:30]:
                print(f'  {item}')
            if len(items) > 30:
                print(f'  …另有 {len(items) - 30} 筆')
    print('\n格式檢查通過。' if result.ok else '\n格式檢查沒有通過。')
    return 0 if result.ok else 1


def main(argv=None):
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('crawl_file', nargs='?', help='爬蟲匯出檔(.json 或 .csv)')
    parser.add_argument('--check', action='store_true', help='只檢查格式,不需要資料庫')
    parser.add_argument('--dry-run', action='store_true', help='只印報告,不寫入')
    parser.add_argument('--map', nargs=2, metavar=('店名', '店家編號'))
    parser.add_argument('--new', metavar='店名')
    parser.add_argument('--category')
    parser.add_argument('--country')
    parser.add_argument('--label', nargs=2, metavar=('原文', '類型'), help='類型:' + '、'.join(LABEL_TYPES))
    parser.add_argument('--note', help='搭配 --label,寫在標記上的說明')
    parser.add_argument('--ignore', metavar='原文', help='等於 --label 原文 ignore')
    args = parser.parse_args(argv)

    if args.label:
        cmd_label(args.label[0], args.label[1], args.note)
        return
    if args.ignore:
        cmd_label(args.ignore, 'ignore', args.note)
        return

    settings = load_settings()
    if args.check:
        if not args.crawl_file:
            parser.error('--check 需要指定爬蟲匯出檔')
        raise SystemExit(cmd_check(args.crawl_file, settings))

    conn = connect(settings)
    try:
        if args.map:
            cmd_map(conn, args.map[0], int(args.map[1]))
            return
        if args.new:
            if not args.category or not args.country:
                raise SystemExit('--new 需要同時指定 --category 與 --country')
            cmd_new(conn, args.new, args.category, args.country)
            return
        if not args.crawl_file:
            parser.error('請指定爬蟲匯出檔,或使用 --map / --new / --label / --ignore')

        rules = load_rules(settings.cards_yaml)
        try:
            crawl = load_rows(args.crawl_file)
        except CrawlFileError as e:
            raise SystemExit(str(e)) from e
        check = check_rows(crawl, [c.crawl_name for c in rules.cards.values()])
        if not check.ok:
            print('格式檢查沒有通過,先用 --check 看完整報告:')
            for line in check.errors[:10]:
                print(f'  {line}')
            raise SystemExit(1)
        plan = plan_import(conn, rules, crawl, load_labels())
        print_report(conn, rules, plan)
        if plan.fatal:
            raise SystemExit(1)
        if args.dry_run:
            print('\n(dry-run,未寫入)')
            return
        apply_import(conn, plan)
        conn.commit()
        print('\n已寫入資料庫。')
    finally:
        conn.close()


if __name__ == '__main__':
    main()
