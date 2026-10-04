"""API 整合測試:連本機 MySQL,用真實資料(docs/DB_DESIGN.md 第 9 節)。"""

import jwt
import pytest

from .conftest import PASSWORD, birthday_not_this_month, birthday_this_month


def put_card(client, headers, card_id, config):
    r = client.put(f'/api/user/cards/{card_id}', json={'config': config}, headers=headers)
    assert r.status_code == 200, r.get_json()
    return r.get_json()


def recommend(client, headers, **body):
    r = client.post('/api/recommend', json=body, headers=headers)
    assert r.status_code == 200, r.get_json()
    data = r.get_json()
    data['by_card'] = {x['card_id']: x for x in data['results']}
    return data


# ---------------------------------------------------------------------------
# 註冊、登入、token
# ---------------------------------------------------------------------------

def test_health(client):
    assert client.get('/api/health').get_json()['status'] == 'ok'


def test_register_validation_and_duplicate(client):
    assert client.post('/api/register', json={'email': 'pytest-x@test.local'}).status_code == 400
    bad_birthday = {'email': 'pytest-x@test.local', 'password': PASSWORD, 'full_name': '甲', 'birthday': '1990/1/1'}
    assert client.post('/api/register', json=bad_birthday).status_code == 400
    ok = dict(bad_birthday, birthday='1990-01-01')
    assert client.post('/api/register', json=ok).status_code == 201
    r = client.post('/api/register', json=ok)
    assert r.status_code == 409 and '已經被註冊' in r.get_json()['error']


def test_login_failure_does_not_reveal_whether_email_exists(client, make_user):
    make_user()
    wrong_password = client.post('/api/login', json={'email': 'pytest-1@test.local', 'password': 'wrong-password'})
    no_account = client.post('/api/login', json={'email': 'pytest-nobody@test.local', 'password': PASSWORD})
    assert wrong_password.status_code == no_account.status_code == 401
    assert wrong_password.get_json() == no_account.get_json() == {'error': '帳號或密碼錯誤'}


def test_api_requires_valid_token(client, make_user, settings):
    assert client.get('/api/cards').status_code == 401
    assert client.get('/api/cards', headers={'Authorization': 'Bearer not-a-token'}).status_code == 401
    forged = jwt.encode({'sub': '1'}, 'some-other-key', algorithm='HS256')
    assert client.get('/api/cards', headers={'Authorization': f'Bearer {forged}'}).status_code == 401
    assert client.get('/api/cards', headers=make_user()).status_code == 200


# ---------------------------------------------------------------------------
# 卡片設定
# ---------------------------------------------------------------------------

def test_card_options(client, make_user):
    cards = {c['card_id']: c for c in client.get('/api/cards', headers=make_user()).get_json()}
    assert cards['esun_unicard']['options'] == ['簡單選', '任意選', 'UP選']
    assert cards['esun_unicard']['pick_merchants_when'] == ['任意選']
    assert cards['esun_unicard']['max_chosen_merchants'] == 8
    assert {'key': 'new_customer', 'label': '新戶自動扣繳'} in cards['ubot_jiho']['toggles']


def test_pickable_merchants(client, make_user, lookup):
    picks = client.get('/api/cards/esun_unicard/pickable_merchants', headers=make_user()).get_json()
    assert lookup.merchant_id('台北101') in {m['merchant_id'] for m in picks}
    assert len(picks) > 8


def test_invalid_card_configs_are_rejected(client, make_user, lookup):
    h = make_user()
    def put(card_id, config):
        return client.put(f'/api/user/cards/{card_id}', json={'config': config}, headers=h)
    assert put('cathay_cube', {'level': 'level_1'}).status_code == 400
    assert put('cathay_cube', {'level': 'Level 1', 'vip': True}).status_code == 400
    assert put('esun_unicard', {'plan': '簡單選', 'chosen_merchants': [lookup.merchant_id('台北101')]}).status_code == 400
    assert put('esun_unicard', {'plan': '任意選', 'chosen_merchants': [lookup.merchant_id('鼎泰豐')]}).status_code == 400
    assert put('no_such_card', {}).status_code == 404


def test_save_list_and_delete_cards(client, make_user):
    h = make_user()
    saved = put_card(client, h, 'cathay_cube', {'level': 'Level 2'})
    assert saved['config'] == {'level': 'Level 2', 'kids_club': False}
    assert [c['card_id'] for c in client.get('/api/user/cards', headers=h).get_json()] == ['cathay_cube']
    assert client.delete('/api/user/cards/cathay_cube', headers=h).status_code == 200
    assert client.delete('/api/user/cards/cathay_cube', headers=h).status_code == 404


# ---------------------------------------------------------------------------
# 搜尋
# ---------------------------------------------------------------------------

def test_suggest(client, make_user):
    h = make_user()
    def names(q):
        return [m['name'] for m in client.get('/api/merchants/suggest', query_string={'q': q}, headers=h).get_json()]
    assert '藏壽司' in names('藏')
    assert names('小七')[0] == '7-ELEVEN (7-11) 實體門市'
    assert names('55688')[0] == '台灣大車隊'
    assert names('') == []
    assert names('%') == []          # % 不會被當成萬用字元


def test_resolve_by_query(client, make_user):
    h = make_user()
    put_card(client, h, 'cathay_cube', {'level': 'Level 2'})
    assert recommend(client, h, query='鼎泰豐信義店')['merchant']['name'] == '鼎泰豐'
    assert recommend(client, h, query='統一超商')['merchant']['name'] == '7-ELEVEN (7-11) 實體門市'
    assert recommend(client, h, query='55688')['merchant']['name'] == '台灣大車隊'


