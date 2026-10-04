"""後端用到的資料庫查詢(docs/DB_DESIGN.md 第 7 節)。

mysql-connector 的參數寫法是 %(name)s,所以 SQL 中的 % 字元要寫成 %%。
"""

import json

from .recommend import Merchant, SchemeRow
from .text import like_escape, normalize

# ---- 7.1 自動補全 ----

SUGGEST_SQL = """
SELECT m.merchant_id, m.name,
       MIN(CASE
             WHEN m.normalized_name = %(q)s OR a.normalized_alias = %(q)s THEN 1
             WHEN m.normalized_name LIKE CONCAT(%(q_like)s, '%%')
               OR a.normalized_alias LIKE CONCAT(%(q_like)s, '%%') THEN 2
             ELSE 3
           END) AS match_rank
FROM merchants m
LEFT JOIN merchant_aliases a ON a.merchant_id = m.merchant_id
WHERE m.active = 1
  AND (m.normalized_name LIKE CONCAT('%%', %(q_like)s, '%%')
       OR a.normalized_alias LIKE CONCAT('%%', %(q_like)s, '%%'))
GROUP BY m.merchant_id, m.name
ORDER BY match_rank, CHAR_LENGTH(m.name)
LIMIT %(limit)s
"""

# ---- 7.2 確定店家 ----

RESOLVE_EXACT_SQL = """
SELECT m.merchant_id, m.name, m.primary_category, m.country
FROM merchants m
LEFT JOIN merchant_aliases a ON a.merchant_id = m.merchant_id
WHERE m.active = 1
  AND (m.normalized_name = %(q)s OR a.normalized_alias = %(q)s)
LIMIT 1
"""

RESOLVE_SUBSTRING_SQL = """
WITH merchant_keys AS (
  SELECT merchant_id, normalized_name AS key_text FROM merchants WHERE active = 1
  UNION ALL
  SELECT a.merchant_id, a.normalized_alias
  FROM merchant_aliases a JOIN merchants m ON m.merchant_id = a.merchant_id
  WHERE m.active = 1
)
SELECT m.merchant_id, m.name, m.primary_category, m.country
FROM merchant_keys k
JOIN merchants m ON m.merchant_id = k.merchant_id
WHERE CHAR_LENGTH(k.key_text) >= 2
  AND (k.key_text LIKE CONCAT('%%', %(q_like)s, '%%') OR %(q)s LIKE CONCAT('%%', k.key_text, '%%'))
ORDER BY
  CASE WHEN k.key_text LIKE CONCAT(%(q_like)s, '%%') OR %(q)s LIKE CONCAT(k.key_text, '%%')
       THEN 1 ELSE 2 END,
  ABS(CHAR_LENGTH(k.key_text) - CHAR_LENGTH(%(q)s)),
  CHAR_LENGTH(m.name)
LIMIT 1
"""

MERCHANT_BY_ID_SQL = """
SELECT merchant_id, name, primary_category, country
FROM merchants WHERE merchant_id = %(merchant_id)s AND active = 1
"""


def suggest(conn, text, limit=10):
    q = normalize(text)
    if not q:
        return []
    cur = conn.cursor(dictionary=True)
    cur.execute(SUGGEST_SQL, {'q': q, 'q_like': like_escape(q), 'limit': limit})
    return [{'merchant_id': r['merchant_id'], 'name': r['name']} for r in cur.fetchall()]


def _merchant(row):
    if row is None:
        return None
    return Merchant(merchant_id=row['merchant_id'], name=row['name'],
                    category=row['primary_category'], country=row['country'])


def merchant_by_id(conn, merchant_id):
    cur = conn.cursor(dictionary=True)
    cur.execute(MERCHANT_BY_ID_SQL, {'merchant_id': merchant_id})
    return _merchant(cur.fetchone())


def resolve(conn, text):
    """輸入文字 → 一家店或 None。第一層完全相同;沒有且至少 2 個字才做第二層子字串比對。"""
    q = normalize(text)
    if not q:
        return None
    cur = conn.cursor(dictionary=True)
    cur.execute(RESOLVE_EXACT_SQL, {'q': q})
    row = cur.fetchone()
    if row is None and len(q) >= 2:
        cur.execute(RESOLVE_SUBSTRING_SQL, {'q': q, 'q_like': like_escape(q)})
        row = cur.fetchone()
    return _merchant(row)


