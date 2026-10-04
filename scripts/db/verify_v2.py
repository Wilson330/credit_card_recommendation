#!/usr/bin/env python3
"""
驗證 v2 資料表的內容與查詢邏輯(docs/DB_DESIGN.md 第 8 節的驗證案例)。

用的是 DB_DESIGN.md 第 4 節的 SQL,所以同時也在驗證文件裡的查詢寫得對不對。
測試用的使用者與卡片在交易內建立,跑完一律 rollback,不會留在資料庫。

用法:python scripts/db/verify_v2.py
"""

import sys

from migrate_v2 import connect, normalize

# ---- DB_DESIGN.md 4.1 自動補全 ----
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
  AND (m.normalized_name LIKE CONCAT('%%', %(q_like)s, '%%') OR a.normalized_alias LIKE CONCAT('%%', %(q_like)s, '%%'))
GROUP BY m.merchant_id, m.name
ORDER BY match_rank, CHAR_LENGTH(m.name)
LIMIT 10
"""

# ---- DB_DESIGN.md 4.2 確定店家 ----
RESOLVE_EXACT_SQL = """
SELECT m.merchant_id, m.name, m.primary_category
FROM merchants m
LEFT JOIN merchant_aliases a ON a.merchant_id = m.merchant_id
WHERE m.active = 1
  AND (m.normalized_name = %(q)s OR a.normalized_alias = %(q)s)
LIMIT 1
"""

RESOLVE_SUBSTRING_SQL = """
SELECT m.merchant_id, m.name, m.primary_category
FROM merchants m
LEFT JOIN merchant_aliases a ON a.merchant_id = m.merchant_id
WHERE m.active = 1
  AND (   m.normalized_name LIKE CONCAT('%%', %(q_like)s, '%%')
       OR a.normalized_alias LIKE CONCAT('%%', %(q_like)s, '%%')
       OR (CHAR_LENGTH(m.normalized_name)  >= 2 AND %(q)s LIKE CONCAT('%%', m.normalized_name,  '%%'))
       OR (CHAR_LENGTH(a.normalized_alias) >= 2 AND %(q)s LIKE CONCAT('%%', a.normalized_alias, '%%')))
ORDER BY CHAR_LENGTH(m.name)
LIMIT 1
"""

# ---- DB_DESIGN.md 4.3 計算各卡最佳回饋 ----
RECOMMEND_SQL = """
WITH candidates AS (
  SELECT uc.card_id, uc.card_level,
         s.scheme_name, s.required_action, s.notes AS scheme_notes, sm.notes AS merchant_notes,
         COALESCE(sm.rate_override, sr.reward_rate)   AS reward_rate,
         CASE WHEN s.is_default = 1 THEN 2 ELSE 1 END AS tier,
         (sm.merchant_id IS NOT NULL)                 AS is_named
  FROM user_cards uc
  JOIN card_schemes s
    ON  s.card_id = uc.card_id
    AND s.active  = 1
  JOIN scheme_rates sr
    ON  sr.scheme_id  = s.scheme_id
    AND sr.card_level = uc.card_level
  LEFT JOIN scheme_merchants sm
    ON  sm.scheme_id   = s.scheme_id
    AND sm.merchant_id = %(merchant_id)s
  LEFT JOIN scheme_categories sc
    ON  sc.scheme_id = s.scheme_id
    AND sc.category  = %(merchant_category)s
  WHERE uc.user_id = %(user_id)s
    AND (s.required_condition IS NULL OR EXISTS (
          SELECT 1 FROM user_card_conditions c
          WHERE c.user_id = uc.user_id
            AND c.card_id = uc.card_id
            AND c.condition_key = s.required_condition))
    AND (s.is_default = 1 OR sm.merchant_id IS NOT NULL OR sc.category IS NOT NULL)
),
best AS (
  SELECT *,
         ROW_NUMBER() OVER (
           PARTITION BY card_id
           ORDER BY tier, reward_rate DESC, is_named DESC
         ) AS rn
  FROM candidates
)
SELECT b.card_id, c.bank_name, c.card_name, b.card_level,
       b.reward_rate, b.scheme_name, b.required_action, b.scheme_notes, b.merchant_notes
