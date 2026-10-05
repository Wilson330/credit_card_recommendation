# 資料庫

MySQL 8.0,資料庫名稱 `credit_card_app`。資料表設計見 [docs/DB_DESIGN.md](../docs/DB_DESIGN.md) 第 4 節。

資料庫是店家與回饋方案的正本。卡片規則不在資料庫,在 [backend/cards.yaml](../backend/cards.yaml)。

## 檔案

| 檔案 | 內容 |
|---|---|
| `schema.sql` | 建立資料庫與 8 張資料表 |
| `seed.sql` | 店家、別名、爬蟲原名對照、方案、回饋率、點名店家的資料(不含使用者) |
| `changes/` | 資料庫的人工修改紀錄,檔名以日期開頭 |
| `crawl/` | Allen 的爬蟲匯出檔,匯入時用 |
| `my.local.cnf.example` | 連線設定範本 |
| `my.local.cnf` | 你自己的連線設定,含密碼,不進 git |
| `reset-root-password.ps1` | 忘記 MySQL root 密碼時重設(Windows,需系統管理員 PowerShell) |

## 新機器建資料庫

以下指令都在專案根目錄執行。`mysql` 不在 PATH 上時要寫完整路徑:Windows 通常是 `& "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"`,Mac 用 Homebrew 安裝的直接打 `mysql`。

**1. 建立連線設定**,把 `password=` 換成你的 MySQL root 密碼:

```bash
cp db/my.local.cnf.example db/my.local.cnf
```

密碼只放在這個檔案裡,不要打在指令上(會留在指令紀錄中)。後端也讀這個檔案;改用環境變數 `DB_HOST`、`DB_PORT`、`DB_USER`、`DB_PASSWORD`、`DB_NAME` 也可以。

**2. 建表並灌入資料:**

```bash
mysql --defaults-extra-file=db/my.local.cnf -e "source db/schema.sql"
mysql --defaults-extra-file=db/my.local.cnf credit_card_app -e "source db/seed.sql"
```

**3. 確認筆數:**

```bash
mysql --defaults-extra-file=db/my.local.cnf credit_card_app -e "SELECT (SELECT COUNT(*) FROM merchants) AS merchants, (SELECT COUNT(*) FROM card_schemes) AS schemes, (SELECT COUNT(*) FROM scheme_merchants) AS scheme_merchants"
```

應該是 438 家店、13 個方案、418 筆點名店家。`changes/` 的修改都已經包含在 `seed.sql` 中,新機器不用另外執行。

## 資料表

| 資料表 | 內容 |
|---|---|
| `merchants` | 店家:名稱、主分類、國別(`TW`、`JP`、`global`…) |
| `merchant_aliases` | 使用者會打的其他叫法(`小七` → 7-ELEVEN 台灣門市) |
| `merchant_source_names` | 爬蟲店名 → 店家,匯入時用 |
| `card_schemes` | 各卡的回饋方案(樂饗購、百大特店…) |
| `scheme_rates` | 方案在各等級 / 方案的回饋率 |
| `scheme_merchants` | 方案點名的店家 |
| `users` | 帳號 |
| `user_cards` | 使用者的卡片與設定(JSON) |

## 修改資料

**人工修改**(改店名、分類、國別、加別名):寫成 SQL 檔放進 `changes/`,檔名以日期開頭(例如 `2026-10-05_japan_merchant_names.sql`),盡量寫成可以重複執行。在自己的資料庫執行後,重新匯出 `seed.sql`,兩者一起 commit。

**匯入新的爬蟲資料**:把匯出檔放進 `crawl/`,用 `python -m backend.importer` 匯入(見 [backend/README.md](../backend/README.md) 第 6 節),完成後重新匯出 `seed.sql`。

**重新匯出 `seed.sql`:**

```bash
mysqldump --defaults-extra-file=db/my.local.cnf --no-create-info --skip-extended-insert --complete-insert --skip-comments --skip-dump-date --no-tablespaces --skip-triggers --set-gtid-purged=OFF credit_card_app merchants merchant_aliases merchant_source_names card_schemes scheme_rates scheme_merchants > db/seed.sql
```

一筆資料一行,commit 時可以從 diff 看出改了什麼。PowerShell 的 `>` 會把檔案存成 UTF-16,要在 Git Bash 執行這個指令。

## 常用查詢

先進入互動模式,可以連續下 SQL,打 `exit` 離開:

```bash
mysql --defaults-extra-file=db/my.local.cnf credit_card_app
```

```sql
-- 查一家店:名稱、別名、被哪些方案點名(靠分類涵蓋的方案,例如樂饗購涵蓋所有國內餐廳,不會出現在這裡)
SELECT m.merchant_id, m.name, m.primary_category, m.country,
       GROUP_CONCAT(DISTINCT a.alias) AS aliases,
       GROUP_CONCAT(DISTINCT CONCAT(s.card_id, ':', s.scheme_name)) AS schemes
FROM merchants m
LEFT JOIN merchant_aliases a ON a.merchant_id = m.merchant_id
LEFT JOIN scheme_merchants sm ON sm.merchant_id = m.merchant_id
LEFT JOIN card_schemes s ON s.scheme_id = sm.scheme_id
WHERE m.name LIKE '%台北101%'
GROUP BY m.merchant_id;

-- 某張卡的方案與各等級回饋率
SELECT s.scheme_name, r.variant, r.reward_rate
FROM card_schemes s JOIN scheme_rates r ON r.scheme_id = s.scheme_id
WHERE s.card_id = 'cathay_cube'
ORDER BY s.scheme_name, r.variant;

-- 使用者與卡片設定
SELECT u.id, u.email, uc.card_id, uc.config
FROM users u LEFT JOIN user_cards uc ON uc.user_id = u.id;
```