# ---- 7.3 計算推薦需要的資料 ----

def user_profile(conn, user_id):
    """使用者生日與卡片設定:(birthday, [(card_id, config)])。"""
    cur = conn.cursor(dictionary=True)
    cur.execute('SELECT birthday FROM users WHERE id = %(uid)s', {'uid': user_id})
    user = cur.fetchone()
    if user is None:
        return None, []
    cur.execute('SELECT card_id, config FROM user_cards WHERE user_id = %(uid)s ORDER BY card_id', {'uid': user_id})
    return user['birthday'], [(r['card_id'], json.loads(r['config'])) for r in cur.fetchall()]


def scheme_rows(conn, card_ids, merchant_id):
    """這些卡的所有方案、各 variant 的回饋率、這家店有沒有被點名。"""
    if not card_ids:
        return []
    params = {f'c{i}': cid for i, cid in enumerate(card_ids)}
    params['mid'] = merchant_id
    placeholders = ', '.join(f'%({k})s' for k in params if k != 'mid')
    cur = conn.cursor(dictionary=True)
    cur.execute(f"""
        SELECT s.card_id, s.scheme_name, sr.variant, sr.reward_rate,
               (sm.merchant_id IS NOT NULL) AS is_named, sm.rate_override, sm.notes AS merchant_notes
        FROM card_schemes s
        JOIN scheme_rates sr ON sr.scheme_id = s.scheme_id
        LEFT JOIN scheme_merchants sm ON sm.scheme_id = s.scheme_id AND sm.merchant_id = %(mid)s
        WHERE s.card_id IN ({placeholders})
    """, params)
    return [SchemeRow(
        card_id=r['card_id'],
        scheme_name=r['scheme_name'],
        variant=r['variant'],
        reward_rate=r['reward_rate'],
        is_named=bool(r['is_named']),
        rate_override=r['rate_override'],
        merchant_notes=tuple(json.loads(r['merchant_notes'])) if r['merchant_notes'] else (),
    ) for r in cur.fetchall()]


# ---- 使用者卡片 ----

def list_user_cards(conn, user_id):
    cur = conn.cursor(dictionary=True)
    cur.execute('SELECT card_id, config, updated_at FROM user_cards WHERE user_id = %(uid)s ORDER BY card_id',
                {'uid': user_id})
    return [{'card_id': r['card_id'], 'config': json.loads(r['config'])} for r in cur.fetchall()]


def save_user_card(conn, user_id, card_id, config):
    cur = conn.cursor()
    cur.execute(
        'INSERT INTO user_cards (user_id, card_id, config) VALUES (%(uid)s, %(cid)s, %(cfg)s) '
        'ON DUPLICATE KEY UPDATE config = VALUES(config)',
        {'uid': user_id, 'cid': card_id, 'cfg': json.dumps(config, ensure_ascii=False)})


def delete_user_card(conn, user_id, card_id):
    cur = conn.cursor()
    cur.execute('DELETE FROM user_cards WHERE user_id = %(uid)s AND card_id = %(cid)s',
                {'uid': user_id, 'cid': card_id})
    return cur.rowcount > 0


def pickable_merchants(conn, card_rule):
    """需要挑店的方案中,可以挑的店家(例如 Unicard 百大特店)。"""
    schemes = [name for name, s in card_rule.schemes.items() if s.pick_merchants_when_plan]
    if not schemes:
        return []
    params = {f's{i}': name for i, name in enumerate(schemes)}
    params['cid'] = card_rule.card_id
    placeholders = ', '.join(f'%(s{i})s' for i in range(len(schemes)))
    cur = conn.cursor(dictionary=True)
    cur.execute(f"""
        SELECT DISTINCT m.merchant_id, m.name
        FROM scheme_merchants sm
        JOIN card_schemes s ON s.scheme_id = sm.scheme_id
        JOIN merchants m ON m.merchant_id = sm.merchant_id
        WHERE s.card_id = %(cid)s AND s.scheme_name IN ({placeholders}) AND m.active = 1
        ORDER BY m.name
    """, params)
    return cur.fetchall()


def db_scheme_keys(conn):
    cur = conn.cursor()
    cur.execute('SELECT card_id, scheme_name FROM card_schemes')
    return set(cur.fetchall())
