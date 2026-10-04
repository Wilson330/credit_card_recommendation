# 資料庫與推薦邏輯設計

> 內容整理自與 Wilson 的討論。實作完成後,要逐節對照程式碼確認一致;
> 對不上的地方以「改文件或改程式」二擇一處理,不讓兩者分歧。
>
> 目前沒有未定案的項目;需要請 Allen 確認或通知 Allen 的事情列在最後一節。

### 修改紀錄

| 版本 | 內容 |
|---|---|
| v0.4 | 新增登入與 token(第 5 節);一般消費可依店家國內外分層,CUBE 海外 2.5%、吉鶴卡日本 2.5%;每張卡改為「方案與一般消費一起比,取最高」;吉鶴卡改用卡片層級加碼(新戶自動扣繳 +0.5%,只加在國內一般消費與國內日系特店),爬蟲數字視為已含基本回饋;分類涵蓋可限國別(樂饗購限國內;趣旅行涵蓋飯店、旅行類與所有國外的店);任意選最多 8 家;慶生月需切換方案;開關有顯示名稱;55688 併入台灣大車隊;`users` 定義定案;`merchants.country` 放寬為 `VARCHAR(10)`,可填 `global`;模糊比對第二層改依命中程度排序;token 有效期 30 天;待確認事項全部定案 |
| v0.3 | 推薦計算改為「SQL 撈資料 + 後端 Python 判斷」;卡片規則改寫在 `cards.yaml`;使用者卡片設定改存 `user_cards.config`(JSON);`scheme_rates.card_level` 改名 `variant`;一般消費改由 `cards.yaml` 維護。移除 `cards`、`scheme_categories`、`user_card_conditions`,`card_schemes` 瘦身 |
| v0.2 | 回饋規則從單一 `reward_rules` 表改為 `card_schemes` + `scheme_rates` + `scheme_merchants` + `scheme_categories`;移除 `card_levels`、`merchant_source_pending` |
| v0.1 | 初稿 |

### 實作狀態

本機資料庫目前是 **v0.2 的結構**(`scripts/mysql/schema_v2.sql`,由 `scripts/db/migrate_v2.py` 灌入資料)。v0.3 起的改動尚未實作,實作步驟見第 10 節。

---

## 1. 目標與範圍

- **MySQL 是爬蟲資料與使用者資料的唯一來源**:哪些店、在哪個方案、回饋幾 %;使用者的帳號與卡片設定
- **`cards.yaml` 是卡片規則的唯一來源**:要什麼條件、會不會疊加、要不要挑店、要做什麼動作、一般消費幾 %。後端啟動時直接讀取
- **推薦計算在後端完成**:SQL 負責搜尋與撈資料,Python 依 `cards.yaml` 判斷規則。App 只送請求、顯示結果

不在本文件範圍:App 的 UI。

---

## 2. 整體架構

```
                         ┌──────────────────────────────────────┐
  App(Allen 的 iOS UI)  │  後端(Python / Flask)                │
  ─────────────────────  │  ──────────────────────────────────  │
  註冊 / 登入 ───────────►│  發 token、驗證 token                │
  輸入店名 ──────────────►│  自動補全、確定店家      ── SQL ────►│ MySQL
  點選建議 / 按搜尋 ─────►│  計算推薦(Python)                  │ (爬蟲資料、
  卡片設定 ──────────────►│  讀寫使用者卡片設定                  │  使用者資料)
  本地:token、我的設定副本 │  提供卡片設定選項                    │
       卡片選項快取       └──────────────────────────────────────┘
                                   ▲ 啟動時讀取            ▲
                              cards.yaml          匯入腳本 ◄── 爬蟲匯出檔
                              (卡片規則)          (也讀 cards.yaml 對照卡片與方案)
```

---

## 3. 資料分工

| 放哪裡 | 放什麼 | 怎麼變動 |
|---|---|---|
| **資料庫** | 爬蟲來的資料(店家、方案點名的店、各等級回饋率)、使用者資料 | 匯入腳本、使用者操作 |
| **`cards.yaml`** | 人定的規則(條件、疊加、加碼、挑店、要做的動作、分類涵蓋、一般消費) | 人改檔案、重啟後端 |
| **手機** | 登入 token、使用者自己的卡片設定副本、卡片設定選項的快取 | 從後端同步,不自行計算 |

判斷一個資訊放哪裡的原則:**SQL 要拿來搜尋或 JOIN 的,用資料表的一般欄位;只有 Python 會讀的,放 `cards.yaml` 或 JSON 欄位。**

---

## 4. 資料表

### 4.1 總覽

```
店家                         爬蟲回饋資料                        使用者
merchants                    card_schemes                       users
 ├─ merchant_aliases          ├─ scheme_rates                    └─ user_cards(config)
 └─ merchant_source_names     └─ scheme_merchants ──► merchants
```

共 8 張表。實際建表檔為 `scripts/mysql/schema_v3.sql`(待建立)。

所有表皆為 `ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`(不分大小寫比對),唯一例外是 `merchant_source_names.source_name` 用 `utf8mb4_bin`(見 4.4)。本文件的 DDL 為了易讀省略這些設定。

**後端連線也必須指定 `collation='utf8mb4_unicode_ci'`。** MySQL 8 的連線預設定序是 `utf8mb4_0900_ai_ci`,跟資料表不同,SQL 中拿 `@變數` 與欄位比較時會出現 `Illegal mix of collations` 錯誤。

### 4.2 正規化規則(全系統共用)

所有「拿使用者輸入去比對名稱」的地方都用同一套正規化:

1. 去頭尾空白
2. 轉小寫
3. 移除所有半形空白與全形空白(`　`)

例:`"7 - ELEVEN "` → `"7-eleven"`。DB 端用**產生欄位**自動維護正規化結果;後端收到使用者輸入時套用同一規則,App 送原始文字即可。

### 4.3 店家

