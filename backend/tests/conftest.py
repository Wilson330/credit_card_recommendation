"""API 測試共用的設定。

API 測試會連本機 MySQL(需要已依 db/README.md 建好資料庫)。測試帳號的 email 都是
pytest-*@test.local,測試開始前與結束後都會刪掉;資料庫連不上時這些測試會被略過。
"""

from datetime import date, timedelta

import pytest

from backend.config import load_settings
from backend.db import connect
from backend.recommend import today_in_taiwan

TEST_EMAIL_PATTERN = 'pytest-%@test.local'
PASSWORD = 'pytest-password'


def _cleanup(conn):
    cur = conn.cursor()
    cur.execute('DELETE uc FROM user_cards uc JOIN users u ON u.id = uc.user_id WHERE u.email LIKE %s',
                (TEST_EMAIL_PATTERN,))
    cur.execute('DELETE FROM users WHERE email LIKE %s', (TEST_EMAIL_PATTERN,))
    conn.commit()


@pytest.fixture(scope='session')
def settings():
    return load_settings()


@pytest.fixture(scope='session')
def dbconn(settings):
    try:
        conn = connect(settings)
    except Exception as e:
        pytest.skip(f'連不上資料庫,略過 API 測試:{e}')
    _cleanup(conn)
    yield conn
    _cleanup(conn)
    conn.close()


@pytest.fixture(scope='session')
def client(settings, dbconn):
    from backend.app import create_app
    app = create_app(settings)
    app.testing = True
    return app.test_client()


@pytest.fixture(scope='session')
def lookup(dbconn):
    """查真實資料:lookup.merchant_id('台北101')、lookup.member('童樂匯', rate_override=10)。"""
    class Lookup:
        def merchant_id(self, name):
            cur = dbconn.cursor()
            cur.execute('SELECT merchant_id FROM merchants WHERE name = %s', (name,))
            row = cur.fetchone()
            assert row, f'資料庫中找不到店家:{name}'
            return row[0]

        def member(self, scheme_name, rate_override=None):
            """某方案點名的一家店的名稱(可指定例外回饋率)。"""
            cur = dbconn.cursor()
            sql = ('SELECT m.name FROM scheme_merchants sm JOIN card_schemes s ON s.scheme_id = sm.scheme_id '
                   'JOIN merchants m ON m.merchant_id = sm.merchant_id WHERE s.scheme_name = %s ')
            params = [scheme_name]
            if rate_override is None:
                sql += 'AND sm.rate_override IS NULL '
            else:
                sql += 'AND sm.rate_override = %s '
                params.append(rate_override)
            cur.execute(sql + 'ORDER BY m.name LIMIT 1', params)
            row = cur.fetchone()
            assert row, f'{scheme_name} 中找不到符合的店家'
            return row[0]
    return Lookup()


@pytest.fixture(scope='session')
def make_user(client):
    """註冊並登入一個測試使用者,回傳 Authorization header。"""
    counter = {'n': 0}

    def _make(birthday=None):
        counter['n'] += 1
        email = f'pytest-{counter["n"]}@test.local'
        birthday = birthday or date(1990, 1, 1)
        r = client.post('/api/register', json={
            'email': email, 'password': PASSWORD, 'full_name': f'測試{counter["n"]}',
            'birthday': birthday.isoformat()})
        assert r.status_code == 201, r.get_json()
        r = client.post('/api/login', json={'email': email, 'password': PASSWORD})
        assert r.status_code == 200, r.get_json()
        return {'Authorization': f'Bearer {r.get_json()["token"]}'}
    return _make


def birthday_this_month():
    return date(1990, today_in_taiwan().month, 1)


def birthday_not_this_month():
    month = today_in_taiwan().month % 12 + 1
    return date(1990, month, 1)
