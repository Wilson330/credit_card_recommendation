"""cards.yaml 的載入與檢查。"""

from decimal import Decimal

import pytest

from backend.config import BACKEND_DIR
from backend.rules import RulesError, consistency_warnings, load_rules


@pytest.fixture(scope='module')
def rules():
    return load_rules(BACKEND_DIR / 'cards.yaml')


def test_real_cards_yaml_loads(rules):
    assert set(rules.cards) == {'cathay_cube', 'esun_unicard', 'ubot_jiho'}
    cube = rules.cards['cathay_cube']
    assert cube.rate_by == 'level' and cube.options == ('Level 1', 'Level 2', 'Level 3')
    assert rules.cards['esun_unicard'].pick_plans == {'任意選'}
    assert rules.cards['esun_unicard'].max_chosen_merchants == 8
    assert rules.cards['ubot_jiho'].rate_by is None
    assert rules.by_crawl_name('吉鶴卡').card_id == 'ubot_jiho'


def test_payment_methods(rules):
    uni, cube, jiho = (rules.cards[c] for c in ('esun_unicard', 'cathay_cube', 'ubot_jiho'))
    assert uni.payment_methods[:2] == ('LINE Pay', '街口支付') and len(uni.payment_methods) == 11
    assert uni.pickable_payment_methods == uni.payment_methods       # 任意選都可以挑
    assert cube.payment_methods == ('全支付',) and cube.pickable_payment_methods == ()
    assert cube.schemes['全支付'].payment_methods[0].crawl_name == '全支付國內合作通路'
    assert uni.schemes['百大特店'].payment_methods[0].crawl_name == 'LINE Pay'   # 只寫名稱時兩者相同
    assert jiho.payment_methods == ()


def test_rates_are_decimal_not_float(rules):
    rate = rules.cards['cathay_cube'].general[0].rate
    assert rate == Decimal('0.3') and isinstance(rate, Decimal)


def write(tmp_path, text):
    path = tmp_path / 'cards.yaml'
    path.write_text(text, encoding='utf-8')
    return path


BASE = """
cards:
  c1:
    name: 測試卡
    bank: 測試銀行
    crawl_name: 測試卡
    rate_by: null
    settings:
      toggles: {vip: 貴賓}
    schemes:
      方案A: {}
    general:
      - {name: 一般消費, rate: 1}
"""


def test_minimal_card_loads(tmp_path):
    rules = load_rules(write(tmp_path, BASE))
    assert rules.cards['c1'].toggles == {'vip': '貴賓'}


@pytest.mark.parametrize('bad, message', [
    (BASE.replace('方案A: {}', '方案A: {requires: [vipp]}'), '未定義的條件'),
    (BASE.replace('方案A: {}', '方案A: {typo_key: 1}'), '不認得的欄位'),
    (BASE.replace('rate_by: null', 'rate_by: tier'), 'rate_by'),
    (BASE.replace('rate_by: null', 'rate_by: level'), 'settings.level'),
    (BASE.replace('- {name: 一般消費, rate: 1}', '- {name: 一般消費, rate: "1%"}'), '要是數字'),
    (BASE + '    bonuses:\n      - {requires: [vip], add: 0.5, applies_to: [不存在]}\n', '不是這張卡的方案'),
    (BASE + '    skip_crawl_schemes: {方案A: 重複}\n', '同時出現在'),
    (BASE.replace('    general:\n      - {name: 一般消費, rate: 1}\n', ''), '至少要有一層一般消費'),
    (BASE.replace('方案A: {}', '方案A: {payment_methods: [甲Pay, 甲Pay]}'), '重複的行動支付'),
    (BASE.replace('方案A: {}', '方案A: {payment_methods: [{name: 甲Pay, url: x}]}'), '不認得的欄位'),
    (BASE.replace('方案A: {}', '方案A: {payment_methods: 甲Pay}'), '要是清單'),
    (BASE.replace('方案A: {}', '方案A: {payment_methods: [甲Pay]}\n      方案B: {payment_methods: [{name: 甲Pay, crawl_name: 乙}]}'),
     'crawl_name 不一致'),
    (BASE.replace('toggles: {vip: 貴賓}', 'toggles: {payment_methods: 行動支付}'), '保留名稱'),
])
def test_invalid_yaml_is_rejected_with_a_clear_message(tmp_path, bad, message):
    with pytest.raises(RulesError, match=message):
        load_rules(write(tmp_path, bad))


def test_pick_plan_must_be_a_valid_option(tmp_path):
    text = BASE.replace('rate_by: null', 'rate_by: plan').replace(
        'toggles: {vip: 貴賓}', 'plan: [甲, 乙]\n      max_chosen_merchants: 3').replace(
        '方案A: {}', '方案A: {pick_merchants_when_plan: [丙]}')
    with pytest.raises(RulesError, match='不在 settings.plan 選項中'):
        load_rules(write(tmp_path, text))


def test_consistency_warnings(rules):
    db_keys = {(c.card_id, s) for c in rules.cards.values() for s in c.schemes}
    assert consistency_warnings(rules, db_keys) == []
    db_keys.add(('cathay_cube', '新方案'))
    db_keys.discard(('ubot_jiho', '日本熱門商店'))
    warnings = consistency_warnings(rules, db_keys)
    assert any('新方案' in w and '計算時忽略' in w for w in warnings)
    assert any('日本熱門商店' in w and '資料庫沒有資料' in w for w in warnings)