```sql
CREATE TABLE merchants (
  merchant_id      INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  name             VARCHAR(255)  NOT NULL,   -- 顯示名稱,也是搜尋比對的主名稱
  normalized_name  VARCHAR(255)  AS (LOWER(REPLACE(REPLACE(TRIM(name), ' ', ''), '　', ''))) STORED,
  primary_category VARCHAR(50)   NOT NULL,   -- dining / hotel / travel / department_store…
  country          VARCHAR(10)   NOT NULL,   -- TW / JP / global…,決定國內外(見 7.3)
  active           TINYINT(1)    NOT NULL DEFAULT 1,
  created_at       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (merchant_id),
  UNIQUE KEY uq_merchant_name (name),
  KEY idx_normalized_name (normalized_name),
  KEY idx_category (primary_category)
);

CREATE TABLE merchant_aliases (
  merchant_id      INT UNSIGNED  NOT NULL,
  alias            VARCHAR(100)  NOT NULL,   -- '小七'、'KFC'、'55688'
  normalized_alias VARCHAR(100)  AS (LOWER(REPLACE(REPLACE(TRIM(alias), ' ', ''), '　', ''))) STORED,
  PRIMARY KEY (merchant_id, alias),
  KEY idx_normalized_alias (normalized_alias),
  FOREIGN KEY (merchant_id) REFERENCES merchants (merchant_id)
);
```

- `merchant_id`:DB 自動遞增。DB 是資料來源、不再清空重灌,號碼分配後不會變
- `name`:可以自由改成好看的名字,不影響回饋計算(方案用 `merchant_id` 指向店家)
- `name` 設 UNIQUE:同品牌不同店要用名字區分,例如 `7-ELEVEN` 與 `7-ELEVEN(日本)`
- `primary_category` 與 `country` 會直接影響回饋:分類涵蓋看分類,海外回饋看國別(見 7.3)。新增店家時兩者都要填對
- `country` 填國別代碼(`TW`、`JP`…);在很多國家都有據點、無法歸到單一國家的店填 `global`(例如 `全球迪士尼飯店`、`東橫INN`)。**只要不是 `TW` 就算國外**
- 店家**不刪除**,停業或下架把 `active` 設 0。所以 `user_cards.config` 裡記的店家編號永遠有效
- 別名只放「使用者會打的叫法」,爬蟲原名放 4.4。一個別名不應同時指向兩家店,也不應等於另一家店的 `name`;這種跨表規則由匯入/檢查腳本負責

### 4.4 爬蟲原名對照(匯入用)

```sql
CREATE TABLE merchant_source_names (
  source_name  VARCHAR(255)  CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,  -- 原始字串,一字不改
  merchant_id  INT UNSIGNED  NOT NULL,
  created_at   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (source_name),
  KEY idx_merchant (merchant_id),
  FOREIGN KEY (merchant_id) REFERENCES merchants (merchant_id)
);
```

- `source_name` 存完全原始的字串(含括號,例如 `統一速邁樂(限本島)加油站`)。爬蟲改了一個字,就會被當成新名稱由人確認,不會默默對錯
- 用 `utf8mb4_bin`(逐字元精確比對):預設定序不分大小寫,會把 `Abc` 與 `ABC` 當成同一個原名
- 同一家店可以有多個原名,例如 `大阪環球影城` 與 `大阪環球影城(USJ)`;`55688` 與 `台灣大車隊`
- 待確認的店名就是「本次爬蟲的店名中,這張表還沒有的」,每次匯入當場算出,不另設表
- 已知限制:對照是全域的。若未來兩張卡用同一個字串指不同的店,再改成依卡片對照

### 4.5 爬蟲回饋資料

```sql
-- 方案:只記「這個方案存在」,規則都在 cards.yaml
CREATE TABLE card_schemes (
  scheme_id    INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  card_id      VARCHAR(32)   NOT NULL,   -- 對應 cards.yaml 的卡片代號,例:'cathay_cube'
  scheme_name  VARCHAR(50)   NOT NULL,   -- 與爬蟲及 cards.yaml 的方案名稱一致,例:'樂饗購'
  PRIMARY KEY (scheme_id),
  UNIQUE KEY uq_card_scheme (card_id, scheme_name)
);

-- 方案在各等級/方案下的回饋率
CREATE TABLE scheme_rates (
  scheme_id   INT UNSIGNED  NOT NULL,
  variant     VARCHAR(50)   NOT NULL DEFAULT '',   -- 決定回饋率的設定值,見下方說明
  reward_rate DECIMAL(5,2)  NOT NULL,
  PRIMARY KEY (scheme_id, variant),
  FOREIGN KEY (scheme_id) REFERENCES card_schemes (scheme_id)
);

-- 方案點名的店家
CREATE TABLE scheme_merchants (
  scheme_id     INT UNSIGNED  NOT NULL,
  merchant_id   INT UNSIGNED  NOT NULL,
  rate_override DECIMAL(5,2)  NULL,      -- NULL = 用方案費率;有值 = 這家店的例外回饋率
  notes         JSON          NULL,      -- 爬蟲中的店家層級限制,例:["限本島"]
  PRIMARY KEY (scheme_id, merchant_id),
  KEY idx_merchant (merchant_id),
  FOREIGN KEY (scheme_id)   REFERENCES card_schemes (scheme_id),
  FOREIGN KEY (merchant_id) REFERENCES merchants (merchant_id)
);
```

**`variant`:決定回饋率的那個設定值。** 不同卡片的意義不同,由 `cards.yaml` 的 `rate_by` 指定:

| 卡片 | `rate_by` | `variant` 的值 |
|---|---|---|
| CUBE | `level`(等級) | `Level 1`、`Level 2`、`Level 3` |
| Unicard | `plan`(方案) | `簡單選`、`任意選`、`UP選` |
| 吉鶴卡 | 無 | `''`(空字串,匯入時把爬蟲的 `Standard` 轉成空字串) |

每個值都明確存一筆,不用 NULL 代表「所有等級」。

