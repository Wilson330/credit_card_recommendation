"""計算推薦的單元測試(docs/DB_DESIGN.md 第 9 節中與計算有關的案例)。

不需要資料庫:用真正的 cards.yaml,搭配一份照 0908 爬蟲數字做的假資料。
"""

from datetime import date
from decimal import Decimal

import pytest

from backend.config import BACKEND_DIR
from backend.recommend import Merchant, SchemeRow, recommend
from backend.rules import load_rules

RULES = load_rules(BACKEND_DIR / 'cards.yaml')
TODAY = date(2026, 10, 4)
NOT_BIRTHDAY = date(1990, 3, 15)
BIRTHDAY = date(1990, 10, 15)

LV = ('Level 1', 'Level 2', 'Level 3')
PLANS = ('簡單選', '任意選', 'UP選')

# 方案 → {variant: 回饋率},照 0908 爬蟲
RATES = {
    'cathay_cube': {
        '全支付': dict.fromkeys(LV, '2'), '台塑家': dict.fromkeys(LV, '2'), '集精選': dict.fromkeys(LV, '2'),
        '樂饗購': dict(zip(LV, ('2', '3', '3.3'))), '玩數位': dict(zip(LV, ('2', '3', '3.3'))),
        '趣旅行': dict(zip(LV, ('2', '3', '3.3'))),
        '童樂匯': dict.fromkeys(LV, '5'), '慶生月': dict.fromkeys(LV, '10'),
    },
    'esun_unicard': {'百大特店': dict(zip(PLANS, ('2', '2.5', '3.5')))},
    'ubot_jiho': {'國內人氣餐廳': {'': '10'}, '國內日系特店': {'': '5'},
                  '日本熱門商店': {'': '8'}, '日本交通卡儲值': {'': '1.5'}},
}

M = {   # 假店家:名稱 → Merchant
    '鼎泰豐': Merchant(1, '鼎泰豐', 'dining', 'TW'),
    '台北101': Merchant(2, '台北101', 'department_store', 'TW'),
    '三越': Merchant(3, '三越', 'department_store', 'JP'),
    '台鐵': Merchant(4, '台鐵', 'travel', 'TW'),
    '麗寶樂園': Merchant(5, '麗寶樂園', 'theme_park', 'TW'),
    '10mois': Merchant(6, '10mois台灣官網', 'retail', 'TW'),
    'UNIQLO': Merchant(7, 'UNIQLO', 'retail', 'TW'),
    '一風堂': Merchant(8, '一風堂', 'dining', 'TW'),
    '慶生店': Merchant(9, '火火燒肉販賣所', 'dining', 'TW'),
    '誠品生活': Merchant(10, '誠品生活', 'retail', 'TW'),
    '日本餐廳': Merchant(11, '大阪某餐廳', 'dining', 'JP'),
    '全球飯店': Merchant(12, '全球迪士尼飯店', 'hotel', 'global'),
}

# (卡片, 方案) → {店家編號: 例外回饋率或 None}
NAMED = {
    ('cathay_cube', '樂饗購'): {2: None, 10: None},
    ('cathay_cube', '童樂匯'): {5: None, 6: '10'},
    ('cathay_cube', '慶生月'): {9: None},
    ('esun_unicard', '百大特店'): {2: None, 4: None, 7: None},
    ('ubot_jiho', '國內日系特店'): {7: None},
    ('ubot_jiho', '國內人氣餐廳'): {8: None},
    ('ubot_jiho', '日本熱門商店'): {3: None},
}


def rows_for(merchant):
    """模擬 SQL:每張卡每個方案每個 variant 一列,標出這家店有沒有被點名。"""
    rows = []
    for card_id, schemes in RATES.items():
        for scheme, by_variant in schemes.items():
            named = NAMED.get((card_id, scheme), {})
            hit = merchant is not None and merchant.merchant_id in named
            override = named.get(merchant.merchant_id) if hit else None
            for variant, rate in by_variant.items():
                rows.append(SchemeRow(card_id, scheme, variant, Decimal(rate), is_named=hit,
                                      rate_override=Decimal(override) if override else None))
    return rows


def run(card_id, config, merchant, birthday=NOT_BIRTHDAY):
    results = recommend(RULES, [(card_id, config)], rows_for(merchant), merchant, birthday, TODAY)
    assert len(results) == 1
    return results[0]


def rate(result):
    return float(result.reward_rate)


CUBE_L1 = {'level': 'Level 1', 'kids_club': False}
CUBE_L2 = {'level': 'Level 2', 'kids_club': False}
CUBE_L3 = {'level': 'Level 3', 'kids_club': False}
CUBE_L2_KIDS = {'level': 'Level 2', 'kids_club': True}


# ---- CUBE ----

def test_category_cover_domestic_restaurant():
    r = run('cathay_cube', CUBE_L2, M['鼎泰豐'])
    assert (rate(r), r.scheme_name, r.required_action) == (3.0, '樂饗購', '需切換至樂饗購權益方案')


def test_levels_change_the_rate():
    assert rate(run('cathay_cube', CUBE_L1, M['誠品生活'])) == 2.0
    assert rate(run('cathay_cube', CUBE_L3, M['誠品生活'])) == 3.3


def test_overseas_general_beats_lower_scheme_without_switching():
    r = run('cathay_cube', CUBE_L1, M['三越'])
    assert (rate(r), r.scheme_name, r.is_general, r.required_action) == (2.5, '海外消費', True, None)


def test_overseas_scheme_wins_when_higher():
    r = run('cathay_cube', CUBE_L2, M['三越'])
    assert (rate(r), r.scheme_name) == (3.0, '趣旅行')


