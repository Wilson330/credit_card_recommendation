"""台新Richart卡:活動主頁是靜態 HTML,一次請求拿到全部資料。

頁面結構(2026-11 版):
  .plan-item                 一個方案;Chill刷 的三組(瘋聚會等)放在 .chill-plan 底下
    .plan-tag                方案名 + 回饋率(<span>)
    .item-col-title          段落標題,Chill刷 與 Pay著刷 的回饋率寫在這裡
    .item-col-text           店名,以 ｜ / 、 分隔
  .search-note.fix           好饗刷指定飯店的品牌清單
  #popup-6 table             LEVEL1 / LEVEL2 各方案回饋率
  .popup-mask                注意事項彈窗,存成條款檔
"""
import re

from bs4 import BeautifulSoup

from crawler.common import SECTION_SEP, clean, rate, split_names

CARD_ID = 'taishin_richart'
BANK_NAME = '台新銀行'
CARD_NAME = '台新Richart卡'
URLS = ['https://mkp.taishinbank.com.tw/s/2025/RichartCard_2025/index.html']

CHILL_SCHEME = 'Chill刷'
PAY_SUFFIX = '綁定支付享'
DATE_RANGE = re.compile(r'(\d{4})/(\d{1,2})/(\d{1,2})\s*[-–~－]\s*(\d{4})/(\d{1,2})/(\d{1,2})')


def _date_range(text):
    m = DATE_RANGE.search(text)
    if not m:
        return None, None
    y1, m1, d1, y2, m2, d2 = (int(x) for x in m.groups())
    return f'{y1:04d}-{m1:02d}-{d1:02d}', f'{y2:04d}-{m2:02d}-{d2:02d}'


def _own_text(el):
    """元素文字,不含回饋率的 <span>/<small> 與 ⓘ 連結。"""
    el = BeautifulSoup(str(el), 'html.parser')
    for tag in el.select('span:not(.purple), small, a.info'):
        tag.decompose()
    return clean(el.get_text(''))


def _rate_of(el):
    span = el.find('span', class_=lambda c: c != 'purple', recursive=False) if el else None
    return rate(span.get_text()) if span and re.fullmatch(r'\s*[\d.]+\s*', span.get_text()) else None


def _popups(soup):
    """{popup id: (標題, 內文)},以及頁面上有按鈕連到的 id。"""
    popups = {}
    for mask in soup.select('.popup-mask[id]'):
        head = mask.select_one('.popup-head')
        body = mask.select_one('.popup-content')
        popups[mask['id']] = (clean(head.get_text(' ')) if head else mask['id'],
                              body.get_text('\n') if body else '')
    linked = {a['data-id'] for a in soup.select('[data-id]')}
    return popups, linked


def _plan_rows(soup, notes):
    """方案卡片上的列,只有 LEVEL2(頁面上顯示的最高回饋)。"""
    rows = []
    for item in soup.select('.plan-item'):
        tag = item.select_one('.plan-tag')
        tag_name, tag_rate = _own_text(tag), _rate_of(tag)
        chill = item.find_parent(class_='chill-plan') is not None
        scheme = CHILL_SCHEME if chill else tag_name

        # 同一欄裡標題與內文依序配對;一個標題後面不一定有內文
        for col in item.select('.item-col, .item-col-full'):
            title = None
            for el in col.find_all(class_=['item-col-title', 'item-col-text'], recursive=False):
                if 'item-col-title' in el['class']:
                    title = el
                    title_text = _own_text(el)
                    if title_text.endswith(PAY_SUFFIX):
                        # Pay著刷:支付工具寫在標題裡,例如「LINE Pay 及 全盈+Pay(7/8起新增)綁定支付享 2.3%」
                        names = [clean(n) for n in title_text[:-len(PAY_SUFFIX)].split(' 及 ')]
                        rows += [dict(scheme_name=scheme, section=scheme, merchant_name=n,
                                      reward_rate=_rate_of(el)) for n in names]
                    elif el.find_next_sibling(class_='item-col-text') is None:
                        # 只有標題、沒有店名,例如「海外消費(含實體及線上、歐洲國家交易)」
                        rows.append(dict(scheme_name=scheme, section=title_text, merchant_name=title_text,
                                         reward_rate=_rate_of(el) or tag_rate))
                    continue

                if title is not None and _own_text(title).endswith(PAY_SUFFIX):
                    notes.append(f'{scheme}:「{_own_text(title)}」底下的說明是可用通路,不是回饋名單,未轉成列')
                    continue
                text = _own_text(el)
                if '。' in text:
                    text, rest = text.split('。', 1)
                    notes.append(f'{scheme}:店名後的說明未轉成列:「{clean(rest)}」')
                title_text = _own_text(title) if title is not None else ''
                section = f'{tag_name}{SECTION_SEP}{title_text}' if chill else title_text
                row_rate = (_rate_of(title) if title is not None else None) or tag_rate
                rows += [dict(scheme_name=scheme, section=section, merchant_name=n, reward_rate=row_rate)
                         for n in split_names(text)]
    return rows


