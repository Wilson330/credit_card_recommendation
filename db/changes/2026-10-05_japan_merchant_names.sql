-- 2026-10-05 日本店家名稱加上「日本」,台灣門市補英文別名
--
-- 原因:搜尋 7-ELEVEN、FamilyMart 時,名稱較短的日本店排在台灣門市前面,直接搜尋也會對到日本的店。
-- 已套用在 Wilson 的開發機,db/seed.sql 已包含這些修改;已有資料庫的機器執行本檔即可。可重複執行。

UPDATE merchants SET name = CONCAT('日本 ', name)
WHERE country = 'JP'
  AND name IN ('7-ELEVEN', 'BIC CAMERA', 'FamilyMart', 'ICOCA', 'LAWSON', 'PASMO', 'SUICA', 'Yodobashi');

UPDATE merchants SET name = CONCAT('日本', name)
WHERE country = 'JP'
  AND name IN ('三越', '唐吉訶德', '永旺', '高島屋');

INSERT INTO merchant_aliases (merchant_id, alias)
SELECT merchant_id, 'FamilyMart' FROM merchants
WHERE name = '全家便利商店 實體門市' AND country = 'TW'
  AND NOT EXISTS (SELECT 1 FROM merchant_aliases WHERE alias = 'FamilyMart');

INSERT INTO merchant_aliases (merchant_id, alias)
SELECT merchant_id, '711' FROM merchants
WHERE name = '7-ELEVEN (7-11) 實體門市' AND country = 'TW'
  AND NOT EXISTS (SELECT 1 FROM merchant_aliases WHERE alias = '711');
