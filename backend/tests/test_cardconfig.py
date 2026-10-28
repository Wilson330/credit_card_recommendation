"""使用者卡片設定的檢查(docs/DB_DESIGN.md 6.3)。"""

import pytest

from backend.cardconfig import validate_config
from backend.config import BACKEND_DIR
from backend.errors import ApiError
from backend.rules import load_rules

RULES = load_rules(BACKEND_DIR / 'cards.yaml')
CUBE, UNI, JIHO = (RULES.cards[c] for c in ('cathay_cube', 'esun_unicard', 'ubot_jiho'))
PICKABLE = set(range(1, 21))


def test_missing_toggles_default_to_false():
    assert validate_config(CUBE, {'level': 'Level 2'}, set()) == {
        'level': 'Level 2', 'kids_club': False, 'payment_methods': []}
    assert validate_config(JIHO, {}, set()) == {'new_customer': False}


def test_任意選_keeps_chosen_merchants():
    cfg = validate_config(UNI, {'plan': '任意選', 'e_bill': True, 'chosen_merchants': [1, 2]}, PICKABLE)
    assert cfg == {'plan': '任意選', 'e_bill': True, 'auto_debit': False, 'payment_methods': [],
                   'chosen_merchants': [1, 2], 'chosen_payment_methods': []}


def test_任意選_without_chosen_is_empty_list():
    assert validate_config(UNI, {'plan': '任意選'}, PICKABLE)['chosen_merchants'] == []


@pytest.mark.parametrize('card, config, message', [
    (CUBE, {'level': 'level_1'}, '要是以下其中之一'),
    (CUBE, {}, '要是以下其中之一'),
    (CUBE, {'level': 'Level 1', 'vip': True}, '沒有這些設定'),
    (CUBE, {'level': 'Level 1', 'kids_club': 'yes'}, 'true 或 false'),
    (JIHO, {'level': 'Level 1'}, '沒有這些設定'),
    (UNI, {'plan': '簡單選', 'chosen_merchants': [1]}, '不需要挑店'),
    (UNI, {'plan': '任意選', 'chosen_merchants': list(range(1, 10))}, '最多只能挑 8 家'),
    (UNI, {'plan': '任意選', 'chosen_merchants': [1, 1]}, '重複'),
    (UNI, {'plan': '任意選', 'chosen_merchants': [999]}, '不在可挑選的名單'),
    (UNI, {'plan': '任意選', 'chosen_merchants': ['台北101']}, '店家編號'),
    (UNI, 'not a dict', '要是物件'),
    (UNI, {'plan': '簡單選', 'payment_methods': ['Apple Pay']}, '不支援這些行動支付'),
    (UNI, {'plan': '簡單選', 'payment_methods': 'LINE Pay'}, '名稱的清單'),
    (UNI, {'plan': '簡單選', 'payment_methods': ['LINE Pay', 'LINE Pay']}, '重複'),
    (JIHO, {'payment_methods': ['LINE Pay']}, '沒有這些設定'),
    (UNI, {'plan': '簡單選', 'chosen_payment_methods': ['LINE Pay']}, '不需要挑店'),
    (UNI, {'plan': '任意選', 'chosen_payment_methods': ['Apple Pay']}, '不在可挑選的名單'),
    (UNI, {'plan': '任意選', 'chosen_merchants': list(range(1, 8)),
           'chosen_payment_methods': ['LINE Pay', '街口支付']}, '行動支付也算在內'),
])
def test_invalid_config_is_rejected(card, config, message):
    with pytest.raises(ApiError, match=message) as e:
        validate_config(card, config, PICKABLE)
    assert e.value.status == 400


def test_payment_methods_are_kept_in_cards_yaml_order():
    cfg = validate_config(UNI, {'plan': '簡單選', 'payment_methods': ['街口支付', 'LINE Pay']}, PICKABLE)
    assert cfg['payment_methods'] == ['LINE Pay', '街口支付']


def test_任意選_picks_and_payment_methods_share_the_limit():
    cfg = validate_config(UNI, {'plan': '任意選', 'payment_methods': ['LINE Pay'],
                                'chosen_merchants': list(range(1, 8)), 'chosen_payment_methods': ['LINE Pay']},
                          PICKABLE)
    assert len(cfg['chosen_merchants']) + len(cfg['chosen_payment_methods']) == 8


def test_cards_without_payment_methods_do_not_store_the_key():
    assert 'payment_methods' not in validate_config(JIHO, {}, set())
