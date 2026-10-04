# 本機 MySQL 設定

把信用卡回饋資料灌進本機 MySQL。資料表設計見 [docs/DB_DESIGN.md](../../docs/DB_DESIGN.md)。

以下指令都是 **PowerShell**,在專案根目錄執行。

## 現況(2026-09-10 確認)

這台機器**已經裝好 MySQL Server 8.0,不用再下載**:

- 安裝位置:`C:\Program Files\MySQL\MySQL Server 8.0`
- Windows 服務 `MySQL80` 正在執行中,3306 埠有在監聽
- 已安裝的元件:MySQL Server / Workbench / Shell / Router 8.0
- `mysql` 指令沒有加進 PATH,所以下面的指令都用完整路徑

## 檔案說明

| 檔案 | 用途 | 進版控? |
|---|---|---|
| `schema.sql` | 建立 `credit_card_app` 資料庫、`card_rewards` 與 `users` 資料表 | 是 |
| `schema_v2.sql` | 新版資料表(店家、方案、使用者卡片) | 是 |
| `examples/recommend_example.sql` | 推薦計算的完整範例(見下方「範例」) | 是 |
| `build_seed_sql.js` | 把 Allen 的匯出 JSON 轉成 `card_rewards` 的 INSERT script | 是 |
| `seed_card_rewards.sql` | 上面產生出來的資料,1236 筆 | 是(可重新產生) |
| `build_merchants_sql.js`、`seed_merchants.sql` | **已停用**。舊版商家表的產生器,新版表同名但結構不同,執行會出錯 | 是 |
| `reset-root-password.ps1` | 忘記 root 密碼時重設用(需系統管理員 PowerShell) | 是 |
| `my.local.cnf.example` | 連線設定範本 | 是 |
| `my.local.cnf` | 你自己的連線設定,**內含密碼** | **否**(已在 .gitignore) |

新版資料表的灌入與驗證腳本在 `scripts/db/`(Python)。

## 先設定兩個變數

每開一個新的 PowerShell 視窗,先執行這兩行,後面的指令都會用到:

```powershell
$MYSQL = "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"
$CNF   = "--defaults-extra-file=scripts/mysql/my.local.cnf"
```

> **PowerShell 的兩個坑,所以下面都用 `-e "source 檔案"` 執行 SQL 檔:**
> - PowerShell 不支援 `mysql < 檔案.sql` 這種 `<` 輸入導向,會直接報錯
> - 改用 `Get-Content 檔案.sql | & $MYSQL` 的話,PowerShell 5.1 會把中文轉成 `?`,資料就壞了
>
> `source` 是讓 mysql 自己讀檔,兩個問題都不會發生。

## 首次設定

1. 複製連線設定範本,並填入你的 MySQL root 密碼:

   ```powershell
   Copy-Item scripts/mysql/my.local.cnf.example scripts/mysql/my.local.cnf
   notepad scripts/mysql/my.local.cnf    # 把 password= 那行換成真正的密碼
   ```

   密碼放檔案而不是直接打在指令上,是因為 `mysql -p你的密碼` 會被記進指令歷史紀錄,
   同一台機器上其他程式也看得到。這個檔案已經被 `.gitignore` 擋住,不會進版控。

2. 建立資料庫與資料表(順序不能換,`schema_v2.sql` 的 `user_cards` 需要 `users` 先存在):

   ```powershell
   & $MYSQL $CNF -e "source scripts/mysql/schema.sql"
   & $MYSQL $CNF -e "source scripts/mysql/schema_v2.sql"
   ```

3. 灌入 `card_rewards`(Allen 的 `app.py` 目前查的是這張表):

   ```powershell
   & $MYSQL $CNF -e "source scripts/mysql/seed_card_rewards.sql"
   ```

