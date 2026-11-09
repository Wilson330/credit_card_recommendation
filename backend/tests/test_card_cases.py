"""各卡的驗證案例:backend/tests/card_cases/<card_id>.yaml。

每個案例指定店家(資料庫中的店名)與卡片設定,用真的 cards.yaml 與資料庫計算,
比對回饋率、方案、要做的動作,以及行動支付建議。案例檔是給人確認的那張表,
新增或修改卡片時先讓人確認案例,再跑這個測試。需要資料庫,連不上時略過。

案例檔格式:

  card_id: esun_unicard
  sources:                      # 案例依據的官網條款網址或文件
    - https://...
  cases:
    - name: 任意選有挑的百大特店   # 必填,測試失敗時顯示
      merchant: 台北101          # 資料庫中的店名;null 代表找不到店家(以國內一般消費計算)
      config: { plan: 任意選, e_bill: true, auto_debit: true, chosen_merchants: [台北101] }
                                # 跟 API 存的 config 相同,chosen_merchants 寫店名
      birthday_month: false     # 選填,這個月是不是生日月,預設 false
      expect: { rate: 3.5, scheme: 百大特店, action: null }
                                # action 省略等於 null(不用做任何動作)
      payment_suggestion: null  # 選填;省略 = 不檢查,null = 不該有建議,
                                # 有值 = { rate: 2.5, scheme: 百大特店, methods: [LINE Pay] }
      source: 官網「百大特店」段落  # 選填,這個案例的依據
"""

from datetime import date
from decimal import Decimal
from pathlib import Path

import pytest
import yaml

from backend import service
from backend.cardconfig import validate_config
from backend.config import BACKEND_DIR
from backend.errors import ApiError
from backend.recommend import payment_suggestion, recommend, today_in_taiwan
from backend.rules import load_rules

CASES_DIR = Path(__file__).parent / 'card_cases'
RULES = load_rules(BACKEND_DIR / 'cards.yaml')
CASE_KEYS = {'name', 'merchant', 'config', 'birthday_month', 'expect', 'payment_suggestion', 'source'}


def _load_cases():
    params = []
    for path in sorted(CASES_DIR.glob('*.yaml')):
        data = yaml.safe_load(path.read_text(encoding='utf-8')) or {}
        card_id = data.get('card_id')
        for i, case in enumerate(data.get('cases') or []):
            label = f'{path.stem}:{case.get("name", i + 1)}'
            params.append(pytest.param(path.name, card_id, case, id=label))
    return params


def _merchant_id(conn, name):
    cur = conn.cursor()
    cur.execute('SELECT merchant_id FROM merchants WHERE name = %s', (name,))
    row = cur.fetchone()
    assert row, f'資料庫中找不到店家「{name}」(要寫 merchants.name 的完整名稱)'
    return row[0]


def _birthday(is_birthday_month, today):
    month = today.month if is_birthday_month else today.month % 12 + 1
    return date(1990, month, 1)


def test_case_files_exist():
    assert list(CASES_DIR.glob('*.yaml')), f'{CASES_DIR} 中沒有案例檔'


@pytest.mark.parametrize('file_name, card_id, case', _load_cases())
def test_card_case(dbconn, file_name, card_id, case):
    assert card_id in RULES.cards, f'{file_name}:card_id {card_id} 不在 cards.yaml'
    unknown = set(case) - CASE_KEYS
    assert not unknown, f'{file_name}:不認得的欄位 {sorted(unknown)}'
    card_rule = RULES.cards[card_id]

    config = dict(case.get('config') or {})
    if 'chosen_merchants' in config:
        config['chosen_merchants'] = [_merchant_id(dbconn, n) for n in config['chosen_merchants']]
    pickable = {m['merchant_id'] for m in service.pickable_merchants(dbconn, card_rule)}
    try:
        config = validate_config(card_rule, config, pickable)
    except ApiError as e:
        pytest.fail(f'config 不合法:{e.message}')

    merchant = None
    if case.get('merchant') is not None:
        merchant = service.merchant_by_id(dbconn, _merchant_id(dbconn, case['merchant']))
    today = today_in_taiwan()
    birthday = _birthday(case.get('birthday_month', False), today)
    rows = service.scheme_rows(dbconn, [card_id], merchant.merchant_id if merchant else None)
    user_cards = [(card_id, config)]

    (result,) = recommend(RULES, user_cards, rows, merchant, birthday, today)
    expect = case['expect']
    actual = {'rate': result.reward_rate, 'scheme': result.scheme_name, 'action': result.required_action}
    wanted = {'rate': Decimal(str(expect['rate'])), 'scheme': expect['scheme'], 'action': expect.get('action')}
    assert actual == wanted, f'{case["name"]}:結果 {actual},預期 {wanted}'

    if 'payment_suggestion' in case:
        suggestion = payment_suggestion(RULES, user_cards, rows, merchant, birthday, today)
        want = case['payment_suggestion']
        if want is None:
            assert suggestion is None, f'{case["name"]}:不該有行動支付建議,實際 {suggestion.result}'
        else:
            assert suggestion is not None, f'{case["name"]}:應該有行動支付建議'
            got = {'rate': suggestion.result.reward_rate, 'scheme': suggestion.result.scheme_name,
                   'methods': list(suggestion.result.payment_methods)}
            assert got == {'rate': Decimal(str(want['rate'])), 'scheme': want['scheme'],
                           'methods': want['methods']}, f'{case["name"]}:行動支付建議 {got},預期 {want}'