**為什麼回饋率存在方案上:** 0908 資料中,37 個「卡 + 方案 + 等級」組合裡有 27 個是底下所有店家回饋率相同。真正同方案不同店回饋率不同的只有童樂匯(多數 5%,另有 1%、10% 的店),用 `rate_override` 記例外。`rate_override` 不分等級;若未來出現等級不同的例外,匯入時會報異常。

**爬蟲回饋率的意義各卡不同。** 吉鶴卡的數字**已包含**基本回饋(國內日系特店 5% = 基本 1% + 加碼 4%);Unicard 百大特店的 2% / 2.5% / 3.5% **不含**基本回饋。所以吉鶴卡不疊加一般消費,Unicard 要疊加。這個差異寫在 `cards.yaml`(見 6.1 的 `stacks_with_general`)。

**`card_id` 沒有外鍵。** 卡片定義在 `cards.yaml`,不在資料庫。`card_id` 只有匯入腳本會寫入,寫入前會用 `cards.yaml` 檢查。

### 4.6 使用者

```sql
CREATE TABLE users (
  id            INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  email         VARCHAR(255)  NOT NULL,
  password_hash VARCHAR(255)  NOT NULL,   -- werkzeug 產生的雜湊,約 160 字元
  full_name     VARCHAR(100)  NOT NULL,
  birthday      DATE          NOT NULL,   -- 判斷生日月(慶生月)
  created_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_email (email)
);

CREATE TABLE user_cards (
  user_id    INT UNSIGNED  NOT NULL,
  card_id    VARCHAR(32)   NOT NULL,   -- 對應 cards.yaml 的卡片代號
  config     JSON          NOT NULL,   -- 這張卡的設定,格式由 cards.yaml 決定(見 6.2)
  created_at TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, card_id),
  FOREIGN KEY (user_id) REFERENCES users (id)
);
```

- `users` 以這份定義為準(`id` 為 `INT UNSIGNED`、定序 `utf8mb4_unicode_ci`)。Allen 的 `app.py` 中 `init_db()` 要改成同樣定義:`user_cards.user_id` 設了外鍵,兩邊型別必須相同
- `user_cards.config` 是 MySQL 的 `JSON` 型別,MySQL 會擋掉格式錯誤的內容。內容是否合法由後端依 `cards.yaml` 檢查(見 6.2)
- `card_id` 沒有外鍵,原因同 4.5;後端 API 寫入前用 `cards.yaml` 檢查
- 註冊時只寫 `users`;卡片在登入後新增時才寫 `user_cards`

**DB 為正本,手機為副本:**

1. 新增/修改卡片:先寫 DB,成功後才更新手機本地。順序反過來的話,寫 DB 失敗時兩邊就不一致
2. 登入時:用 DB 的資料覆蓋手機本地
3. 畫面顯示「我的卡片」:讀手機本地,不查 DB
4. 計算推薦:一律用 DB 的 `user_cards`,App 只送「查哪家店」

### 4.7 移除的資料表

| 資料表 | 處理 |
|---|---|
| `cards` | 移除,卡片定義改在 `cards.yaml` |
| `scheme_categories` | 移除,分類涵蓋改寫在 `cards.yaml` 的方案規則 |
| `user_card_conditions` | 移除,併入 `user_cards.config` |
| `card_rewards`(Allen 的扁平表) | 後端改用新表後移除 |
| `legacy_merchants`、`legacy_merchant_aliases`、`legacy_merchant_tags` | 開發機上的舊版商家表,驗證完成後移除 |

---

## 5. 登入與身分驗證

**註冊**:輸入 email、密碼、姓名、生日 → 密碼用 werkzeug 雜湊後寫入 `users`。email 已存在時回「這個 Email 已經被註冊過」。

**登入**:輸入 email、密碼 → 找 `users` 並比對密碼雜湊。
- 成功:後端發一個 **token** 給 App
- 失敗:不管是帳號不存在還是密碼錯誤,一律回「帳號或密碼錯誤」,畫面附「還沒有帳號?前往註冊」按鈕。不回「此帳號不存在」,否則任何人都能拿 email 去試出哪些人註冊過

**token**:
- 內容包含 `user_id` 與到期時間,由後端用**只有後端知道的密鑰**簽名
- App 之後每次呼叫 API 都帶著它(放在 `Authorization` header);後端驗證簽名後取出 `user_id`
- 不讓 App 直接送 `user_id` 的原因:`user_id` 是流水號,App 送什麼後端就信什麼的話,任何人改成別的數字就能存取別人的資料。token 被竄改時簽名會對不上,後端直接拒絕
- 過期或驗證失敗回 401,App 回到登入畫面
- 簽名密鑰放環境變數,不能寫死在程式裡
- 實作可用 Flask 內建的 `itsdangerous`,或 PyJWT
- 有效期限 30 天,過期後重新登入

**註冊後**:使用者還沒有卡片,App 引導他新增卡片。新增卡片時才寫入 `user_cards`。

---

## 6. cards.yaml

### 6.1 內容

後端啟動時讀取一次。匯入腳本也讀它,用來對照爬蟲中的卡片與方案。

| 區塊 | 內容 |
|---|---|
| 卡片 | 代號、名稱、銀行、爬蟲中的卡名 |
| `rate_by` | 哪個設定決定回饋率(`level` / `plan` / 無) |
| `settings` | 設定畫面的選項:等級或方案的清單、開關(每個開關附顯示名稱)、可挑店的上限 |
| `schemes` | 每個方案的規則:要做的動作、需要的條件、涵蓋的範圍(`covers`)、是否疊加一般消費、哪些方案要挑店、限制說明 |
| `general` | 一般消費:可以有多層,每層有名稱、回饋率、需要的條件、適用的地點(`where`) |
| `bonuses` | 卡片層級的加碼:滿足條件時,加在指定的方案或一般消費上 |
| `skip_crawl_schemes` | 爬蟲中整個略過的方案,以及原因 |

