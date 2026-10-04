-- credit_card_app 資料表 v3(對應 docs/DB_DESIGN.md v0.4 第 4 節)
--
-- 8 張表:店家(3)、爬蟲回饋資料(3)、使用者(2)。卡片規則不在資料庫,在 backend/cards.yaml。
-- card_rewards(Allen 的舊扁平表)不在這裡,仍由 schema.sql 建立,app.py 換到新後端後移除。
--
-- 新機器:
--   mysql --defaults-extra-file=scripts/mysql/my.local.cnf -e "source scripts/mysql/schema_v3.sql"
-- 已有 v2 資料表的機器:用 python -m backend.migrate_v3,它會先移除 v2 的表再執行本檔。

CREATE DATABASE IF NOT EXISTS credit_card_app
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE credit_card_app;

-- ---------------------------------------------------------------------------
-- 店家(4.3、4.4)
-- ---------------------------------------------------------------------------
CREATE TABLE merchants (
  merchant_id      INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  name             VARCHAR(255)  NOT NULL,
  normalized_name  VARCHAR(255)  AS (LOWER(REPLACE(REPLACE(TRIM(name), ' ', ''), '　', ''))) STORED,
  primary_category VARCHAR(50)   NOT NULL,
  country          VARCHAR(10)   NOT NULL,   -- TW / JP / global;不是 TW 就算國外
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
  alias            VARCHAR(100)  NOT NULL,
  normalized_alias VARCHAR(100)  AS (LOWER(REPLACE(REPLACE(TRIM(alias), ' ', ''), '　', ''))) STORED,
  PRIMARY KEY (merchant_id, alias),
  KEY idx_normalized_alias (normalized_alias),
  FOREIGN KEY (merchant_id) REFERENCES merchants (merchant_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE merchant_source_names (
  source_name  VARCHAR(255)  CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,  -- 爬蟲原始字串,逐字元比對
  merchant_id  INT UNSIGNED  NOT NULL,
  created_at   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (source_name),
  KEY idx_merchant (merchant_id),
  FOREIGN KEY (merchant_id) REFERENCES merchants (merchant_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- 爬蟲回饋資料(4.5)
-- ---------------------------------------------------------------------------
CREATE TABLE card_schemes (
  scheme_id    INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  card_id      VARCHAR(32)   NOT NULL,   -- 對應 cards.yaml,沒有外鍵
  scheme_name  VARCHAR(50)   NOT NULL,
  PRIMARY KEY (scheme_id),
  UNIQUE KEY uq_card_scheme (card_id, scheme_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE scheme_rates (
  scheme_id   INT UNSIGNED  NOT NULL,
  variant     VARCHAR(50)   NOT NULL DEFAULT '',   -- CUBE 存等級、Unicard 存方案、吉鶴卡存 ''
  reward_rate DECIMAL(5,2)  NOT NULL,
  PRIMARY KEY (scheme_id, variant),
  FOREIGN KEY (scheme_id) REFERENCES card_schemes (scheme_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE scheme_merchants (
  scheme_id     INT UNSIGNED  NOT NULL,
  merchant_id   INT UNSIGNED  NOT NULL,
  rate_override DECIMAL(5,2)  NULL,
  notes         JSON          NULL,
  PRIMARY KEY (scheme_id, merchant_id),
  KEY idx_merchant (merchant_id),
  FOREIGN KEY (scheme_id)   REFERENCES card_schemes (scheme_id),
  FOREIGN KEY (merchant_id) REFERENCES merchants (merchant_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- 使用者(4.6)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
  id            INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  email         VARCHAR(255)  NOT NULL,
  password_hash VARCHAR(255)  NOT NULL,
  full_name     VARCHAR(100)  NOT NULL,
  birthday      DATE          NOT NULL,
  created_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE user_cards (
  user_id    INT UNSIGNED  NOT NULL,
  card_id    VARCHAR(32)   NOT NULL,   -- 對應 cards.yaml,沒有外鍵
  config     JSON          NOT NULL,
  created_at TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, card_id),
  FOREIGN KEY (user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