FROM best b
JOIN cards c ON c.card_id = b.card_id AND c.active = 1
WHERE b.rn = 1
ORDER BY b.reward_rate DESC, c.card_name
LIMIT 3
"""

# ---- DB_DESIGN.md 4.5 卡片設定選項 ----
LEVEL_OPTIONS_SQL = """
SELECT DISTINCT sr.card_level
FROM scheme_rates sr
JOIN card_schemes s ON s.scheme_id = sr.scheme_id
WHERE s.card_id = %(card_id)s AND s.active = 1
"""


def like_escape(s):
    return s.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_')


class Verifier:
    def __init__(self, conn):
        self.conn = conn
        self.cur = conn.cursor(dictionary=True)
        self.passed = 0
        self.failed = 0

    def q(self, sql, **params):
        self.cur.execute(sql, params)
        return self.cur.fetchall()

    def check(self, label, ok, detail=''):
        if ok:
            self.passed += 1
            print(f'  PASS  {label}')
        else:
            self.failed += 1
            print(f'  FAIL  {label}  {detail}')

    # -- 查詢流程 --

    def suggest(self, text):
        n = normalize(text)
        return [r['name'] for r in self.q(SUGGEST_SQL, q=n, q_like=like_escape(n))]

    def resolve(self, text):
        n = normalize(text)
        rows = self.q(RESOLVE_EXACT_SQL, q=n)
        if not rows and len(n) >= 2:
            rows = self.q(RESOLVE_SUBSTRING_SQL, q=n, q_like=like_escape(n))
        return rows[0] if rows else None

    def recommend(self, user_id, text):
        merchant = self.resolve(text)
        rows = self.q(
            RECOMMEND_SQL,
            user_id=user_id,
            merchant_id=merchant['merchant_id'] if merchant else None,
            merchant_category=merchant['primary_category'] if merchant else None,
        )
        return merchant, {r['card_id']: r for r in rows}

    # -- 測試資料 --

    def make_user(self, cards, conditions=()):
        self.user_seq = getattr(self, 'user_seq', 0) + 1
        self.cur.execute(
            "INSERT INTO users (email, password_hash, full_name, birthday) VALUES (%s, 'x', '驗證用', '2000-01-01')",
            (f'verify-{self.user_seq}@test.local',))
        uid = self.cur.lastrowid
        for card_id, level in cards.items():
            self.cur.execute(
                'INSERT INTO user_cards (user_id, card_id, card_level) VALUES (%s, %s, %s)', (uid, card_id, level))
        for card_id, key in conditions:
            self.cur.execute(
                'INSERT INTO user_card_conditions (user_id, card_id, condition_key) VALUES (%s, %s, %s)',
                (uid, card_id, key))
        return uid


def rate(result, card_id):
    r = result.get(card_id)
    return float(r['reward_rate']) if r else None


def scheme(result, card_id):
    r = result.get(card_id)
    return r['scheme_name'] if r else None


def run(v):
    all_cards_l2 = {'cathay_cube': 'Level 2', 'ubot_jiho': 'Standard', 'esun_unicard': '簡單選'}
    u = v.make_user(all_cards_l2)
    u_kids = v.make_user({'cathay_cube': 'Level 2'}, [('cathay_cube', 'kids_club')])
    u_l1 = v.make_user({'cathay_cube': 'Level 1'})
    u_l3 = v.make_user({'cathay_cube': 'Level 3'})
    u_up = v.make_user({'esun_unicard': 'UP選'})
    u_debit = v.make_user({'esun_unicard': '簡單選'}, [('esun_unicard', 'auto_debit')])

    print('\n[分類涵蓋]')
    m, res = v.recommend(u, '藏壽司')
    v.check('藏壽司 解析成功', m is not None and m['name'] == '藏壽司', m)
    v.check('藏壽司 CUBE Level 2 → 樂饗購 3%(分類涵蓋)',
            rate(res, 'cathay_cube') == 3.0 and scheme(res, 'cathay_cube') == '樂饗購', res.get('cathay_cube'))

    m, res = v.recommend(u, '鼎泰豐')
    v.check('鼎泰豐 CUBE Level 2 → 樂饗購 3%', rate(res, 'cathay_cube') == 3.0, res.get('cathay_cube'))

    print('\n[別名]')
    for alias in ('小七', '統一超商'):
        m, res = v.recommend(u, alias)
        v.check(f'{alias} 解析為台灣 7-11',
                m is not None and m['name'] == '7-ELEVEN (7-11) 實體門市', m)
        v.check(f'{alias} CUBE 拿到點名方案 2%,不是一般消費',
                rate(res, 'cathay_cube') == 2.0 and scheme(res, 'cathay_cube') != '一般消費', res.get('cathay_cube'))

    print('\n[條件:童樂匯]')
    kids_store = v.q("""
        SELECT m.name, sm.rate_override FROM scheme_merchants sm
        JOIN card_schemes s ON s.scheme_id = sm.scheme_id
        JOIN merchants m ON m.merchant_id = sm.merchant_id
        WHERE s.scheme_name = '童樂匯' AND m.name = '麗寶樂園'""")
    v.check('麗寶樂園 在童樂匯名單中', len(kids_store) == 1, kids_store)
    _, res = v.recommend(u, '麗寶樂園')
    v.check('麗寶樂園 未加入童樂匯 → 不是童樂匯', scheme(res, 'cathay_cube') != '童樂匯', res.get('cathay_cube'))
    _, res = v.recommend(u_kids, '麗寶樂園')
    v.check('麗寶樂園 已加入童樂匯 → 童樂匯', scheme(res, 'cathay_cube') == '童樂匯', res.get('cathay_cube'))

    print('\n[例外回饋率]')
    exc = v.q("""
        SELECT m.name, sm.rate_override FROM scheme_merchants sm
        JOIN card_schemes s ON s.scheme_id = sm.scheme_id
        JOIN merchants m ON m.merchant_id = sm.merchant_id
        WHERE s.scheme_name = '童樂匯' AND sm.rate_override = 10 LIMIT 1""")
    if exc:
        _, res = v.recommend(u_kids, exc[0]['name'])
        v.check(f'{exc[0]["name"]}(童樂匯例外店)→ 10%,不是方案的 5%',
                rate(res, 'cathay_cube') == 10.0, res.get('cathay_cube'))
    else:
        v.check('找到童樂匯 10% 例外店', False)

    print('\n[等級]')
    _, r1 = v.recommend(u_l1, '誠品生活')
    _, r3 = v.recommend(u_l3, '誠品生活')
    v.check('誠品生活 CUBE Level 1 → 2%、Level 3 → 3.3%',
            rate(r1, 'cathay_cube') == 2.0 and rate(r3, 'cathay_cube') == 3.3,
            (rate(r1, 'cathay_cube'), rate(r3, 'cathay_cube')))
    _, rs = v.recommend(u, '台北101')
    _, ru = v.recommend(u_up, '台北101')
    v.check('台北101 Unicard 簡單選 → 2%、UP選 → 3.5%',
            rate(rs, 'esun_unicard') == 2.0 and rate(ru, 'esun_unicard') == 3.5,
            (rate(rs, 'esun_unicard'), rate(ru, 'esun_unicard')))

    print('\n[找不到店家]')
    m, res = v.recommend(u, '完全不存在的店家xyz')
    v.check('解析結果為找不到', m is None, m)
    v.check('各卡一般消費:CUBE 0.3%、吉鶴卡 1%、Unicard 0.3%',
            (rate(res, 'cathay_cube'), rate(res, 'ubot_jiho'), rate(res, 'esun_unicard')) == (0.3, 1.0, 0.3),
            {k: rate(res, k) for k in res})
    _, res = v.recommend(u_debit, '完全不存在的店家xyz')
    v.check('Unicard 有自動扣繳 → 1%', rate(res, 'esun_unicard') == 1.0, res.get('esun_unicard'))

    print('\n[自動補全與設定選項]')
    v.check('打「藏」的建議清單有藏壽司', '藏壽司' in v.suggest('藏'), v.suggest('藏'))
    v.check('打「小七」第一個建議是台灣 7-11',
            v.suggest('小七')[:1] == ['7-ELEVEN (7-11) 實體門市'], v.suggest('小七'))
    levels = sorted(r['card_level'] for r in v.q(LEVEL_OPTIONS_SQL, card_id='cathay_cube'))
    v.check('CUBE 可選等級為 Level 1/2/3', levels == ['Level 1', 'Level 2', 'Level 3'], levels)
    v.check('level_1 不是合法等級', 'level_1' not in levels)


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    conn = connect()
    v = Verifier(conn)
    try:
        run(v)
    finally:
        conn.rollback()  # 測試資料一律不保留
        conn.close()
    print(f'\n結果:{v.passed} 通過,{v.failed} 失敗')
    sys.exit(1 if v.failed else 0)


if __name__ == '__main__':
    main()