**`covers`(分類涵蓋)**:一個方案可以涵蓋多組範圍,店家符合任何一組就適用。每組可指定:
- `category`:店家分類
- `country`:店家國別,例如 `TW` 表示只限國內
- `overseas: true`:所有國外的店(國別不是 `TW`)

**`where`(一般消費的適用地點)**:省略 = 不分國內外;`domestic` = 國內的店;`overseas` = 國外的店;或填國別代碼(例如 `JP`)。

**為什麼一般消費寫在這裡而不是資料庫:** 一般消費都是人確認過的數字,Unicard 的「依電子帳單、自動扣繳分三層」本身就是規則。由人維護,爬蟲的值就不會悄悄蓋掉確認過的數字(0908 爬蟲中 CUBE 的一般消費是 1.2%,實際為 0.3%)。匯入時若爬蟲的一般消費與這裡不同,報告會提醒。

### 6.2 範例

欄位名稱以實作為準,這裡示意結構:

```yaml
cards:
  cathay_cube:
    name: CUBE卡
    bank: 國泰世華
    crawl_name: CUBE卡
    rate_by: level
    settings:
      level: [Level 1, Level 2, Level 3]
      toggles:
        kids_club: 童樂匯
    notes: [實際回饋依當期公告為準]
    schemes:
      全支付:   { action: 需切換至全支付權益方案 }
      台塑家:   { action: 需切換至台塑家權益方案 }
      樂饗購:
        action: 需切換至樂饗購權益方案
        covers: [{ category: dining, country: TW }]          # 國內所有餐廳
      玩數位:   { action: 需切換至玩數位權益方案 }
      趣旅行:
        action: 需切換至趣旅行權益方案
        covers:                                               # 國內旅行相關 + 所有國外消費
          - { category: hotel }
          - { category: travel }
          - { overseas: true }
      集精選:   { action: 需切換至集精選權益方案 }
      童樂匯:
        action: 需切換至童樂匯權益方案
        requires: [kids_club]
        notes: [是否需另行切換方案尚未與官網條款或 Allen 確認]
      慶生月:
        action: 需切換至慶生月權益方案
        requires: [birthday_month]
    general:
      - { name: 一般消費, rate: 0.3, notes: [不含保費] }
      - { name: 海外消費, rate: 2.5, where: overseas, notes: [含國外餐飲、飯店到店付款等] }
    skip_crawl_schemes:
      固定回饋: 一般消費與海外消費改由 general 設定

  esun_unicard:
    name: Unicard
    bank: 玉山銀行
    crawl_name: Unicard
    rate_by: plan
    settings:
      plan: [簡單選, 任意選, UP選]
      toggles:
        e_bill: 電子帳單
        auto_debit: 自動扣繳
      max_chosen_merchants: 8
    notes: [實際回饋依當期公告為準]
    schemes:
      百大特店:
        stacks_with_general: true          # 爬蟲數字不含基本回饋,要加上一般消費
        pick_merchants_when_plan: [任意選]  # 任意選只算使用者挑的店
    general:                                # 取符合條件中最高的;國內外相同(請 Allen 確認)
      - { name: 一般消費, requires: [],                   rate: 0 }
      - { name: 一般消費, requires: [e_bill],             rate: 0.3 }
      - { name: 一般消費, requires: [e_bill, auto_debit], rate: 1.0 }

  ubot_jiho:
    name: 吉鶴卡
    bank: 聯邦銀行
    crawl_name: 吉鶴卡
    rate_by: null
    settings:
      toggles:
        new_customer: 新戶自動扣繳       # 新戶與自動扣繳在吉鶴卡是綁在一起的,一個開關
    notes: [實際回饋依當期公告為準]
    schemes:                             # 爬蟲數字已包含基本回饋,不疊加一般消費
      國內人氣餐廳:
        notes: [需於週一至週五並滿足指定額度,結帳時出示吉鶴卡實體卡並全額支付消費才可享有完整回饋]
      國內日系特店: {}
      日本熱門商店: {}
      日本交通卡儲值: {}
    general:
      - { name: 國內一般消費, rate: 1.0, where: domestic }
      - { name: 國外一般消費, rate: 1.0, where: overseas }
      - { name: 日本消費,     rate: 2.5, where: JP, notes: [日幣消費] }
    bonuses:
      - requires: [new_customer]
        add: 0.5                         # 目前查到 0.5%(請 Allen 確認)
        applies_to: [國內一般消費, 國內日系特店]   # 國內人氣餐廳、國外消費都沒有
    skip_crawl_schemes:
      國內一般消費: 改由 general 設定
      國外一般消費: 改由 general 設定
      日本消費: 改由 general 設定;日本行動支付 5% 需要付款方式資訊,不納入
```

### 6.3 使用者卡片設定(`user_cards.config`)

config 的欄位由該卡在 `cards.yaml` 的 `settings` 決定:

| 卡片 | config 範例 |
|---|---|
| CUBE | `{"level": "Level 2", "kids_club": false}` |
| 吉鶴卡 | `{"new_customer": true}` |
| Unicard | `{"plan": "任意選", "e_bill": true, "auto_debit": true, "chosen_merchants": [12, 87]}` |

後端儲存時的檢查:
- `level` / `plan` 必須在 `settings` 列出的選項中(擋掉 `level_1` 這種拼錯的值)
- 開關只能是 `settings.toggles` 列出的,值為 `true` / `false`
- `chosen_merchants` 只有在方案屬於 `pick_merchants_when_plan` 時才允許;最多 `max_chosen_merchants`(Unicard 8 家);每個編號都必須在該方案的點名店家中
- 不允許其他欄位

Unicard 實際規則是「每月最多切換 30 次方案,以當月最後一個方案計算整月」。App 不限制切換次數,一律以使用者**目前**設定的方案計算。

### 6.4 條件

