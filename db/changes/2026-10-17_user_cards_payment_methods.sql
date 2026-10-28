-- v0.5 行動支付:既有的使用者卡片設定補上新欄位(docs/DB_DESIGN.md 6.3)。
--
-- 不改資料表,只更新 user_cards.config(JSON)。可以重複執行:已經有這些欄位的不會被動到。
-- 這是使用者資料,不在 seed.sql 中;每個已經有使用者資料的資料庫各自執行一次。
--
-- 不執行也能運作(後端把缺少的欄位當成空清單),執行後資料庫中的 config 會跟後端儲存的格式一致。
--
-- 執行(專案根目錄):
--   mysql --defaults-extra-file=db/my.local.cnf credit_card_app < db/changes/2026-10-17_user_cards_payment_methods.sql

-- CUBE、Unicard 支援行動支付:補上「有綁定的行動支付」,預設沒有綁定
UPDATE user_cards
SET config = JSON_SET(config, '$.payment_methods', JSON_ARRAY())
WHERE card_id IN ('cathay_cube', 'esun_unicard')
  AND NOT JSON_CONTAINS_PATH(config, 'one', '$.payment_methods');

-- Unicard 任意選:補上「挑選的行動支付」,預設沒有挑
UPDATE user_cards
SET config = JSON_SET(config, '$.chosen_payment_methods', JSON_ARRAY())
WHERE card_id = 'esun_unicard'
  AND JSON_UNQUOTE(JSON_EXTRACT(config, '$.plan')) = '任意選'
  AND NOT JSON_CONTAINS_PATH(config, 'one', '$.chosen_payment_methods');

-- 確認:應該是 0 筆
SELECT COUNT(*) AS cards_missing_new_fields
FROM user_cards
WHERE (card_id IN ('cathay_cube', 'esun_unicard') AND NOT JSON_CONTAINS_PATH(config, 'one', '$.payment_methods'))
   OR (card_id = 'esun_unicard' AND JSON_UNQUOTE(JSON_EXTRACT(config, '$.plan')) = '任意選'
       AND NOT JSON_CONTAINS_PATH(config, 'one', '$.chosen_payment_methods'));
