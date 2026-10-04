-- credit_card_app 資料庫結構
--
-- 對應 Allen 的 app.py：DB_CONFIG 裡指定 database='credit_card_app'、charset='utf8mb4'，
-- /api/search_rewards 查 card_rewards、/api/register 與 /api/login 查 users。
--
-- 執行方式（Windows，MySQL 8.0 已安裝於 C:\Program Files\MySQL\MySQL Server 8.0）：
--   mysql --defaults-extra-file=scripts/mysql/my.local.cnf < scripts/mysql/schema.sql
--
-- 這支 script 可重複執行（全部用 IF NOT EXISTS，不會刪掉既有資料）。

CREATE DATABASE IF NOT EXISTS credit_card_app
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE credit_card_app;

-- ---------------------------------------------------------------------------
-- card_rewards：Allen 爬蟲匯出的回饋資料，欄位與 card_rewards_export_0908.csv 完全一致。
-- 這張表是「衍生資料」——內容完全來自匯出檔，由 build_seed_sql.js 重新產生，
-- 不要直接手動改這裡的資料，改了下次重灌就會被蓋掉。
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS card_rewards (
  -- 沿用匯出檔原本的 id，方便日後跟 Allen 那邊的資料庫對帳
  id            INT UNSIGNED  NOT NULL,
  bank_name     VARCHAR(50)   NOT NULL,
  card_name     VARCHAR(50)   NOT NULL,
  -- CUBE卡 是 'Level 1'/'Level 2'/'Level 3'，Unicard 是 '簡單選'/'任意選'/'UP選'，
  -- 沒有分等級的卡（吉鶴卡）統一是 'Standard'——app.py 就是這樣預設的
  card_level    VARCHAR(50)   NOT NULL,
  scheme_name   VARCHAR(50)   NOT NULL,
  merchant_name VARCHAR(255)  NOT NULL,
  -- 目前資料最多 1 位小數、最大值 10，DECIMAL(5,2) 綽綽有餘且不會有浮點誤差
  reward_rate   DECIMAL(5,2)  NOT NULL,
  updated_at    DATETIME      NOT NULL,
  PRIMARY KEY (id),
  -- app.py 的 WHERE 有 (card_name = ? AND card_level = ?)，這個索引吃得到
  KEY idx_card_lookup (card_name, card_level)
  -- 注意：app.py 用 merchant_name LIKE '%關鍵字%'，前面有萬用字元，
  -- 一般 BTREE 索引幫不上忙，所以這裡不放 merchant_name 索引。
  -- 目前只有 1236 筆，全表掃描完全無感；資料量長大再考慮 FULLTEXT 或改查詢寫法。
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- users：app.py 的 /api/register 與 /api/login 會用到。
-- 帳號登入功能目前是擱置狀態（iOS UI 還沒接），但少了這張表 app.py 一啟動打那兩支 API 就會 500，
-- 所以先把結構建起來，內容留空。
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
  id            INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  email         VARCHAR(255)  NOT NULL,
  -- werkzeug 的 generate_password_hash 產出的字串，長度會隨演算法變動，留寬一點
  password_hash VARCHAR(255)  NOT NULL,
  full_name     VARCHAR(100)  NOT NULL,
  birthday      DATE          NOT NULL,
  created_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  -- app.py 靠 IntegrityError 判斷「這個 Email 已經被註冊過」，要有 UNIQUE 才會丟那個錯
  UNIQUE KEY uq_users_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- 商家目錄、回饋方案、使用者卡片等新版資料表在 schema_v2.sql(docs/DB_DESIGN.md)。
-- 舊版的 merchants / merchant_aliases / merchant_tags 已移出本檔:它們與新版
-- 同名但結構不同,留在這裡會讓新機器先建出舊表,schema_v2.sql 就建不起來。
-- ---------------------------------------------------------------------------