| 條件 | 意義 | 卡片 | 來源 |
|---|---|---|---|
| `kids_club` | 已加入童樂匯 | CUBE | config 開關,顯示「童樂匯」 |
| `birthday_month` | 本月是生日月 | CUBE | 系統依 `users.birthday` 自動判斷,不存在 config |
| `new_customer` | 新戶並設定自動扣繳 | 吉鶴卡 | config 開關,顯示「新戶自動扣繳」 |
| `e_bill` | 已設定電子帳單 | Unicard | config 開關,顯示「電子帳單」 |
| `auto_debit` | 已設定自動扣繳 | Unicard | config 開關,顯示「自動扣繳」 |

一個方案、一般消費層或加碼可以要求多個條件,**全部滿足**才適用。

### 6.5 後端啟動時的一致性檢查

- 資料庫中每個 `(card_id, scheme_name)` 都要在 `cards.yaml` 找得到規則
- `cards.yaml` 中每個方案都要在資料庫找得到
- `bonuses.applies_to` 中的名稱都要是該卡的方案或一般消費層
- 對不上的列出警告。資料庫中有、`cards.yaml` 沒有的方案,計算時忽略

---

## 7. 查詢流程

```
① 使用者打字 ──► 自動補全(多筆候選)
                    │
② 點選某個建議 ─────┼──► 得到 merchant_id ──┐
   或直接按搜尋 ────┘──► 解析店家(一家或找不到)┤
                                              ▼
③ SQL 撈出使用者卡片設定,以及這些卡的方案、回饋率、店家是否被點名
                                              ▼
④ Python 依 cards.yaml 判斷每張卡的最佳回饋,排序取前 3 名
```

### 7.1 自動補全

**觸發方式(App 端):**
- 打第一個字就送出查詢
- 同時只允許一個請求在途中。結果回來時,如果輸入框的文字已經變了,就用當下最新的文字再送一次
- 輸入法組字中不送(例如注音 `ㄉㄧㄥˇ` 尚未選字時)

**SQL(`:q` 為正規化後的輸入):**

```sql
SELECT m.merchant_id, m.name,
       MIN(CASE
             WHEN m.normalized_name = :q OR a.normalized_alias = :q THEN 1          -- 完全相同
             WHEN m.normalized_name LIKE CONCAT(:q, '%')
               OR a.normalized_alias LIKE CONCAT(:q, '%') THEN 2                    -- 開頭相同
             ELSE 3                                                                  -- 包含
           END) AS match_rank
FROM merchants m
LEFT JOIN merchant_aliases a ON a.merchant_id = m.merchant_id
WHERE m.active = 1
  AND (m.normalized_name LIKE CONCAT('%', :q, '%') OR a.normalized_alias LIKE CONCAT('%', :q, '%'))
GROUP BY m.merchant_id, m.name, m.country
ORDER BY match_rank, (m.country <> 'TW'), CHAR_LENGTH(m.name)   -- 同一級時台灣的店優先
LIMIT 10;
```

`:q` 中的 `%`、`_` 要先跳脫。透過別名找到的店,清單上顯示的是店家的 `name`(打 `55688` 出現的是「台灣大車隊」)。

日本的店名稱前加「日本」(`日本 7-ELEVEN`、`日本三越`),避免和台灣的店搞混;使用者多半在台灣消費,所以命中程度相同時台灣的店排前面(打 `7-ELEVEN` 先出現台灣門市、打 `三越` 先出現新光三越)。

### 7.2 確定店家

**使用者點了建議清單** → 直接拿到 `merchant_id`。

**使用者直接按搜尋** → 兩層、精準優先:

```sql
-- 第一層:完全相同(名稱或別名)
SELECT m.merchant_id, m.name, m.primary_category, m.country
FROM merchants m
LEFT JOIN merchant_aliases a ON a.merchant_id = m.merchant_id
WHERE m.active = 1
  AND (m.normalized_name = :q OR a.normalized_alias = :q)
ORDER BY (m.country <> 'TW')
LIMIT 1;

-- 第二層:第一層沒結果、且輸入至少 2 個字時才查。任一方包含另一方即算命中
WITH keys AS (                                   -- 店名與別名都當成比對對象
  SELECT merchant_id, normalized_name AS key_text FROM merchants WHERE active = 1
  UNION ALL
  SELECT a.merchant_id, a.normalized_alias
  FROM merchant_aliases a JOIN merchants m ON m.merchant_id = a.merchant_id
  WHERE m.active = 1
)
SELECT m.merchant_id, m.name, m.primary_category, m.country
FROM keys k
JOIN merchants m ON m.merchant_id = k.merchant_id
WHERE CHAR_LENGTH(k.key_text) >= 2
  AND (k.key_text LIKE CONCAT('%', :q, '%') OR :q LIKE CONCAT('%', k.key_text, '%'))
ORDER BY
  CASE WHEN k.key_text LIKE CONCAT(:q, '%') OR :q LIKE CONCAT(k.key_text, '%')
       THEN 1 ELSE 2 END,                        -- ① 開頭相同優先
  ABS(CHAR_LENGTH(k.key_text) - CHAR_LENGTH(:q)), -- ② 長度越接近輸入,命中程度越高
  (m.country <> 'TW'),                           -- ③ 台灣的店優先
  CHAR_LENGTH(m.name)                            -- ④ 都一樣時取名稱最短
LIMIT 1;
```

- 「輸入包含店名」這個方向讓 `鼎泰豐信義店` 能對到 `鼎泰豐`
- 多家命中時依**命中程度**排序:開頭相同的優先;再來是長度最接近輸入的(長度差越少,代表輸入和店名重疊的部分越完整);再來台灣的店優先;都一樣才取名稱最短
- 兩層都沒有結果 → 找不到店家

### 7.3 計算推薦

**SQL 只撈資料**,兩支查詢:

