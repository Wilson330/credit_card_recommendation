"""爬蟲共用邏輯的測試,不連網路:python -m pytest crawler/tests"""
import pytest

from crawler import checks, diff, recipe
from crawler.common import clean, finalize, split_names


def test_split_names_keeps_parentheses():
    assert split_names('MITSUI OUTLET PARK (林口/台中港/台南)｜華泰名品城') == \
        ['MITSUI OUTLET PARK (林口/台中港/台南)', '華泰名品城']
    assert split_names('臺鐵、高鐵 / Uber') == ['臺鐵', '高鐵', 'Uber']
    assert split_names('全家及7-11(兩大超商限台新Pay)｜') == ['全家及7-11(兩大超商限台新Pay)']


def test_clean_joins_wrapped_lines():
    assert clean('COMPOSE\n   COFFEE') == 'COMPOSE COFFEE'
    assert clean('行動支付(\nGoogle Pay/Apple\nPay\n)') == '行動支付(Google Pay/Apple Pay)'


def test_parse_date_range_roc_and_western():
    assert recipe.parse_date_range('活動期間：115/7/1-115/12/31') == ('2026-07-01', '2026-12-31')
    assert recipe.parse_date_range('2026/7/8 - 2026/12/31 快樂上市') == ('2026-07-08', '2026-12-31')
    assert recipe.parse_date_range('沒有日期') == (None, None)


PAGE = """<div><h3>人氣餐廳最高現折10%</h3>
<p>指定人氣餐廳：涮乃葉、一風堂、
金子半之助(限週一至週四)</p>
<p>指定日本熱門商店：(1)便利商店：7-ELEVEN、LAWSON　(2)遊樂園：東京迪士尼</p>
<h3>一般消費回饋無上限</h3><p>國內消費 1%</p></div>"""

RECIPE = {
    'bank_name': '聯邦銀行', 'card_name': '吉鶴卡', 'levels': ['Standard'],
    'blocks': [
        {'scheme_name': '國內人氣餐廳', 'section': '指定人氣餐廳', 'rate': 10, 'rate_evidence': '最高現折10%',
         'list': {'after': '指定人氣餐廳：', 'until': '指定日本熱門商店', 'separators': '、'}},
        {'scheme_name': '日本熱門商店', 'rate': 3, 'rate_basis': '測試',
         'list': {'after': '指定日本熱門商店：', 'until': '一般消費回饋無上限', 'separators': '、',
                  'group_pattern': r'\(\d+\)([^：]+)：'}},
        {'scheme_name': '國內一般消費', 'items': ['國內消費'], 'rate': 1, 'rate_evidence': '國內消費 1%'},
    ],
}


def test_recipe_parse():
    rows, notes = recipe.parse(RECIPE, PAGE, 'https://example.com')
    names = [(r['scheme_name'], r.get('section'), r['merchant_name'], r['reward_rate']) for r in rows]
    assert ('國內人氣餐廳', '指定人氣餐廳', '金子半之助(限週一至週四)', 10.0) in names
    assert ('日本熱門商店', '遊樂園', '東京迪士尼', 3.0) in names
    assert ('國內一般消費', '', '國內消費', 1.0) in names
    assert len(rows) == 7
    assert any('推算' in n for n in notes)


def test_recipe_fails_loudly_when_page_changes():
    with pytest.raises(recipe.RecipeError, match='指定人氣餐廳'):
        recipe.parse(RECIPE, PAGE.replace('指定人氣餐廳', '精選餐廳'), 'https://example.com')
    bad = dict(RECIPE, blocks=[dict(RECIPE['blocks'][0], rate_evidence='最高現折12%')])
    with pytest.raises(recipe.RecipeError, match='回饋率依據'):
        recipe.parse(bad, PAGE, 'https://example.com')


def test_checks_flag_ungrounded_and_derived():
    rows, _ = recipe.parse(RECIPE, PAGE, 'https://example.com')
    rows = finalize(rows + [dict(rows[0], merchant_name='不存在的店')], '2026-11-10 00:00:00')
    issues = checks.check(rows, recipe.page_text(PAGE), today='2026-11-10')
    kinds = {(i['level'], i['check']) for i in issues}
    assert (checks.ERROR, '溯源') in kinds          # 編造的店名
    assert (checks.WARN, '回饋率出處') in kinds      # 3% 不在頁面上


def test_diff():
    old = [dict(card_name='C', card_level='', scheme_name='S', merchant_name=m, reward_rate=r)
           for m, r in [('a', 1), ('b', 1)]]
    new = [dict(card_name='C', card_level='', scheme_name='S', merchant_name=m, reward_rate=r)
           for m, r in [('a', 2), ('c', 1)]]
    c = diff.compare(old, new)
    assert c['names_removed'] == {('C', '', 'S'): ['b']}
    assert c['names_added'] == {('C', '', 'S'): ['c']}
    assert c['rate_changed'] == {('C', '', 'S'): [('a', 1.0, 2.0)]}
