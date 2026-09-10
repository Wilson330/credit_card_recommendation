# 本機 MySQL 設定

把 Allen 匯出的信用卡回饋資料灌進本機 MySQL，讓 `app.py` 可以在本機跑起來。

## 現況（2026-09-10 確認）

這台機器**已經裝好 MySQL Server 8.0，不用再下載**：

- 安裝位置：`C:\Program Files\MySQL\MySQL Server 8.0`
- Windows 服務 `MySQL80` 正在執行中，3306 埠有在監聽
- 已安裝的元件：MySQL Server / Workbench / Shell / Router 8.0
- `mysql` 指令沒有加進 PATH，所以下面的指令都用完整路徑

## 檔案說明

| 檔案 | 用途 | 進版控？ |
|---|---|---|
| `schema.sql` | 建立 `credit_card_app` 資料庫、`card_rewards` 與 `users` 資料表 | 是 |
| `build_seed_sql.js` | 把 Allen 的匯出 JSON 轉成 INSERT script | 是 |
| `seed_card_rewards.sql` | 上面產生出來的資料，1236 筆 | 是（可重新產生） |
| `my.local.cnf.example` | 連線設定範本 | 是 |
| `my.local.cnf` | 你自己的連線設定，**內含密碼** | **否**（已在 .gitignore） |

## 首次設定

1. 複製連線設定範本，並填入你的 MySQL root 密碼：

   ```bash
   cp scripts/mysql/my.local.cnf.example scripts/mysql/my.local.cnf
   ```

   然後編輯 `scripts/mysql/my.local.cnf`，把 `password=` 那行換成真正的密碼。

   密碼放檔案而不是直接打在指令上，是因為 `mysql -p你的密碼` 會被記進 shell 歷史紀錄，
   同一台機器上其他程式用 `ps` 也看得到。這個檔案已經被 `.gitignore` 擋住，不會進版控。

2. 建立資料庫與資料表：

   ```bash
   "/c/Program Files/MySQL/MySQL Server 8.0/bin/mysql.exe" \
     --defaults-extra-file=scripts/mysql/my.local.cnf < scripts/mysql/schema.sql
   ```

3. 灌入回饋資料：

   ```bash
   "/c/Program Files/MySQL/MySQL Server 8.0/bin/mysql.exe" \
     --defaults-extra-file=scripts/mysql/my.local.cnf < scripts/mysql/seed_card_rewards.sql
   ```

## Allen 出新版資料時

1. 把新的匯出檔放進 `lib/data/allen/`
2. 改 `build_seed_sql.js` 最上面的 `SOURCE_JSON` 指到新檔名
3. `node scripts/mysql/build_seed_sql.js`
4. 重跑上面第 3 步

`seed_card_rewards.sql` 開頭會 `TRUNCATE TABLE card_rewards`，所以是整批取代，
不會殘留上一版已經被刪掉的資料。這張表的內容完全衍生自匯出檔，
**不要直接在資料庫裡手動改資料**，下次重灌就會被蓋掉。

## 目前資料內容（card_rewards_export_0908）

共 1236 筆：

| 卡片 | 等級 | 筆數 |
|---|---|---|
| CUBE卡（國泰世華） | Level 1 / Level 2 / Level 3 | 各 289 |
| Unicard（玉山銀行） | 簡單選 / 任意選 / UP選 | 各 99 |
| 吉鶴卡（聯邦銀行） | Standard | 72 |

比 7 月那版（933 筆）多了 **Unicard 的 297 筆**，這是之前完全沒有資料的一張卡。

## 跟 app.py 的關係

`app.py` 的 `DB_CONFIG` 預期 `host=127.0.0.1`、`user=root`、`database=credit_card_app`、
`charset=utf8mb4`，跟這裡建出來的結構一致。它會查：

- `card_rewards` — `/api/search_rewards` 用 `merchant_name LIKE '%關鍵字%'` 加上
  `(card_name, card_level)` 的條件查詢
- `users` — `/api/register` 與 `/api/login`。登入功能目前擱置中（iOS 那邊還沒接），
  但表沒建的話那兩支 API 一打就會 500，所以先把結構建好、內容留空。

`app.py` 裡目前有一組寫死的明碼密碼，那是 Allen 自己機器上的設定；
你本機的密碼放在 `my.local.cnf` 就好，不需要去改 `app.py`
（真的要跑 `app.py` 的話，建議把那組設定也改成讀環境變數）。