```sql
-- 使用者的卡片設定與生日
SELECT uc.card_id, uc.config, u.birthday
FROM user_cards uc
JOIN users u ON u.id = uc.user_id
WHERE uc.user_id = :user_id;

-- 這些卡的所有方案、各等級回饋率、這家店有沒有被點名
SELECT s.card_id, s.scheme_name, sr.variant, sr.reward_rate,
       (sm.merchant_id IS NOT NULL) AS is_named, sm.rate_override, sm.notes AS merchant_notes
FROM card_schemes s
JOIN scheme_rates sr ON sr.scheme_id = s.scheme_id
LEFT JOIN scheme_merchants sm
       ON sm.scheme_id = s.scheme_id AND sm.merchant_id = :merchant_id
WHERE s.card_id IN (:user_card_ids);
```

找不到店家時 `:merchant_id` 為 NULL,`is_named` 全部為假。第二支查詢的結果最多幾十筆。

**Python 依 `cards.yaml` 判斷**,每張卡:

1. **條件**:config 中為 `true` 的開關,加上系統判斷的 `birthday_month`(本月 = 生日月份,以台灣時間計)
2. **地點**:店家的 `country`;**找不到店家時視為國內**(`TW`)
3. **一般消費**:`general` 中條件全部滿足、`where` 符合地點的各層,各自加上適用的加碼後,取最高。一層都不符合就是 0%
4. **逐一檢查方案**(`schemes` 中的每個方案):
   - 條件:`requires` 全部滿足,否則跳過
   - 適用:店家被點名(`is_named`),或店家符合 `covers` 中任何一組;都不是就跳過
   - 挑店:目前方案在 `pick_merchants_when_plan` 中時,店家必須在 config 的 `chosen_merchants`,否則跳過
   - 回饋率:取 `variant` 等於 config 中 `rate_by` 那個設定值的那筆(`rate_by` 為空時用 `''`);有 `rate_override` 就用它
   - 疊加:`stacks_with_general` 為真時,加上第 3 步的一般消費
   - 加碼:加上 `bonuses` 中條件滿足、且 `applies_to` 包含這個方案的加碼
5. **取最好的一筆**:第 3 步的一般消費與第 4 步的所有方案**一起比**,取回饋率最高者。同分時優先不需要做任何動作的(一般消費),其次是店家被點名的方案
6. **卡片之間**:回饋率高到低,同分依卡名,取前 3 名

> 第 5 步在 v0.3 是「有方案適用就不看一般消費」。改成一起比,是因為一般消費現在可能比方案高:CUBE Level 1 在國外的店,趣旅行 2%、海外消費 2.5%,應該推薦不用切換的 2.5%。

```python
def best_reward(card, rows, merchant, birthday):
    rules = card.rules
    flags = {k for k, v in card.config.items() if v is True}
    if is_birthday_month(birthday):
        flags.add('birthday_month')
    country = merchant.country if merchant else 'TW'          # 找不到店家視為國內

    def bonus(name):
        return sum(b.add for b in rules.bonuses if b.requires <= flags and name in b.applies_to)

    generals = [(g.rate + bonus(g.name), 0, g.name)           # 第二個值:同分排序用,一般消費排前面
                for g in rules.general if g.requires <= flags and where_matches(g.where, country)]
    best_general = max(generals, default=(0, 0, '一般消費'))

    variant = card.config.get(rules.rate_by, '') if rules.rate_by else ''
    candidates = [best_general]
    for name, rule in rules.schemes.items():
        row = rows.get((card.card_id, name, variant))
        if row is None or not rule.requires <= flags:
            continue
        if not (row.is_named or covers_match(rule.covers, merchant, country)):
            continue
        if variant in rule.pick_merchants_when_plan and merchant.id not in card.config.get('chosen_merchants', []):
            continue
        rate = row.rate_override if row.rate_override is not None else row.reward_rate
        if rule.stacks_with_general:
            rate += best_general[0]
        rate += bonus(name)
        candidates.append((rate, -1 if row.is_named else -2, name))

    return max(candidates)
```

### 7.4 範例

**CUBE Level 2、未加入童樂匯、不是生日月,查「鼎泰豐」(dining、TW)**

| 項目 | 結果 |
|---|---|
| 童樂匯、慶生月 | 條件不滿足,跳過 |
| 樂饗購 | 涵蓋國內餐廳 → 3%(Level 2) |
| 其他方案 | 未被點名、未被涵蓋,跳過 |
| 一般消費 | 0.3%(國內,海外消費不適用) |

→ **3%,需切換至樂饗購權益方案**。

**CUBE 查「三越」(日本的百貨公司)**
- 趣旅行涵蓋所有國外的店 → Level 1 為 2%、Level 2 為 3%
- 一般消費:海外消費 2.5%
- Level 1 → **2.5%,不用切換**;Level 2 → **3%,需切換至趣旅行權益方案**

**Unicard 任意選、有電子帳單與自動扣繳,查「台北101」**
- 一般消費:三層都符合,取最高 1%
- 百大特店:台北101 被點名、在 `chosen_merchants` 中;任意選 2.5% + 1% = **3.5%**
- 若沒挑台北101 → **1%**

**吉鶴卡、新戶自動扣繳**
- UNIQLO(國內日系特店):5% + 0.5% = **5.5%**
- 國內人氣餐廳的店:**10%**(沒有新戶加碼)
- 國內未知店家:1% + 0.5% = **1.5%**
- 日本熱門商店的店:**8%**(沒有新戶加碼)

### 7.5 顯示

- 每筆顯示:卡名、回饋率、方案名稱(一般消費顯示該層名稱,例如「海外消費」)、要做的動作、限制說明(卡片、方案、一般消費層的 `notes`,加上店家層級的 `merchant_notes`)
- 找不到店家時:結果上方顯示「此店家不在回饋名單中,以一般消費計算」,下方照常列出各卡一般消費
- 找得到店家、但某些卡只有一般消費:正常顯示,不跳提示

### 7.6 API(建議,由 Allen 定案)