def test_travel_category_covered_by_趣旅行():
    r = run('cathay_cube', CUBE_L2, M['台鐵'])
    assert (rate(r), r.scheme_name) == (3.0, '趣旅行')


def test_樂饗購_only_covers_domestic_restaurants():
    r = run('cathay_cube', CUBE_L2, M['日本餐廳'])
    assert r.scheme_name == '趣旅行'      # 國外的店由趣旅行涵蓋,不是樂饗購


def test_global_country_counts_as_overseas():
    r = run('cathay_cube', CUBE_L1, M['全球飯店'])
    assert (rate(r), r.scheme_name) == (2.5, '海外消費')


def test_kids_club_condition():
    assert run('cathay_cube', CUBE_L2, M['麗寶樂園']).scheme_name != '童樂匯'
    r = run('cathay_cube', CUBE_L2_KIDS, M['麗寶樂園'])
    assert (rate(r), r.scheme_name) == (5.0, '童樂匯')


def test_rate_override():
    assert rate(run('cathay_cube', CUBE_L2_KIDS, M['10mois'])) == 10.0


def test_birthday_month():
    r = run('cathay_cube', CUBE_L2, M['慶生店'], birthday=BIRTHDAY)
    assert (rate(r), r.scheme_name, r.required_action) == (10.0, '慶生月', '需切換至慶生月權益方案')
    assert run('cathay_cube', CUBE_L2, M['慶生店'], birthday=NOT_BIRTHDAY).scheme_name != '慶生月'


def test_unknown_merchant_is_general_domestic():
    r = run('cathay_cube', CUBE_L2, None)
    assert (rate(r), r.scheme_name) == (0.3, '一般消費')


# ---- Unicard ----

def uni(plan, e_bill=False, auto_debit=False, chosen=None):
    config = {'plan': plan, 'e_bill': e_bill, 'auto_debit': auto_debit}
    if chosen is not None:
        config['chosen_merchants'] = chosen
    return config


@pytest.mark.parametrize('config, expected', [
    (uni('簡單選'), 2.0),
    (uni('UP選'), 3.5),
    (uni('UP選', e_bill=True, auto_debit=True), 4.5),
    (uni('UP選', e_bill=True), 3.8),
    (uni('UP選', auto_debit=True), 3.5),
    (uni('任意選', e_bill=True, auto_debit=True, chosen=[2]), 3.5),
    (uni('任意選', e_bill=True, auto_debit=True, chosen=[7]), 1.0),   # 沒挑台北101
])
def test_unicard_百大特店(config, expected):
    assert rate(run('esun_unicard', config, M['台北101'])) == expected


@pytest.mark.parametrize('config, expected', [
    (uni('UP選'), 0.0),
    (uni('UP選', e_bill=True), 0.3),
    (uni('UP選', auto_debit=True), 0.0),
    (uni('UP選', e_bill=True, auto_debit=True), 1.0),
])
def test_unicard_general(config, expected):
    assert rate(run('esun_unicard', config, M['鼎泰豐'])) == expected


# ---- 吉鶴卡 ----

NEW = {'new_customer': True}
OLD = {'new_customer': False}


@pytest.mark.parametrize('config, merchant, expected', [
    (NEW, 'UNIQLO', 5.5),      # 國內日系特店 5% + 新戶 0.5%
    (OLD, 'UNIQLO', 5.0),
    (NEW, '一風堂', 10.0),      # 國內人氣餐廳沒有新戶加碼
    (NEW, None, 1.5),          # 國內一般消費 1% + 0.5%
    (OLD, None, 1.0),
    (NEW, '三越', 8.0),         # 日本熱門商店沒有新戶加碼
    (NEW, '全球飯店', 1.0),     # 國外一般消費沒有新戶加碼
])
def test_jiho(config, merchant, expected):
    assert rate(run('ubot_jiho', config, M[merchant] if merchant else None)) == expected


def test_jiho_japan_general():
    japan_store = Merchant(99, '日本某藥妝', 'drugstore', 'JP')
    r = run('ubot_jiho', OLD, japan_store)
    assert (rate(r), r.scheme_name) == (2.5, '日本消費')


# ---- 多張卡 ----

def test_sorted_by_rate_and_cards_not_in_rules_are_ignored():
    cards = [('cathay_cube', CUBE_L2), ('ubot_jiho', NEW), ('esun_unicard', uni('UP選')), ('unknown_card', {})]
    results = recommend(RULES, cards, rows_for(M['台北101']), M['台北101'], NOT_BIRTHDAY, TODAY)
    assert [(r.card_id, float(r.reward_rate)) for r in results] == [
        ('esun_unicard', 3.5), ('cathay_cube', 3.0), ('ubot_jiho', 1.5)]


def test_limit():
    cards = [('cathay_cube', CUBE_L2), ('ubot_jiho', NEW), ('esun_unicard', uni('UP選'))]
    assert len(recommend(RULES, cards, rows_for(None), None, NOT_BIRTHDAY, TODAY, limit=2)) == 2


def test_notes_include_card_scheme_and_merchant_notes():
    rows = [SchemeRow('ubot_jiho', '國內人氣餐廳', '', Decimal('10'), is_named=True, merchant_notes=('限週一至週四',))]
    r = recommend(RULES, [('ubot_jiho', OLD)], rows, M['一風堂'], NOT_BIRTHDAY, TODAY)[0]
    assert r.notes[0] == '實際回饋依當期公告為準'
    assert any('週一至週五' in n for n in r.notes)
    assert r.notes[-1] == '限週一至週四'
