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
    assert validate_config(CUBE, {'level': 'Level 2'}, set()) == {'level': 'Level 2', 'kids_club': False}
    assert validate_config(JIHO, {}, set()) == {'new_customer': False}


def test_任意選_keeps_chosen_merchants():
    cfg = validate_config(UNI, {'plan': '任意選', 'e_bill': True, 'chosen_merchants': [1, 2]}, PICKABLE)
    assert cfg == {'plan': '任意選', 'e_bill': True, 'auto_debit': False, 'chosen_merchants': [1, 2]}


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
])
def test_invalid_config_is_rejected(card, config, message):
    with pytest.raises(ApiError, match=message) as e:
        validate_config(card, config, PICKABLE)
    assert e.value.status == 400