| 方法與路徑 | 輸入 | 輸出 | 需要 token |
|---|---|---|---|
| `POST /api/register` | email、密碼、姓名、生日 | 成功與否 | 否 |
| `POST /api/login` | email、密碼 | token、姓名、生日 | 否 |
| `GET /api/merchants/suggest?q=` | 輸入文字 | `[{merchant_id, name}]`,最多 10 筆 | 是 |
| `POST /api/recommend` | `{merchant_id}` 或 `{query}`(二擇一) | `{merchant: {merchant_id, name} \| null, results: [...]}` | 是 |
| `GET /api/cards` | — | 各卡的名稱與設定選項(來自 `cards.yaml` 的 `settings`) | 是 |
| `GET /api/cards/{card_id}/pickable_merchants` | — | 需要挑店的方案中可挑的店家(例如 Unicard 百大特店) | 是 |
| `GET /api/user/cards` | — | 使用者的卡片與 config | 是 |
| `PUT /api/user/cards/{card_id}` | config | 新增或更新一張卡(依 6.3 檢查) | 是 |
| `DELETE /api/user/cards/{card_id}` | — | 移除一張卡 | 是 |

手機只快取 `/api/cards` 的結果,不打包 `cards.yaml`:規則若打包進 App,銀行改規則就要重新發版,且舊版 App 的選項會跟後端的計算對不上。

---

## 8. 爬蟲匯入流程

```
爬蟲匯出檔
 ① 對照卡片:爬蟲 card_name → cards.yaml 的 crawl_name      對不到 → 中止,先在 cards.yaml 加入新卡
 ② 特殊列:一般消費與 cards.yaml 的 general 比對,不同則提醒;國別、付款工具等略過
 ③ 對照方案:cards.yaml 的 schemes 或 skip_crawl_schemes      對不到 → 本次略過,先在 cards.yaml 加入
 ④ 對照店名:merchant_source_names                          對不到 → 列入報告並附配對建議
 ⑤ 計算:每個方案每個 variant,取多數店家的回饋率當方案費率,少數不同者記為例外
 ⑥ 寫入:card_schemes 沒有的方案自動新增;本次出現的方案,在一個交易內替換其 scheme_rates 與 scheme_merchants
 ⑦ 報告
```

- `variant`:依 `rate_by` 取爬蟲的 `card_level`;`rate_by` 為空的卡(吉鶴卡)一律存 `''`
- 建議先用 `--dry-run` 只看報告,處理完待確認店名再正式匯入
- 括號中的限制說明(例如 `(限本島)`)抽出放進 `scheme_merchants.notes`;但 `merchant_source_names` 對照時用未經處理的原始字串
- 不自動新增店家:腳本分不出「新店」與「舊店改名」。改名若被當成新店,別名會留在舊的那筆、方案名單跟著新名字走,使用者搜別名會默默拿到一般消費
- 新增店家時要填對分類與國別,兩者都會影響回饋