4. 灌入新版資料表(店家、方案、回饋率),需要 Python 與 `mysql-connector-python`。
   用 anaconda 的話,請在已 activate 的 conda 環境(提示字元前有 `(base)`)裡執行,
   否則 pip 會因為找不到 SSL 模組而無法下載套件:

   ```powershell
   pip install -r scripts/db/requirements.txt
   python scripts/db/migrate_v2.py --dry-run   # 先看報告,不寫入
   python scripts/db/migrate_v2.py             # 寫入
   python scripts/db/verify_v2.py              # 跑驗證案例(DB_DESIGN.md 第 8 節)
   ```

## 資料表

| 資料表 | 內容 | 狀態 |
|---|---|---|
| `card_rewards` | Allen 的扁平回饋表 | `app.py` 使用中;v2 遷移完成後移除 |
| `users` | 帳號 | 登入擱置中;目前有一個測試使用者 wilson(見下方) |
| `cards`、`card_schemes`、`scheme_rates`、`scheme_merchants`、`scheme_categories` | 卡片與回饋方案 | 由 `migrate_v2.py` 灌入 |
| `merchants`、`merchant_aliases`、`merchant_source_names` | 店家目錄 | 由 `migrate_v2.py` 灌入 |
| `user_cards`、`user_card_conditions` | 使用者卡片 | 目前只有 wilson 的兩張卡 |

### 測試使用者 wilson

開發機上手動建立的使用者,用來測試推薦計算(登入功能還沒做):

| 欄位 | 值 |
|---|---|
| email | `wilson@local.test` |
| 密碼 | 未設定(`password_hash` 為 `!`,無法登入) |
| 卡片 | CUBE(Level 1)、吉鶴卡(Standard),沒有勾任何條件 |

建立方式:

```powershell
& $MYSQL $CNF credit_card_app -e "START TRANSACTION; INSERT INTO users (email, password_hash, full_name, birthday) VALUES ('wilson@local.test', '!', 'wilson', '2000-01-01'); SET @uid = LAST_INSERT_ID(); INSERT INTO user_cards (user_id, card_id, card_level) VALUES (@uid, 'cathay_cube', 'Level 1'), (@uid, 'ubot_jiho', 'Standard'); COMMIT;"
```

改等級或加條件:

```powershell
# CUBE 改成 Level 2
& $MYSQL $CNF credit_card_app -e "UPDATE user_cards SET card_level = 'Level 2' WHERE user_id = (SELECT id FROM users WHERE email = 'wilson@local.test') AND card_id = 'cathay_cube';"

# 吉鶴卡勾「新戶」
& $MYSQL $CNF credit_card_app -e "INSERT INTO user_card_conditions (user_id, card_id, condition_key) SELECT id, 'ubot_jiho', 'new_customer' FROM users WHERE email = 'wilson@local.test';"
```

### 開發機上的 `legacy_*` 資料表

在 Wilson 的開發機上,建立 v2 之前已經有舊版的 `merchants`、`merchant_aliases`、`merchant_tags`
(452 家店)。為了讓 v2 同名的新表建得起來,舊表已改名為 `legacy_merchants`、
`legacy_merchant_aliases`、`legacy_merchant_tags` 保留,沒有刪除:

```sql
RENAME TABLE merchants TO legacy_merchants,
             merchant_aliases TO legacy_merchant_aliases,
             merchant_tags TO legacy_merchant_tags;
```

新機器照上面步驟設定不會有這些表。等 v2 遷移驗證完成後刪除。

## 常用查詢

```powershell
# 各表筆數
& $MYSQL $CNF --table credit_card_app -e "SELECT TABLE_NAME, TABLE_ROWS FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'credit_card_app';"

# 看某張卡的所有方案與各等級回饋率
& $MYSQL $CNF --table credit_card_app -e "SELECT s.scheme_name, s.is_default, s.required_condition, sr.card_level, sr.reward_rate FROM card_schemes s JOIN scheme_rates sr ON sr.scheme_id = s.scheme_id WHERE s.card_id = 'cathay_cube' ORDER BY s.scheme_name, sr.card_level;"

# 看某個方案點名了哪些店
& $MYSQL $CNF --table credit_card_app -e "SELECT m.merchant_id, m.name, sm.rate_override FROM scheme_merchants sm JOIN card_schemes s ON s.scheme_id = sm.scheme_id JOIN merchants m ON m.merchant_id = sm.merchant_id WHERE s.scheme_name = '樂饗購' ORDER BY m.name;"

# 進互動模式,可以連續下 SQL,打 exit 離開
& $MYSQL $CNF credit_card_app
```

