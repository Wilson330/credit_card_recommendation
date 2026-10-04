"""註冊、登入與 token(docs/DB_DESIGN.md 第 5 節)。

token 內含 user_id 與到期時間,用只有後端知道的密鑰簽名。App 之後每次呼叫 API 都放在
Authorization: Bearer <token>。不讓 App 直接送 user_id,是因為 user_id 是流水號,
改個數字就能存取別人的資料;token 被改過簽名就會對不上。
"""

import re
from datetime import date, datetime, timedelta, timezone

import jwt
from werkzeug.security import check_password_hash, generate_password_hash

from .config import TOKEN_DAYS
from .errors import ApiError

_EMAIL_RE = re.compile(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
MIN_PASSWORD_LENGTH = 8
LOGIN_FAILED = '帳號或密碼錯誤'


def create_token(user_id, secret_key, days=TOKEN_DAYS):
    now = datetime.now(timezone.utc)
    payload = {'sub': str(user_id), 'iat': now, 'exp': now + timedelta(days=days)}
    return jwt.encode(payload, secret_key, algorithm='HS256')


def user_id_from_token(token, secret_key):
    """驗證 token 並取出 user_id;過期或被竄改時丟出 401。"""
    try:
        payload = jwt.decode(token, secret_key, algorithms=['HS256'])
        return int(payload['sub'])
    except jwt.ExpiredSignatureError:
        raise ApiError(401, '登入已過期,請重新登入')
    except (jwt.InvalidTokenError, KeyError, ValueError):
        raise ApiError(401, '登入狀態無效,請重新登入')


def user_id_from_header(header, secret_key):
    if not header or not header.startswith('Bearer '):
        raise ApiError(401, '請先登入')
    return user_id_from_token(header[len('Bearer '):].strip(), secret_key)


def _parse_birthday(value):
    try:
        birthday = date.fromisoformat(value)
    except (TypeError, ValueError):
        raise ApiError(400, '生日格式要是 YYYY-MM-DD')
    if birthday > date.today() or birthday.year < 1900:
        raise ApiError(400, '生日不合理')
    return birthday


def register(conn, data):
    """建立帳號,回傳 user_id。"""
    email = (data.get('email') or '').strip().lower()
    password = data.get('password') or ''
    full_name = (data.get('full_name') or '').strip()
    if not email or not password or not full_name or not data.get('birthday'):
        raise ApiError(400, 'email、密碼、姓名、生日都是必填')
    if not _EMAIL_RE.match(email):
        raise ApiError(400, 'email 格式不正確')
    if len(password) < MIN_PASSWORD_LENGTH:
        raise ApiError(400, f'密碼至少要 {MIN_PASSWORD_LENGTH} 個字元')
    birthday = _parse_birthday(data['birthday'])

    cur = conn.cursor()
    cur.execute('SELECT 1 FROM users WHERE email = %(email)s', {'email': email})
    if cur.fetchone():
        raise ApiError(409, '這個 Email 已經被註冊過')
    cur.execute(
        'INSERT INTO users (email, password_hash, full_name, birthday) '
        'VALUES (%(email)s, %(hash)s, %(name)s, %(birthday)s)',
        {'email': email, 'hash': generate_password_hash(password), 'name': full_name, 'birthday': birthday})
    return cur.lastrowid


def login(conn, data):
    """檢查帳號密碼,成功回傳使用者資料。

    帳號不存在與密碼錯誤回同一個訊息,避免有人拿 email 來試出誰註冊過。
    """
    email = (data.get('email') or '').strip().lower()
    password = data.get('password') or ''
    if not email or not password:
        raise ApiError(400, '請輸入 email 與密碼')
    cur = conn.cursor(dictionary=True)
    cur.execute('SELECT id, email, password_hash, full_name, birthday FROM users WHERE email = %(email)s',
                {'email': email})
    user = cur.fetchone()
    if user is None or not _password_ok(user['password_hash'], password):
        raise ApiError(401, LOGIN_FAILED)
    return user


def _password_ok(password_hash, password):
    try:
        return check_password_hash(password_hash, password)
    except (ValueError, TypeError):
        # 例如測試帳號的 password_hash 是 '!'(刻意設成無法登入)
        return False