**待確認店名的處理**:報告中附上建議(「可能是既有店家 #12」、「疑似新店,建議分類 dining」、「疑似付款工具」),人確認後用指令處理:

```bash
import --map    "7-ELEVEN 實體門市" 12                       # 對到既有店家
import --new    "一蘭拉麵" --category dining --country TW    # 建立新店並建立對照
import --ignore "悠遊卡"                                     # 加入略過清單
```

非店家的判斷樣式與略過清單屬於匯入腳本自己的設定,不放在 `cards.yaml`。

**已知限制**:Unicard 百大特店名單中有 LINE Pay、街口支付等行動支付,銀行規則允許選入任意選的 8 家。系統以「店家」查詢、不記錄付款方式,這些會被當成非店家略過,使用者在 App 中也選不到。

**報告中的異常提醒**:例外回饋率無法用單一值表示的店家、上次有這次沒有的方案、離開方案名單的店家、別名衝突、爬蟲的一般消費與 `cards.yaml` 不同。

**修改紀錄**:資料庫中的人工修改(店名、分類、國別、別名)不會出現在 git,所以一律寫成 SQL 腳本,放在 `db/changes/`(檔名以日期開頭,例如 `2026-10-05_rename_mitsui_outlet.sql`)並 commit,之後可以照順序重播。`cards.yaml` 在 git 中,不受此影響。

---

## 9. 驗證案例

實作後要能通過的案例。現行 `scripts/db/verify_v2.py` 依 v0.2 實作,v0.4 改為測試 Python 的計算函式。

| 案例 | 預期 |
|---|---|
| 搜尋 `藏壽司`(不在任何方案名單)、CUBE Level 2 | 樂饗購分類涵蓋,3% |
| 搜尋 `小七`、`統一超商`(別名) | 解析為台灣 7-11,拿到點名方案的 2%,不是一般消費 |
| 搜尋 `55688` | 解析為台灣大車隊 |
| 按搜尋 `鼎泰豐信義店`(目錄裡沒有完全相同的) | 解析為鼎泰豐 |
| 搜尋 `麗寶樂園`、CUBE 未加入 / 已加入童樂匯 | 非童樂匯 / 童樂匯 |
| 搜尋童樂匯 10% 的例外店、已加入童樂匯 | 10%,不是方案的 5% |
| 搜尋 `誠品生活`、CUBE Level 1 / Level 3 | 2% / 3.3% |
| 搜尋慶生月名單上的店、生日月 / 非生日月 | 慶生月回饋並顯示「需切換至慶生月權益方案」/ 其他方案或一般消費 |
| 搜尋 `三越`(日本)、CUBE Level 1 / Level 2 | 2.5% 海外消費、不用切換 / 3% 趣旅行 |
| 搜尋 `台鐵`(未被趣旅行點名的旅行類)、CUBE Level 2 | 趣旅行 3% |
| 搜尋 `台北101`、Unicard 簡單選 / UP選、無電子帳單 | 2% / 3.5% |
| 同上、UP選、電子帳單 + 自動扣繳 / 只有電子帳單 / 只有自動扣繳 | 4.5% / 3.8% / 3.5% |
| 搜尋 `台北101`、Unicard 任意選、有挑 / 沒挑、電子帳單 + 自動扣繳 | 3.5% / 1% |
| 搜尋不在百大的店、Unicard 都沒有 / 只有電子帳單 / 兩者 | 0% / 0.3% / 1% |
| 吉鶴卡新戶,搜尋 UNIQLO / 國內人氣餐廳的店 / 未知店家 / 日本熱門商店的店 | 5.5% / 10% / 1.5% / 8% |
| 吉鶴卡非新戶,搜尋 UNIQLO / 未知店家 | 5% / 1% |
| 搜尋完全不存在的店 | 顯示「不在回饋名單中」,各卡一般消費(以國內計) |
| 自動補全打 `藏` | 清單中有藏壽司 |
| 儲存 config:不存在的等級(`level_1`)、未定義的欄位、簡單選卻帶 `chosen_merchants`、挑了第 9 家、挑了不在百大名單的店 | 後端拒絕 |
| 未帶 token、token 被竄改或過期 | 401 |
| 登入時帳號不存在 / 密碼錯誤 | 兩者回同樣的「帳號或密碼錯誤」 |
| 資料庫有方案但 `cards.yaml` 沒有 | 啟動時警告,計算時忽略 |
| 爬蟲中某店改名後重新匯入 | 該店列入待確認並附建議,其他店照常匯入 |

---

## 10. 實作步驟

1. 建立 `cards.yaml`(內容見 6.2;由 `scripts/db/migrate_v2.py` 開頭的設定區改寫)
2. 建立 `scripts/mysql/schema_v3.sql`,並調整本機資料庫:
   - 移除 `cards`、`scheme_categories`、`user_card_conditions`
   - `card_schemes` 移除規則欄位;移除一般消費方案的資料
   - `scheme_rates.card_level` 改名 `variant`,吉鶴卡的 `Standard` 改為 `''`
   - `user_cards` 移除 `card_level`、新增 `config`,wilson 的資料轉成 config
3. 資料修正:`merchants.country` 改為 `VARCHAR(10)`;`55688` 併入台灣大車隊(爬蟲原名對照 + 別名);`全球迪士尼飯店`、`東橫INN` 的國別改為 `global`
4. 匯入腳本改讀 `cards.yaml`,補上慶生月的匯入
5. 後端:載入 `cards.yaml` 與一致性檢查(6.5)、計算函式(7.3)、config 檢查(6.3)、註冊 / 登入 / token(第 5 節)、API(7.6)
6. 驗證案例(第 9 節)改寫成 Python 測試
7. 更新 `scripts/mysql/README.md`、`SETUP.md` 與範例 SQL
8. **打包給 Allen**:設計文件、`cards.yaml`、建表檔、匯入腳本、後端程式、交接說明(取代已過時的 `swift_port/HANDOFF_PROMPT.md`)

---

## 11. 現行程式的去留

| 現行 | v0.4 中 |
|---|---|
| `scripts/convert_allen_rewards.js` | 由新的匯入腳本取代 |
| `scripts/build_merchants.js` | 不再產生 `merchants.json`;分類邏輯保留,用來產生匯入時的建議分類 |
| `scripts/mysql/build_*_sql.js`、`seed_*.sql` | 移除 |
| `lib/data/*.json`、Flutter App 內的比對邏輯、`swift_port/` | App 改呼叫 API 後移除。不另外從資料庫匯出 JSON 給 App 過渡,因為登入與 token 本來就需要後端 |
| `scripts/db/migrate_v2.py` 開頭的設定區 | 改寫為 `cards.yaml` |
| `app.py` 的 `/api/search_rewards`、`/api/autocomplete`、`/api/unicard_merchants` | 由 7.6 的 API 取代 |

新增卡片不需要改資料表:在 `cards.yaml` 加一段、匯入爬蟲資料即可。只有當新卡出現現有規則表達不了的情況時,才需要擴充計算函式。

---

## 12. 待確認事項與通知

目前沒有阻擋實作的待確認事項。

**請 Allen 確認(先照目前的設定實作)**:
- 吉鶴卡新戶自動扣繳加碼為 0.5%
- Unicard 在國外的一般消費與國內相同(0% / 0.3% / 1%)

**要通知 Allen 的事項**:
- `users` 表改用本文件 4.6 的定義,`app.py` 的 `init_db()` 跟著改
- 登入改為發 token(有效 30 天),後續 API 都要帶 token
- `app.py` 目前 `debug=True` 且監聽 `0.0.0.0`,同網路的人可透過除錯頁面執行程式;要給手機連時請關掉 debug。資料庫密碼不要寫死在檔案裡

**已確定**(2026-10-01 ~ 10-04):
- CUBE 一般消費 0.3%、國外的店 2.5%(不用切換);吉鶴卡國內 1%、日本 2.5%、其他國外 1%
- Unicard 一般消費依電子帳單 / 自動扣繳分 0% / 0.3% / 1%,疊加在百大特店上;以使用者目前設定的方案為準,不限切換次數;任意選最多 8 家
- 吉鶴卡爬蟲數字已含基本回饋;新戶自動扣繳 +0.5%,只加在國內一般消費與國內日系特店
- 慶生月用 `users.birthday` 在後端判斷,需切換至慶生月權益方案
- 樂饗購只涵蓋國內餐廳;趣旅行涵蓋飯店、旅行類(含叫車)與所有國外的店
- 登入發 token(有效 30 天),登入失敗一律回「帳號或密碼錯誤」
- `users` 表 `id` 為 `INT UNSIGNED`、定序 `utf8mb4_unicode_ci`
- 匯入腳本與後端用 Python;規則寫在 `cards.yaml` 並由後端啟動時讀取;使用者卡片設定存 JSON
- 店家國別可填 `global`,不是 `TW` 就算國外
- 模糊比對多家命中時:開頭相同優先,再來是長度最接近輸入的,再來台灣的店優先,最後取名稱最短;日本的店名稱前加「日本」
- 資料庫人工修改寫成 SQL 腳本放 `db/changes/` 並 commit
- App 直接改呼叫 API,不另外匯出 JSON 過渡
- 待確認店名用 `--map` / `--new` / `--ignore` 指令處理