`--table` 會把結果畫成表格,比較好讀;不加的話是用 Tab 分隔。

**自己寫 SQL 時注意定序:** 如果 SQL 裡有 `SET @變數 = '文字'` 再拿去跟欄位比較,
要先執行 `SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;`。MySQL 8 連線預設的定序是
`utf8mb4_0900_ai_ci`,跟資料表的 `utf8mb4_unicode_ci` 不同,會出現 `Illegal mix of collations` 錯誤。

## 範例:CUBE Level 2 查「鼎泰豐」

完整範例在 [examples/recommend_example.sql](examples/recommend_example.sql),對應
`docs/DB_DESIGN.md` 4.2 與 4.3。它會在交易內建立一個暫時的使用者(CUBE Level 2、吉鶴卡、
Unicard 簡單選),跑完 `ROLLBACK`,不會留下任何資料:

```powershell
& $MYSQL $CNF --table -e "source scripts/mysql/examples/recommend_example.sql"
```

想試其他店,改檔案裡的 `SET @q = '鼎泰豐';`。

### 步驟 1:確定店家

用正規化後的輸入去比對店名或別名,拿到 `merchant_id` 和分類:

```sql
SELECT m.merchant_id, m.primary_category
  INTO @merchant_id, @merchant_category
FROM merchants m
LEFT JOIN merchant_aliases a ON a.merchant_id = m.merchant_id
WHERE m.active = 1
  AND (m.normalized_name = @q OR a.normalized_alias = @q)
LIMIT 1;
```

```
+-----------+-------------+--------+
| 輸入      | merchant_id | 分類   |
+-----------+-------------+--------+
| 鼎泰豐    |         404 | dining |
+-----------+-------------+--------+
```

### 步驟 2:各卡適用的方案(看懂 JOIN 在做什麼)

這一步把每張卡、每個方案都展開,只留下「適用這家店」的。實際 API 不需要這一步,
它是為了看清楚中間過程:

```sql
SELECT c.card_name AS 卡片,
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
JOIN cards c         ON c.card_id = uc.card_id                                     -- 卡片名稱
JOIN card_schemes s  ON s.card_id = uc.card_id AND s.active = 1                    -- 這張卡的所有方案
JOIN scheme_rates sr ON sr.scheme_id = s.scheme_id AND sr.card_level = uc.card_level  -- 使用者等級的費率
LEFT JOIN scheme_merchants  sm ON sm.scheme_id = s.scheme_id AND sm.merchant_id = @merchant_id     -- 有被點名嗎
LEFT JOIN scheme_categories sc ON sc.scheme_id = s.scheme_id AND sc.category    = @merchant_category -- 分類有被涵蓋嗎
WHERE uc.user_id = @user_id
  AND (s.required_condition IS NULL OR EXISTS (                                    -- 條件滿足嗎
        SELECT 1 FROM user_card_conditions cc
        WHERE cc.user_id = uc.user_id AND cc.card_id = uc.card_id
          AND cc.condition_key = s.required_condition))
  AND (s.is_default = 1 OR sm.merchant_id IS NOT NULL OR sc.category IS NOT NULL)  -- 三者之一才適用
ORDER BY c.card_name, 層, 回饋率 DESC;
```