def _hotel_rows(soup):
    """好饗刷指定飯店的品牌清單,例如「＊【好饗刷3.3%｜指定飯店適用品牌】台北晶華酒店、…」。"""
    rows = []
    for note in soup.select('.search-note.fix'):
        text = clean(note.get_text(' '))
        m = re.match(r'＊【(.+?)([\d.]+)%｜(.+?)】(.*)', text)
        if not m:
            continue
        scheme, r, section, body = m.groups()
        rows += [dict(scheme_name=scheme, section=section, merchant_name=n, reward_rate=rate(r))
                 for n in split_names(body.rstrip('。'), '、')]
    return rows


def _levels(soup):
    """從 #popup-6 的表格讀等級:回傳 ([等級名], {方案: [各等級回饋率文字]})。"""
    table = soup.select_one('#popup-6 table')
    levels = [clean(th.contents[0]) for th in table.select('tr th')[1:]]
    by_scheme = {}
    for tr in table.select('tr')[1:]:
        tds = tr.select('td')
        for scheme in clean(tds[0].get_text()).split('/'):
            by_scheme[scheme] = [clean(td.get_text('')) for td in tds[1:]]
    return levels, by_scheme


def _general_rows(soup):
    """等級表下的註:「保費1.3%、一般消費 0.3％ 不受卡友身分限制皆享回饋」,各等級都一樣。"""
    note = soup.select_one('#popup-6 .pop-note')
    rows = []
    for part in clean(note.get_text('')).removeprefix('註：').split('、'):
        m = re.match(r'(\D+?)\s*([\d.]+)\s*[%％]', part)
        if m:
            name = clean(m.group(1))
            rows.append(dict(scheme_name=name, section='註', merchant_name=name, reward_rate=rate(m.group(2))))
    return rows


def parse(html, url):
    """回傳 (列, 條款 {標題: 文字}, 給人看的備註, 頁面純文字)。"""
    soup = BeautifulSoup(html, 'html.parser')
    for tag in soup(['script', 'style', 'noscript']):
        tag.decompose()
    notes = []
    popups, linked = _popups(soup)

    # 活動期間:Chill刷 看標題下的日期,其他切換方案看有連結的「7大切換方案注意事項」
    chill_period = _date_range(soup.select_one('.chill-date').get_text())
    switch_period = (None, None)
    for pid, (title, body) in popups.items():
        if title == '7大切換方案注意事項':
            period = _date_range(body)
            if pid in linked:
                switch_period = period
            else:
                notes.append(f'彈窗 {pid}「{title}」沒有按鈕連到,活動期間 {period[0]}~{period[1]},'
                             '應是舊版,未採用')
    insurance_period = _date_range(popups.get('popup-4', ('', ''))[1])

    levels, level_rates = _levels(soup)
    top = levels[-1]
    base_rows = _plan_rows(soup, notes) + _hotel_rows(soup)

    rows = []
    for r in base_rows:
        period = chill_period if r['scheme_name'] == CHILL_SCHEME else switch_period
        r = dict(r, valid_from=period[0], valid_to=period[1])
        rows.append(dict(r, card_level=top))
        lower = level_rates.get(r['scheme_name'])
        if lower is None:
            notes.append(f'等級表沒有方案「{r["scheme_name"]}」,只產生 {top} 的列')
            continue
        for level, text in zip(levels[:-1], lower):
            rows.append(dict(r, card_level=level, reward_rate=rate(re.match(r'[\d.]+', text).group())))
    for r in _general_rows(soup):
        period = insurance_period if r['scheme_name'] == '保費' else (None, None)
        rows += [dict(r, card_level=level, valid_from=period[0], valid_to=period[1]) for level in levels]

    for r in rows:
        r.update(bank_name=BANK_NAME, card_name=CARD_NAME, source_url=url)

    terms = {'00_活動主頁': soup.get_text('\n')}
    for pid, (title, body) in popups.items():
        suffix = '' if pid in linked else '_頁面未連結'
        terms[f'{pid}_{title}{suffix}'] = body
    return rows, terms, notes, soup.get_text('\n')
