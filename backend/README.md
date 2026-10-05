# 後端(本機測試)

信用卡回饋推薦的後端:Python + Flask + MySQL。設計見 [docs/DB_DESIGN.md](../docs/DB_DESIGN.md)。

以下指令都在**專案根目錄**、已 activate 的 conda 環境(提示字元前有 `(base)`)中執行。

## 1. 安裝套件(只需一次)

```powershell
pip install -r backend/requirements.txt
```

## 2. 資料庫

建資料庫的步驟見 [db/README.md](../db/README.md)(建表 + 灌入店家與方案資料,438 家店、13 個方案)。

連線設定讀 `db/my.local.cnf`;也可以用環境變數 `DB_HOST`、`DB_PORT`、`DB_USER`、`DB_PASSWORD`、`DB_NAME` 覆蓋。

## 3. 啟動後端

```powershell
python -m backend.app
```

跑在 `http://127.0.0.1:5000`。iOS 模擬器在同一台 Mac 上可以直接連;要讓**實機手機**連,改用:

```powershell
python -m backend.app --host 0.0.0.0
```

此時除錯模式會被強制關閉(除錯頁面可以執行任意程式,不能對網路開放)。

啟動時會檢查 `cards.yaml` 與資料庫是否一致,有問題會印出 WARNING。`cards.yaml` 寫錯會直接無法啟動,並說明哪裡錯。

## 4. 手動試用

後端開著,另開一個視窗:

```powershell
python -m backend.try_api --cube "Level 2" --jiho-new --unicard 任意選 --e-bill --auto-debit --pick 台北101
```

會用測試帳號 `demo@local.test` 登入(沒有就自動註冊)、設定卡片,然後讓你輸入店名查推薦:

```
店名> 台北101
  建議:#54 台北101
  店家:台北101(#54,department_store,TW)
  1. Unicard   3.50%  百大特店
  2. CUBE卡     3.00%  樂饗購,需切換至樂饗購權益方案
  3. 吉鶴卡       1.50%  國內一般消費
```

- 下次執行不帶卡片參數,就沿用上次的設定
- `--kids-club` 加入童樂匯;`--jiho-old` 改成非新戶;`--no-cube` 等移除卡片
- `--birthday-this-month` 換一個生日在本月的測試帳號,測慶生月
- 輸入 `#編號` 直接用店家編號查

**用 curl 或 PowerShell 直接打 API 時要注意:** Windows 預設不是用 UTF-8 送中文,後端會收到亂碼(搜尋不到、或回「請用 JSON 格式送出資料」)。用 `try_api` 就沒有這個問題。iOS 與 Flutter 都是 UTF-8,不受影響。

## 5. 自動測試

```powershell
python -m pytest backend/tests -q
```

- `test_recommend.py`、`test_rules.py`、`test_cardconfig.py`:計算與檢查邏輯,不需要資料庫
- `test_api.py`:連本機 MySQL 跑完整流程(註冊、登入、加卡、搜尋、推薦)。測試帳號都是 `pytest-*@test.local`,跑完自動刪除

## 6. 匯入新的爬蟲資料

```powershell
python -m backend.importer db/crawl/新的匯出檔.json --dry-run   # 先看報告
python -m backend.importer db/crawl/新的匯出檔.json             # 正式匯入
```

報告中「對不到店家的爬蟲店名」會附上建議,用以下指令處理後再重跑:

```powershell
python -m backend.importer --map "店名" 店家編號                       # 是既有的店(改名、異寫)
python -m backend.importer --new "店名" --category dining --country TW # 是新店
python -m backend.importer --ignore "店名"                             # 不是店家,以後略過
```

## API 一覽

除了 `register`、`login`、`health`,都要帶 `Authorization: Bearer <token>`。錯誤一律回 `{"error": "訊息"}`。

| 方法與路徑 | 送出 | 回傳 |
|---|---|---|
| `GET /api/health` | — | 狀態、卡片清單、店家數 |
| `POST /api/register` | `{email, password, full_name, birthday}`(生日 `YYYY-MM-DD`,密碼至少 8 字元) | 201;email 重複 409 |
| `POST /api/login` | `{email, password}` | `{token, user}`;失敗一律 401「帳號或密碼錯誤」 |
| `GET /api/merchants/suggest?q=` | 輸入文字 | `[{merchant_id, name}]`,最多 10 筆 |
| `POST /api/recommend` | `{merchant_id}` 或 `{query}` | `{merchant, merchant_found, message, results}` |
| `GET /api/cards` | — | 各卡的設定選項(等級/方案、開關與顯示名稱、挑店上限) |
| `GET /api/cards/{card_id}/pickable_merchants` | — | 可挑的店(Unicard 百大特店) |
| `GET /api/user/cards` | — | 我的卡片與 config |
| `PUT /api/user/cards/{card_id}` | `{"config": {...}}` | 儲存後的 config;不合法 400 |
| `DELETE /api/user/cards/{card_id}` | — | 移除 |

config 範例:

```json
{"config": {"level": "Level 2", "kids_club": false}}                                   // CUBE
{"config": {"new_customer": true}}                                                    // 吉鶴卡
{"config": {"plan": "任意選", "e_bill": true, "auto_debit": true, "chosen_merchants": [54]}}  // Unicard
```

## 檔案

| 檔案 | 內容 |
|---|---|
| `cards.yaml` | 卡片規則(改了要重啟後端) |
| `app.py` | API 路由 |
| `recommend.py` | 推薦計算(純函式) |
| `service.py` | 資料庫查詢 |
| `rules.py` | 載入與檢查 `cards.yaml` |
| `auth.py` | 註冊、登入、token |
| `cardconfig.py` | 卡片設定的檢查 |
| `importer.py` | 爬蟲匯入 |
| `try_api.py` | 本機手動試用工具 |
| `.secret_key` | token 簽名密鑰,第一次啟動自動產生,不進版控 |