```
+-----------+-----------+--------------+-------------------------+-----+-----------+
| 卡片      | 等級      | 方案         | 適用原因                | 層  | 回饋率    |
+-----------+-----------+--------------+-------------------------+-----+-----------+
| CUBE卡    | Level 2   | 樂饗購       | 分類 dining 被涵蓋      |   1 |      3.00 |
| CUBE卡    | Level 2   | 一般消費     | 一般消費類              |   2 |      0.30 |
| Unicard   | 簡單選    | 一般消費     | 一般消費類              |   2 |      0.30 |
| 吉鶴卡    | Standard  | 一般消費     | 一般消費類              |   2 |      1.00 |
+-----------+-----------+--------------+-------------------------+-----+-----------+
```

鼎泰豐沒有被任何方案點名,但它的分類是 `dining`,樂饗購涵蓋 `dining`,所以 CUBE 有一筆第 1 層。
CUBE 的其他方案(台塑家、集精選…)既沒點名鼎泰豐、也沒涵蓋 dining,所以不出現;
童樂匯則是因為這個使用者沒勾 `kids_club`,在條件那關就被排除。

### 步驟 3:最終推薦

在步驟 2 的基礎上,每張卡只留最好的一筆(先比層、再比回饋率),卡片之間依回饋率排序取前 3 名。
SQL 與 `docs/DB_DESIGN.md` 4.3 相同,完整內容見範例檔。

```
+-----------+-----------+-----------+--------------+-----------------------------------+
| 卡片      | 等級      | 回饋率    | 方案         | 要做的動作                        |
+-----------+-----------+-----------+--------------+-----------------------------------+
| CUBE卡    | Level 2   |      3.00 | 樂饗購       | 需切換至樂饗購權益方案            |
| 吉鶴卡    | Standard  |      1.00 | 一般消費     | NULL                              |
| Unicard   | 簡單選    |      0.30 | 一般消費     | NULL                              |
+-----------+-----------+-----------+--------------+-----------------------------------+
```

## Allen 出新版資料時

`card_rewards`(舊表,`app.py` 用):

1. 把新的匯出檔放進 `lib/data/allen/`
2. 改 `build_seed_sql.js` 最上面的來源檔名指到新檔
3. 重新產生並灌入:

   ```powershell
   node scripts/mysql/build_seed_sql.js
   & $MYSQL $CNF -e "source scripts/mysql/seed_card_rewards.sql"
   ```

`seed_card_rewards.sql` 開頭會 `TRUNCATE TABLE card_rewards`,所以是整批取代。
這張表的內容完全衍生自匯出檔,**不要直接在資料庫裡手動改資料**,下次重灌就會被蓋掉。

新版資料表之後會改用新的匯入流程(`docs/DB_DESIGN.md` 第 5 節,尚未實作)。

## 目前爬蟲資料內容(card_rewards_export_0908)

共 1236 筆:

| 卡片 | 等級 | 筆數 |
|---|---|---|
| CUBE卡(國泰世華) | Level 1 / Level 2 / Level 3 | 各 289 |
| Unicard(玉山銀行) | 簡單選 / 任意選 / UP選 | 各 99 |
| 吉鶴卡(聯邦銀行) | Standard | 72 |

## 跟 app.py 的關係

`app.py` 的 `DB_CONFIG` 預期 `host=127.0.0.1`、`user=root`、`database=credit_card_app`、
`charset=utf8mb4`。它目前查的是:

- `card_rewards` — `/api/search_rewards` 用 `merchant_name LIKE '%關鍵字%'` 加上
  `(card_name, card_level)` 的條件查詢
- `users` — `/api/register` 與 `/api/login`

改用新版資料表後,後端的連線要另外指定 `collation='utf8mb4_unicode_ci'`(原因見上方
「自己寫 SQL 時注意定序」),`scripts/db/migrate_v2.py` 的 `connect()` 就是這樣設定的。

`app.py` 裡目前有一組寫死的明碼密碼,那是 Allen 自己機器上的設定;
你本機的密碼放在 `my.local.cnf` 就好,不需要去改 `app.py`
(真的要跑 `app.py` 的話,建議把那組設定也改成讀環境變數)。
