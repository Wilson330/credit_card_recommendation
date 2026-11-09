"""爬蟲結果的自動檢查:確認列是照網頁抄的,把可疑的地方標出來給人看。

不檢查格式(那是 backend.importer --check 的事),只檢查「抄得對不對」。
"""
import re
from collections import defaultdict
from datetime import date

from crawler.common import SECTION_SEP, split_names

ERROR, WARN, INFO = 'error', 'warn', 'info'


def _compact(text):
    return re.sub(r'\s+', '', text)


def check(rows, page_text, today=None):
    """回傳問題清單,每項 {level, check, ids, message}。"""
    today = today or date.today().isoformat()
    page = _compact(page_text)
    issues = []

    def add(level, name, message, ids=()):
        issues.append({'level': level, 'check': name, 'ids': list(ids), 'message': message})

    # 溯源:店名與段落要逐字出現在網頁上(忽略空白),否則可能是解析出錯或編造
    missing = defaultdict(list)
    for r in rows:
        for field in ('merchant_name', 'section'):
            value = r.get(field)
            parts = value.split(SECTION_SEP) if field == 'section' and value else [value]
            if value and any(_compact(p) not in page for p in parts):
                missing[(field, value)].append(r['id'])
    for (field, value), ids in missing.items():
        add(ERROR, '溯源', f'{field}「{value}」在網頁上找不到', ids)

    # 名稱裡還有分隔符號或句子,可能沒切乾淨
    seen = set()
    for r in rows:
        name = r['merchant_name']
        if name in seen:
            continue
        seen.add(name)
        if len(split_names(name)) > 1:
            add(WARN, '分隔符號', f'「{name}」括號外還有 ｜ / 、,可能要再切開')
        if re.search(r'[。，；]', name):
            add(WARN, '句子', f'「{name}」含句號或逗號,可能是說明文字')
        if len(re.sub(r'[(（][^)）]*[)）]', '', name)) > 30:
            add(WARN, '過長', f'「{name}」括號外超過 30 字,可能是說明文字')

    # 回饋率要在網頁出現過的「最高 X%」範圍內
    ceiling = max((float(x) for x in re.findall(r'最高([\d.]+)%', page)), default=None)
    for r in rows:
        if r['reward_rate'] <= 0 or (ceiling and r['reward_rate'] > ceiling):
            add(ERROR, '回饋率', f'{r["merchant_name"]} {r["reward_rate"]}% 不在 0~{ceiling}% 之間', [r['id']])

    # 回饋率的數字本身沒出現在網頁上:可能是加總推算的,請人確認算法
    for value in sorted({r['reward_rate'] for r in rows}):
        if not re.search(rf'(?<![\d.]){re.escape(f"{value:g}")}[%％]', page):
            ids = [r['id'] for r in rows if r['reward_rate'] == value]
            add(WARN, '回饋率出處', f'{value:g}% 沒有直接出現在網頁上,是推算的嗎?', ids)

    # 重複:同等級、方案、名稱出現兩次
    groups = defaultdict(list)
    for r in rows:
        groups[(r['card_name'], r['card_level'], r['scheme_name'], r['merchant_name'])].append(r)
    for (card, level, scheme, name), rs in groups.items():
        if len(rs) > 1:
            rates = sorted({x['reward_rate'] for x in rs})
            level_ = WARN if len(rates) > 1 else INFO
            sections = '、'.join(sorted({x.get('section', '') for x in rs}))
            add(level_, '重複', f'{level} {scheme}「{name}」出現 {len(rs)} 次(段落:{sections};回饋率:{rates})',
                [x['id'] for x in rs])

    # 等級完整:每個等級的(方案、段落、名稱)應該一樣
    by_level = defaultdict(set)
    for r in rows:
        by_level[(r['card_name'], r['card_level'])].add((r['scheme_name'], r.get('section', ''), r['merchant_name']))
    cards = defaultdict(list)
    for card, level in by_level:
        cards[card].append(level)
    for card, levels in cards.items():
        union = set().union(*(by_level[(card, lv)] for lv in levels))
        for lv in levels:
            lacking = union - by_level[(card, lv)]
            if lacking:
                add(WARN, '等級', f'{card} {lv} 少了 {len(lacking)} 項,例如 {sorted(lacking)[:3]}')

    # 活動期間
    for r in rows:
        if r.get('valid_to') and r['valid_to'] < today:
            add(WARN, '期間', f'{r["scheme_name"]}「{r["merchant_name"]}」已過期({r["valid_to"]}),匯入時會略過', [r['id']])
        if r.get('valid_from') and r['valid_from'] > today:
            add(INFO, '期間', f'{r["scheme_name"]}「{r["merchant_name"]}」{r["valid_from"]} 才開始', [r['id']])
    return issues


def summary(rows):
    """各等級、方案的列數與回饋率,給人快速對照網頁用。"""
    table = defaultdict(lambda: defaultdict(int))
    rates = defaultdict(set)
    for r in rows:
        table[r['card_level']][r['scheme_name']] += 1
        rates[(r['card_level'], r['scheme_name'])].add(r['reward_rate'])
    lines = []
    for level in sorted(table):
        lines.append(f'  {level}:')
        for scheme, n in sorted(table[level].items()):
            rs = '、'.join(f'{x:g}%' for x in sorted(rates[(level, scheme)]))
            lines.append(f'    {scheme}:{n} 列,回饋率 {rs}')
    return '\n'.join(lines)
