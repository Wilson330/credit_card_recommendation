-- 範例:CUBE Level 2、未加入童樂匯的使用者查「鼎泰豐」
-- 對應 docs/DB_DESIGN.md 4.2(確定店家)與 4.3(計算各卡最佳回饋)。
--
-- 執行(PowerShell,在專案根目錄):
--   & $MYSQL $CNF --table -e "source scripts/mysql/examples/recommend_example.sql"
--
-- 推薦計算需要 user_cards,但登入功能還沒做,所以在交易內建立一個暫時的使用者,
-- 最後 ROLLBACK,不會在資料庫留下任何資料。
-- 想試其他店,改下面的 @q;想試其他等級,改 user_cards 那段。

USE credit_card_app;
-- 連線定序要跟資料表一致(utf8mb4_unicode_ci)。MySQL 8 的預設是 utf8mb4_0900_ai_ci,
-- 拿 @變數 跟欄位比較時會出現 "Illegal mix of collations" 錯誤
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;
START TRANSACTION;

-- ---------------------------------------------------------------------------
-- 1. 暫時的使用者:持有 CUBE(Level 2)、吉鶴卡、Unicard(簡單選),沒有勾任何條件
-- ---------------------------------------------------------------------------
INSERT INTO users (email, password_hash, full_name, birthday)
VALUES ('example@test.local', 'x', '範例使用者', '2000-01-01');
SET @user_id = LAST_INSERT_ID();

INSERT INTO user_cards (user_id, card_id, card_level) VALUES
  (@user_id, 'cathay_cube',  'Level 2'),
  (@user_id, 'ubot_jiho',    'Standard'),
  (@user_id, 'esun_unicard', '簡單選');

-- ---------------------------------------------------------------------------
-- 2. 確定店家(4.2 第一層:正規化後的名稱或別名完全相同)
--    @q 應為正規化後的輸入(去空白、轉小寫),實際由後端處理。
-- ---------------------------------------------------------------------------
SET @q = '鼎泰豐';

SET @merchant_id = NULL, @merchant_category = NULL;
SELECT m.merchant_id, m.primary_category
  INTO @merchant_id, @merchant_category
FROM merchants m
LEFT JOIN merchant_aliases a ON a.merchant_id = m.merchant_id
WHERE m.active = 1
  AND (m.normalized_name = @q OR a.normalized_alias = @q)
LIMIT 1;

SELECT '步驟 2:確定店家' AS step, @q AS 輸入, @merchant_id AS merchant_id, @merchant_category AS 分類;

-- ---------------------------------------------------------------------------
-- 3. 中間過程:每張卡有哪些方案適用這家店(4.3 的 candidates)
--    這一步只是為了看懂 JOIN 在做什麼,實際 API 只需要第 4 步。
-- ---------------------------------------------------------------------------
SELECT '步驟 3:各卡適用的方案' AS step,
       c.card_name AS 卡片,
       uc.card_level AS 等級,
       s.scheme_name AS 方案,
       CASE
         WHEN s.is_default = 1           THEN '一般消費類'
         WHEN sm.merchant_id IS NOT NULL THEN '店家被點名'
         ELSE CONCAT('分類 ', sc.category, ' 被涵蓋')
       END AS 適用原因,
       CASE WHEN s.is_default = 1 THEN 2 ELSE 1 END AS 層,
       COALESCE(sm.rate_override, sr.reward_rate) AS 回饋率
FROM user_cards uc
JOIN cards c         ON c.card_id = uc.card_id
JOIN card_schemes s  ON s.card_id = uc.card_id AND s.active = 1
JOIN scheme_rates sr ON sr.scheme_id = s.scheme_id AND sr.card_level = uc.card_level
LEFT JOIN scheme_merchants  sm ON sm.scheme_id = s.scheme_id AND sm.merchant_id = @merchant_id
LEFT JOIN scheme_categories sc ON sc.scheme_id = s.scheme_id AND sc.category    = @merchant_category
WHERE uc.user_id = @user_id
  AND (s.required_condition IS NULL OR EXISTS (
        SELECT 1 FROM user_card_conditions cc
        WHERE cc.user_id = uc.user_id AND cc.card_id = uc.card_id
          AND cc.condition_key = s.required_condition))
  AND (s.is_default = 1 OR sm.merchant_id IS NOT NULL OR sc.category IS NOT NULL)
ORDER BY c.card_name, 層, 回饋率 DESC;

-- ---------------------------------------------------------------------------
-- 4. 最終推薦(4.3,與 DB_DESIGN.md 中的 SQL 相同)
--    每張卡只留最好的一筆,卡片之間依回饋率排序,取前 3 名
-- ---------------------------------------------------------------------------
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
    AND sm.merchant_id = @merchant_id
  LEFT JOIN scheme_categories sc
    ON  sc.scheme_id = s.scheme_id
    AND sc.category  = @merchant_category
  WHERE uc.user_id = @user_id
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
SELECT '步驟 4:推薦結果' AS step,
       c.card_name AS 卡片, b.card_level AS 等級,
       b.reward_rate AS 回饋率, b.scheme_name AS 方案, b.required_action AS 要做的動作
FROM best b
JOIN cards c ON c.card_id = b.card_id AND c.active = 1
WHERE b.rn = 1
ORDER BY b.reward_rate DESC, c.card_name
LIMIT 3;

ROLLBACK;
