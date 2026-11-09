"""食譜引擎:依 crawler/sites/<card_id>.yaml 的設定解析網頁,不用為每張卡寫程式。

食譜由 agent 讀過網頁後撰寫、user 確認;之後重跑只是照食譜執行,結果固定。
格式說明見 crawler/sites/README.md。

每個 block 產生一組列:
  - list:在頁面文字中取 after 與 until 之間的文字,依 separators 切成名稱
  - items:直接列出名稱(例如「日幣消費」這種單獨一項),名稱必須出現在頁面上
回饋率與活動期間都要附上頁面上的原文(rate_evidence / valid_evidence),找不到原文就報錯,
確保每個數字都有出處。
"""
import re

import yaml
from bs4 import BeautifulSoup

from crawler.common import ROOT, clean, split_names

SITES_DIR = ROOT / 'crawler' / 'sites'
DATE = r'(\d{2,4})/(\d{1,2})/(\d{1,2})'
DATE_RANGE = re.compile(DATE + r'\s*[-–~－至]\s*' + DATE)


class RecipeError(Exception):
    pass


def load(card_id):
    path = SITES_DIR / f'{card_id}.yaml'
    return yaml.safe_load(path.read_text(encoding='utf-8')) if path.exists() else None


def page_text(html):
    soup = BeautifulSoup(html, 'html.parser')
    for tag in soup(['script', 'style', 'noscript']):
        tag.decompose()
    return soup.get_text('\n')


def _loose(needle):
    """忽略空白的比對:網頁常在字中間換行,例如「Google Pay/Apple\\nPay」。"""
    return re.compile(r'\s*'.join(re.escape(ch) for ch in re.sub(r'\s+', '', needle)))


def _find(flat, needle, what, start=0):
    """回傳 needle 在頁面文字中的 (起, 迄);找不到丟 RecipeError。"""
    m = _loose(needle).search(flat, start)
    if not m:
        raise RecipeError(f'{what}:頁面上找不到「{needle}」')
    return m.span()


def parse_date_range(text):
    """'115/7/1-115/12/31' 或 '2026/7/8 - 2026/12/31' -> ('2026-07-01', '2026-12-31')。民國年自動換算。"""
    m = DATE_RANGE.search(text)
    if not m:
        return None, None
    nums = [int(x) for x in m.groups()]
    out = []
    for y, mo, d in (nums[:3], nums[3:]):
        y = y + 1911 if y < 1911 else y
        out.append(f'{y:04d}-{mo:02d}-{d:02d}')
    return tuple(out)


def _names(flat, spec, what):
    start = _find(flat, spec['after'], what)[1]
    end = _find(flat, spec['until'], what + f'(「{spec["after"]}」之後)', start)[0] \
        if spec.get('until') else len(flat)
    text = flat[start:end]
    seps = spec.get('separators', '、｜/')
    group = spec.get('group_pattern')
    if not group:
        return [(None, n) for n in split_names(text, seps)]
    # 例如「(1)便利商店：7-ELEVEN、FamilyMart (2)遊樂園：東京迪士尼」,組名當作段落
    out = []
    parts = re.split(group, text)
    for label, body in zip(parts[1::2], parts[2::2]):
        out += [(clean(label), n) for n in split_names(body, seps)]
    return out


def parse(recipe, html, url):
    """回傳 (列, 備註)。食譜與頁面對不上時丟 RecipeError。"""
    flat = clean(page_text(html))
    rows, notes = [], []
    levels = recipe.get('levels') or ['']
    source_url = recipe.get('source_url', url)

    for block in recipe['blocks']:
        what = f'方案「{block["scheme_name"]}」'
        for ev in _as_list(block.get('rate_evidence')):
            _find(flat, ev, what + '的回饋率依據')
        valid = (None, None)
        if block.get('valid_evidence'):
            _find(flat, block['valid_evidence'], what + '的活動期間依據')
            valid = parse_date_range(block['valid_evidence'])

        if 'list' in block:
            names = _names(flat, block['list'], what)
        else:
            names = []
            for item in block['items']:
                s, e = _find(flat, item, what)
                names.append((None, clean(flat[s:e])))   # 用頁面上的寫法
        if not names:
            raise RecipeError(f'{what}:沒有抓到任何名稱')

        rates = block['rate'] if isinstance(block['rate'], dict) else {lv: block['rate'] for lv in levels}
        for level in levels:
            for group, name in names:
                section = block.get('section', '')
                if group:
                    section = f'{section} > {group}' if section else group
                rows.append(dict(bank_name=recipe['bank_name'], card_name=recipe['card_name'], card_level=level,
                                 scheme_name=block['scheme_name'], merchant_name=name,
                                 reward_rate=float(rates[level]), section=section, source_url=source_url,
                                 valid_from=valid[0], valid_to=valid[1]))
        if block.get('rate_basis'):
            notes.append(f'{block["scheme_name"]} 的回饋率 {block["rate"]} 是推算的:{block["rate_basis"]}')
    return rows, notes


def _as_list(x):
    return [] if x is None else x if isinstance(x, list) else [x]
