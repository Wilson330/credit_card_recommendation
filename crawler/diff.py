"""比較兩份匯出檔:新增或移除的方案、名稱,以及回饋率的變化。

用途:重爬既有的卡時看官網改了什麼;新爬蟲拿 0908 對答案。
只比較新檔中出現的卡,參考檔中其他卡的列不管。
"""
import csv
import json
import re
from collections import defaultdict
from pathlib import Path

from crawler.common import CRAWL_DIR


def load(path):
    path = Path(path)
    if path.suffix == '.csv':
        with path.open(encoding='utf-8-sig', newline='') as f:
            rows = list(csv.DictReader(f))
        for r in rows:
            r['reward_rate'] = float(r['reward_rate'])
        return rows
    return json.loads(path.read_text(encoding='utf-8'))


def latest_previous(card_id, out, card_name=None):
    """db/crawl 中同一張卡最近的另一份匯出檔;沒有的話,找含有這張卡的綜合匯出檔(例如 0908)。"""
    out = Path(out).resolve()
    own = sorted(p for p in CRAWL_DIR.glob(f'card_rewards_export_*_{card_id}.json') if p.resolve() != out)
    if own:
        return own[-1]
    if card_name:
        for p in sorted(CRAWL_DIR.glob('card_rewards_export_*.json'), reverse=True):
            if p.resolve() != out and re.fullmatch(r'card_rewards_export_\d+\.json', p.name):
                if any(r.get('card_name') == card_name for r in load(p)):
                    return p
    return None


def _index(rows, cards):
    idx = defaultdict(dict)   # (卡, 等級, 方案) -> {名稱: 回饋率}
    for r in rows:
        if r['card_name'] in cards:
            idx[(r['card_name'], r['card_level'], r['scheme_name'])][r['merchant_name']] = float(r['reward_rate'])
    return idx


def compare(old_rows, new_rows):
    cards = {r['card_name'] for r in new_rows}
    old, new = _index(old_rows, cards), _index(new_rows, cards)
    changes = {'cards_missing': sorted(cards - {r['card_name'] for r in old_rows}),
               'schemes_added': sorted(set(new) - set(old)),
               'schemes_removed': sorted(set(old) - set(new)),
               'names_added': {}, 'names_removed': {}, 'rate_changed': {}}
    for key in sorted(set(old) & set(new)):
        o, n = old[key], new[key]
        if set(n) - set(o):
            changes['names_added'][key] = sorted(set(n) - set(o))
        if set(o) - set(n):
            changes['names_removed'][key] = sorted(set(o) - set(n))
        moved = [(m, o[m], n[m]) for m in sorted(set(o) & set(n)) if o[m] != n[m]]
        if moved:
            changes['rate_changed'][key] = moved
    return changes


def one_line(c):
    return (f'新方案 {len(c["schemes_added"])}、消失方案 {len(c["schemes_removed"])}、'
            f'新名稱 {sum(map(len, c["names_added"].values()))}、'
            f'消失名稱 {sum(map(len, c["names_removed"].values()))}、'
            f'回饋率變動 {sum(map(len, c["rate_changed"].values()))}')


def format_changes(c):
    """Markdown 條列,給報告用。"""
    def k(key):
        card, level, scheme = key
        return f'{level} {scheme}' if level else scheme

    lines = [f'- 摘要:{one_line(c)}']
    if c['cards_missing']:
        lines.append(f'- 參考檔沒有這張卡:{"、".join(c["cards_missing"])}')
    for key in c['schemes_added']:
        lines.append(f'- 🆕 方案「{k(key)}」參考檔沒有')
    for key in c['schemes_removed']:
        lines.append(f'- ❓ 方案「{k(key)}」參考檔有、這次沒有(漏抓,或官網拿掉了?)')
    for key, names in c['names_removed'].items():
        lines.append(f'- ❓ {k(key)} 少了 {len(names)} 項:{"、".join(names)}')
    for key, names in c['names_added'].items():
        lines.append(f'- 🆕 {k(key)} 多了 {len(names)} 項:{"、".join(names)}')
    for key, moved in c['rate_changed'].items():
        detail = '、'.join(f'{m} {a:g}%→{b:g}%' for m, a, b in moved[:10])
        more = f' 等 {len(moved)} 項' if len(moved) > 10 else ''
        lines.append(f'- 🔁 {k(key)} 回饋率改變:{detail}{more}')
    return lines