def test_recommend_request_validation(client, make_user):
    h = make_user()
    assert client.post('/api/recommend', json={}, headers=h).status_code == 400
    assert client.post('/api/recommend', json={'merchant_id': 1, 'query': 'x'}, headers=h).status_code == 400
    assert client.post('/api/recommend', json={'merchant_id': 99999999}, headers=h).status_code == 404


# ---------------------------------------------------------------------------
# 推薦計算(真實資料)
# ---------------------------------------------------------------------------

@pytest.fixture(scope='module')
def user(client, make_user, lookup):
    """CUBE Level 2、吉鶴卡新戶、Unicard 任意選(電子帳單 + 自動扣繳,挑了台北101)。"""
    h = make_user(birthday=birthday_not_this_month())
    put_card(client, h, 'cathay_cube', {'level': 'Level 2', 'kids_club': False})
    put_card(client, h, 'ubot_jiho', {'new_customer': True})
    put_card(client, h, 'esun_unicard', {'plan': '任意選', 'e_bill': True, 'auto_debit': True,
                                          'chosen_merchants': [lookup.merchant_id('台北101')]})
    return h


def rate_of(data, card_id):
    return data['by_card'][card_id]['reward_rate']


def test_category_cover(client, user):
    d = recommend(client, user, query='藏壽司')
    assert (rate_of(d, 'cathay_cube'), d['by_card']['cathay_cube']['scheme_name']) == (3.0, '樂饗購')


def test_alias_gets_named_scheme(client, user):
    for q in ('小七', '統一超商'):
        cube = recommend(client, user, query=q)['by_card']['cathay_cube']
        assert cube['reward_rate'] == 2.0 and not cube['is_general']


def test_unknown_store(client, user):
    d = recommend(client, user, query='完全不存在的店家xyz')
    assert d['merchant_found'] is False and d['message'] == '此店家不在回饋名單中,以一般消費計算'
    assert (rate_of(d, 'cathay_cube'), rate_of(d, 'ubot_jiho'), rate_of(d, 'esun_unicard')) == (0.3, 1.5, 1.0)


def test_unicard_任意選_picked_and_not_picked(client, user, lookup):
    assert rate_of(recommend(client, user, query='台北101'), 'esun_unicard') == 3.5
    other = lookup.member('百大特店')
    assert other != '台北101'
    assert rate_of(recommend(client, user, query=other), 'esun_unicard') == 1.0


def test_overseas(client, user, make_user):
    d = recommend(client, user, query='三越')
    assert (rate_of(d, 'cathay_cube'), d['by_card']['cathay_cube']['scheme_name']) == (3.0, '趣旅行')
    assert rate_of(d, 'ubot_jiho') == 8.0
    h = make_user()
    put_card(client, h, 'cathay_cube', {'level': 'Level 1'})
    cube = recommend(client, h, query='三越')['by_card']['cathay_cube']
    assert (cube['reward_rate'], cube['scheme_name'], cube['required_action']) == (2.5, '海外消費', None)


def test_travel_category(client, user):
    d = recommend(client, user, query='台鐵')
    assert (rate_of(d, 'cathay_cube'), d['by_card']['cathay_cube']['scheme_name']) == (3.0, '趣旅行')


def test_jiho_new_customer(client, user, lookup):
    assert rate_of(recommend(client, user, query='UNIQLO'), 'ubot_jiho') == 5.5
    assert rate_of(recommend(client, user, query=lookup.member('國內人氣餐廳')), 'ubot_jiho') == 10.0


def test_levels(client, make_user):
    h = make_user()
    put_card(client, h, 'cathay_cube', {'level': 'Level 1'})
    assert rate_of(recommend(client, h, query='誠品生活'), 'cathay_cube') == 2.0
    put_card(client, h, 'cathay_cube', {'level': 'Level 3'})
    assert rate_of(recommend(client, h, query='誠品生活'), 'cathay_cube') == 3.3


def test_kids_club_and_override(client, make_user, lookup):
    h = make_user()
    put_card(client, h, 'cathay_cube', {'level': 'Level 2', 'kids_club': False})
    assert recommend(client, h, query='麗寶樂園')['by_card']['cathay_cube']['scheme_name'] != '童樂匯'
    put_card(client, h, 'cathay_cube', {'level': 'Level 2', 'kids_club': True})
    assert recommend(client, h, query='麗寶樂園')['by_card']['cathay_cube']['scheme_name'] == '童樂匯'
    store = lookup.member('童樂匯', rate_override=10)
    assert rate_of(recommend(client, h, query=store), 'cathay_cube') == 10.0


def test_birthday_month(client, make_user, lookup):
    store = lookup.member('慶生月')
    h = make_user(birthday=birthday_this_month())
    put_card(client, h, 'cathay_cube', {'level': 'Level 2'})
    cube = recommend(client, h, query=store)['by_card']['cathay_cube']
    assert (cube['reward_rate'], cube['scheme_name'], cube['required_action']) == (10.0, '慶生月', '需切換至慶生月權益方案')
    h2 = make_user(birthday=birthday_not_this_month())
    put_card(client, h2, 'cathay_cube', {'level': 'Level 2'})
    assert recommend(client, h2, query=store)['by_card']['cathay_cube']['scheme_name'] != '慶生月'


def test_recommend_by_merchant_id(client, user, lookup):
    d = recommend(client, user, merchant_id=lookup.merchant_id('台北101'))
    assert d['merchant']['name'] == '台北101'
    assert [r['card_id'] for r in d['results']] == ['esun_unicard', 'cathay_cube', 'ubot_jiho']
