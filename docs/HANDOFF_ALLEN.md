# 交接:iOS App 改接新後端

Allen 你好,這份說明 iOS App 要怎麼改接新的後端。

## 這次改了什麼

- **後端換成 `backend/`(Python + Flask)**,取代原本的 `app.py`。路由、資料表都不一樣,舊的 `/api/search_rewards`、`/api/autocomplete`、`/api/unicard_merchants` 不再使用。
- **推薦計算全部在後端。** App 只送「查哪家店」,後端依使用者存在資料庫的卡片設定算好回饋率,排好順序回傳。App 不用再自己比對店名或算回饋。
- **登入改發 token。** 除了註冊和登入,每個 API 都要帶 token。
- **卡片規則寫在 `backend/cards.yaml`**,改了重啟後端就生效。卡片的設定選項(等級、方案、開關)也由後端提供,App 照著畫設定畫面,不用寫死。
- **`swift_port/` 停用。** 那是把舊 Flutter 邏輯翻成 Swift 的版本,現在邏輯都在後端,不需要了。

整體設計在 [DB_DESIGN.md](DB_DESIGN.md),後端說明在 [backend/README.md](../backend/README.md)。

## 1. 在你的 Mac 上跑起後端

1. **資料庫。** 舊的 `credit_card_app` 裡的 `users` 欄位定義不同,新的建表檔遇到已存在的 `users` 會跳過,接著 `user_cards` 的外鍵就會出錯。舊資料庫只有測試資料,建議先備份再整個刪掉:

   ```bash
   mysqldump --defaults-extra-file=db/my.local.cnf credit_card_app > ~/credit_card_app_backup.sql
   mysql --defaults-extra-file=db/my.local.cnf -e "DROP DATABASE credit_card_app"
   ```

   接著照 [db/README.md](../db/README.md) 的「新機器建資料庫」建立(先建 `db/my.local.cnf`,上面兩行指令也要用到它)。

2. **後端。** 照 [backend/README.md](../backend/README.md):

   ```bash
   pip install -r backend/requirements.txt
   python -m pytest backend/tests -q        # 應該 83 個全部通過
   python -m backend.app --host 0.0.0.0     # 讓手機連得到
   ```

   iOS 模擬器連 `http://127.0.0.1:5000`;實機連 Mac 的區網 IP,例如 `http://192.168.1.20:5000`。iOS 預設擋 http,開發期間要在 Info.plist 的 App Transport Security 允許。

3. **手動試用。** 後端開著時另開一個視窗,執行 `python -m backend.try_api --cube "Level 2" --jiho-new`,就可以在終端機輸入店名看推薦結果,不用開 App。它會自動註冊測試帳號 `demo@local.test`;參數說明見 backend/README.md 第 4 節。

## 2. API

所有 API 都是 JSON。除了 `register`、`login`、`health`,都要帶 header `Authorization: Bearer <token>`。錯誤一律回 `{"error": "訊息"}`,訊息可以直接顯示給使用者。

| 方法與路徑 | 送出 | 成功時回傳 |
|---|---|---|
| `POST /api/register` | `{email, password, full_name, birthday}` | 201 |
| `POST /api/login` | `{email, password}` | `{token, user}` |
| `GET /api/cards` | — | 各卡的設定選項 |
| `GET /api/cards/{card_id}/pickable_merchants` | — | 可挑的店 `[{merchant_id, name}]` |
| `GET /api/user/cards` | — | 我的卡片 |
| `PUT /api/user/cards/{card_id}` | `{"config": {...}}` | 存好的卡片 |
| `DELETE /api/user/cards/{card_id}` | — | `{message}` |
| `GET /api/merchants/suggest?q=小七` | — | `[{merchant_id, name}]`,最多 10 筆 |
| `POST /api/recommend` | `{merchant_id}` 或 `{query}` | 推薦結果 |

以下回應都是實際呼叫後端得到的。

### 註冊與登入

- 註冊:密碼至少 8 個字元,`birthday` 格式 `YYYY-MM-DD`(用來判斷慶生月)。email 已被註冊回 409。
- 登入失敗一律回 401「帳號或密碼錯誤」,不會告訴對方帳號存不存在。

```json
{
  "token": "eyJ0eXAiOiJKV1QiLCJh...",
  "user": {"email": "...", "full_name": "王小明", "birthday": "1995-03-15"}
}
```

- token 有效 30 天,存在 Keychain。
- **任何 API 回 401,就清掉 token、回到登入畫面。** 這代表 token 過期或無效。

### 卡片設定畫面:`GET /api/cards`

```json
[
  {"card_id": "cathay_cube", "name": "CUBE卡", "bank": "國泰世華",
   "rate_by": "level", "options": ["Level 1", "Level 2", "Level 3"],
   "toggles": [{"key": "kids_club", "label": "童樂匯"}],
   "pick_merchants_when": [], "max_chosen_merchants": null},
  {"card_id": "esun_unicard", "name": "Unicard", "bank": "玉山銀行",
   "rate_by": "plan", "options": ["簡單選", "任意選", "UP選"],
   "toggles": [{"key": "e_bill", "label": "電子帳單"}, {"key": "auto_debit", "label": "自動扣繳"}],
   "pick_merchants_when": ["任意選"], "max_chosen_merchants": 8},
  {"card_id": "ubot_jiho", "name": "吉鶴卡", "bank": "聯邦銀行",
   "rate_by": null, "options": [],
   "toggles": [{"key": "new_customer", "label": "新戶自動扣繳"}],
   "pick_merchants_when": [], "max_chosen_merchants": null}
]
```

