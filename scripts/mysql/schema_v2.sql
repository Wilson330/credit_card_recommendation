-- credit_card_app 新版資料表(對應 docs/DB_DESIGN.md v0.2 第 3 節)
--
-- 只建立新設計的資料表,不動 card_rewards 與 users(app.py 仍在使用)。
-- 執行前,舊版的 merchants / merchant_aliases / merchant_tags 必須先改名或移除,
-- 因為新表與舊表同名但結構不同,見 scripts/mysql/README.md 的「v2 資料表」一節。
--
-- 執行方式:
--   mysql --defaults-extra-file=scripts/mysql/my.local.cnf < scripts/mysql/schema_v2.sql
--
-- 與 DB_DESIGN.md 的 DDL 相同,另外統一加上 ENGINE / CHARSET,
-- 以及 merchant_source_names.source_name 使用 utf8mb4_bin(見該表註解)。

USE credit_card_app;

-- ---------------------------------------------------------------------------
-- 卡片與方案(3.4)
-- ---------------------------------------------------------------------------
CREATE TABLE cards (
  card_id    VARCHAR(32)  NOT NULL,   -- 'cathay_cube'
  bank_name  VARCHAR(50)  NOT NULL,   -- '國泰世華'
  card_name  VARCHAR(50)  NOT NULL,   -- 'CUBE卡',必須與爬蟲資料的 card_name 一致
  active     TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (card_id),
  UNIQUE KEY uq_card_name (card_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE card_schemes (
  scheme_id          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  card_id            VARCHAR(32)   NOT NULL,
  scheme_name        VARCHAR(50)   NOT NULL,   -- '樂饗購',一般方案須與爬蟲的 scheme_name 一致
  is_default         TINYINT(1)    NOT NULL DEFAULT 0,  -- 1 = 一般消費類,適用所有店家
  required_action    VARCHAR(100)  NULL,       -- '需切換至樂饗購權益方案'
  required_condition VARCHAR(50)   NULL,       -- 'kids_club'、'new_customer';NULL = 無條件
  notes              JSON          NULL,       -- 方案層級的限制說明,字串陣列
  active             TINYINT(1)    NOT NULL DEFAULT 1,
  PRIMARY KEY (scheme_id),
  UNIQUE KEY uq_card_scheme (card_id, scheme_name),
  FOREIGN KEY (card_id) REFERENCES cards (card_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- 方案的回饋率(3.5)
-- ---------------------------------------------------------------------------
CREATE TABLE scheme_rates (
  scheme_id   INT UNSIGNED  NOT NULL,
  card_level  VARCHAR(50)   NOT NULL,   -- 照爬蟲寫法:'Level 2'、'簡單選'、'Standard'
  reward_rate DECIMAL(5,2)  NOT NULL,
  PRIMARY KEY (scheme_id, card_level),
  FOREIGN KEY (scheme_id) REFERENCES card_schemes (scheme_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- 店家(3.6 ~ 3.8)
-- ---------------------------------------------------------------------------
CREATE TABLE merchants (
  merchant_id      INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  name             VARCHAR(255)  NOT NULL,   -- 顯示名稱,也是搜尋比對的主名稱
  normalized_name  VARCHAR(255)  AS (LOWER(REPLACE(REPLACE(TRIM(name), ' ', ''), '　', ''))) STORED,
  primary_category VARCHAR(50)   NOT NULL,   -- 方案的分類涵蓋比對這欄
  country          CHAR(2)       NOT NULL,   -- TW / JP
  active           TINYINT(1)    NOT NULL DEFAULT 1,
  created_at       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (merchant_id),
  UNIQUE KEY uq_merchant_name (name),
  KEY idx_normalized_name (normalized_name),
  KEY idx_category (primary_category)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE merchant_aliases (
  merchant_id      INT UNSIGNED  NOT NULL,
  alias            VARCHAR(100)  NOT NULL,   -- '小七'、'KFC'
  normalized_alias VARCHAR(100)  AS (LOWER(REPLACE(REPLACE(TRIM(alias), ' ', ''), '　', ''))) STORED,
  PRIMARY KEY (merchant_id, alias),
  KEY idx_normalized_alias (normalized_alias),
  FOREIGN KEY (merchant_id) REFERENCES merchants (merchant_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE merchant_source_names (
  -- 爬蟲原始字串,一字不改。用 utf8mb4_bin(逐字元精確比對):預設的 unicode_ci
  -- 不分大小寫,會把只差大小寫的兩個原名當成同一個,違反「改一個字就要人確認」的設計
  source_name  VARCHAR(255)  CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
  merchant_id  INT UNSIGNED  NOT NULL,
  created_at   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (source_name),
  KEY idx_merchant (merchant_id),
  FOREIGN KEY (merchant_id) REFERENCES merchants (merchant_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- 方案的涵蓋範圍(3.5),需要 card_schemes 與 merchants 先存在
-- ---------------------------------------------------------------------------
CREATE TABLE scheme_merchants (
  scheme_id     INT UNSIGNED  NOT NULL,
  merchant_id   INT UNSIGNED  NOT NULL,
  rate_override DECIMAL(5,2)  NULL,      -- NULL = 用方案在該等級的回饋率
  notes         JSON          NULL,      -- 店家層級的限制,例:["限本島"]
  PRIMARY KEY (scheme_id, merchant_id),
  KEY idx_merchant (merchant_id),
  FOREIGN KEY (scheme_id)   REFERENCES card_schemes (scheme_id),
  FOREIGN KEY (merchant_id) REFERENCES merchants (merchant_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE scheme_categories (
  scheme_id INT UNSIGNED  NOT NULL,
  category  VARCHAR(50)   NOT NULL,      -- 對應 merchants.primary_category
  PRIMARY KEY (scheme_id, category),
  KEY idx_category (category),
  FOREIGN KEY (scheme_id) REFERENCES card_schemes (scheme_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- 使用者卡片(3.9)【待確認:登入設計】,需要 users 先存在(schema.sql 建立)
-- ---------------------------------------------------------------------------
CREATE TABLE user_cards (
  user_id    INT UNSIGNED  NOT NULL,
  card_id    VARCHAR(32)   NOT NULL,
  card_level VARCHAR(50)   NOT NULL,   -- 照 3.3 的規則;吉鶴卡為 'Standard'
  created_at TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, card_id),
  FOREIGN KEY (user_id) REFERENCES users (id),
  FOREIGN KEY (card_id) REFERENCES cards (card_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE user_card_conditions (
  user_id       INT UNSIGNED  NOT NULL,
  card_id       VARCHAR(32)   NOT NULL,
  condition_key VARCHAR(50)   NOT NULL,
  PRIMARY KEY (user_id, card_id, condition_key),
  FOREIGN KEY (user_id, card_id) REFERENCES user_cards (user_id, card_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