設定畫面照這份資料畫,三張卡共用同一個畫面:

- `rate_by` 是 `level` 或 `plan` 時,顯示 `options` 讓使用者選一個,存成 `config.level` 或 `config.plan`。`null` 就不顯示。
- 每個 `toggles` 顯示一個開關,標題用 `label`,存成 `config[key] = true/false`。
- 選到的方案在 `pick_merchants_when` 裡時(Unicard 任意選),顯示「挑選店家」:清單來自 `pickable_merchants`,最多 `max_chosen_merchants` 家,把 `merchant_id` 存成 `config.chosen_merchants`。

`PUT` 的 config 範例:

```json
{"config": {"level": "Level 2", "kids_club": false}}
{"config": {"new_customer": true}}
{"config": {"plan": "任意選", "e_bill": true, "auto_debit": true, "chosen_merchants": [54]}}
```

不合法的設定回 400,錯誤訊息可直接顯示,例如「CUBE卡 的 level 要是以下其中之一:Level 1、Level 2、Level 3」。

**我的卡片以資料庫為準。** 新增或修改時先 `PUT`,成功後才更新手機上的資料;登入後用 `GET /api/user/cards` 覆蓋手機上的資料。

### 搜尋與推薦

自動補全:使用者打字時呼叫 `suggest`。

- 同時只送一個請求;結果回來時,如果輸入框的文字已經變了,就用最新的文字再送一次。
- 注音還在組字時不要送(UIKit 的 `markedTextRange` 不是 nil 的時候)。

推薦:

- 使用者點了建議清單 → 送 `{"merchant_id": 54}`
- 使用者直接按搜尋 → 送 `{"query": "鼎泰豐信義店"}`,後端會找最接近的店

```json
{
  "merchant": {"merchant_id": 54, "name": "台北101", "category": "department_store", "country": "TW"},
  "merchant_found": true,
  "message": null,
  "results": [
    {"card_id": "esun_unicard", "card_name": "Unicard", "bank_name": "玉山銀行",
     "reward_rate": 3.5, "scheme_name": "百大特店", "is_general": false,
     "required_action": null, "notes": ["實際回饋依當期公告為準"]},
    {"card_id": "cathay_cube", "card_name": "CUBE卡", "bank_name": "國泰世華",
     "reward_rate": 2.0, "scheme_name": "樂饗購", "is_general": false,
     "required_action": "需切換至樂饗購權益方案", "notes": ["實際回饋依當期公告為準"]},
    {"card_id": "ubot_jiho", "card_name": "吉鶴卡", "bank_name": "聯邦銀行",
     "reward_rate": 1.5, "scheme_name": "國內一般消費", "is_general": true,
     "required_action": null, "notes": ["實際回饋依當期公告為準"]}
  ]
}
```

- `results` 已經依回饋率由高到低排好,第一張就是推薦的卡。
- `reward_rate` 是百分比數字:`3.5` 代表 3.5%。
- `required_action` 不是 null 時要顯示,提醒使用者刷卡前先切換方案。
- 找不到店時 `merchant` 是 null、`merchant_found` 是 false,`message` 是「此店家不在回饋名單中,以一般消費計算」。`results` 照樣有資料,是各卡的一般消費回饋。

### 參考實作

Wilson 的 Flutter App 已經改接這套 API,畫面流程可以參考:

| 檔案 | 內容 |
|---|---|
| `lib/api/api_client.dart` | 呼叫 API、帶 token、401 處理 |
| `lib/pages/card_form_page.dart` | 依 `/api/cards` 畫的卡片設定畫面 |
| `lib/pages/pick_merchants_page.dart` | Unicard 任意選挑店 |
| `lib/pages/home_page.dart` | 自動補全(同時一個請求、組字中不送) |
| `lib/pages/result_page.dart` | 推薦結果 |

## 3. 安全性

- **原本 `app.py` 裡寫死了資料庫密碼。** 新後端從 `db/my.local.cnf` 或環境變數讀密碼,這兩處都不會進 git。舊的 `app.py` 如果放在任何 repo 裡,請確認沒有被 commit;已經 commit 過的話,要換資料庫密碼。
- 原本 `app.py` 是 `debug=True` 又監聽 `0.0.0.0`,同一個網路的人可以透過除錯頁面在你電腦上執行程式。新後端用 `--host 0.0.0.0` 啟動時會自動關掉除錯模式。
- token 的簽名密鑰在 `backend/.secret_key`,第一次啟動時自動產生,不進 git。正式上線時改用環境變數 `APP_SECRET_KEY`。

## 4. 爬蟲資料更新

新的匯出檔維持 0908 版的 JSON 格式,放進 `db/crawl/`,再用匯入工具處理:

```bash
python -m backend.importer db/crawl/新的匯出檔.json --dry-run   # 先看報告
python -m backend.importer db/crawl/新的匯出檔.json             # 正式匯入
```

報告會列出對不到既有店家的爬蟲店名,並附上建議的處理指令。細節見 [backend/README.md](../backend/README.md) 第 6 節。

## 5. 請你確認

以下兩點目前先照這個設定實作,請幫忙對照官網條款:

1. 吉鶴卡「新戶自動扣繳」加碼是 0.5%,只加在國內一般消費與國內日系特店。
2. Unicard 在國外的一般消費和國內一樣:電子帳單加自動扣繳 1%、只有電子帳單 0.3%、只有自動扣繳 0%。
