# 交接 v0.5:行動支付

Allen 你好,這次在推薦裡加了「用行動支付付款」的建議。後端與 Wilson 的 Flutter App 都已經改好,這份說明你那邊要做的事:更新程式碼、補資料庫裡的使用者資料、改 iOS App。

這份文件也寫給協助你的 agent:每一步都附有確認方式,照順序做,確認通過再往下。

## 0. 這次改了什麼

| 部分 | 改動 |
|---|---|
| 資料表 | **沒有改**。沒有新的資料表或欄位,`db/schema.sql`、`db/seed.sql` 都沒變 |
| 店家與方案資料 | **沒有改**。不用重新匯入爬蟲資料 |
| 使用者資料 | `user_cards.config`(JSON)多兩個欄位:`payment_methods`、`chosen_payment_methods`。用步驟 2 的腳本補上 |
| 卡片規則 | `backend/cards.yaml`:Unicard 百大特店列出 11 種行動支付,CUBE 全支付列出「全支付」 |
| 後端 API | `/api/cards`、`/api/recommend`、卡片 config 多了欄位(第 4 節) |
| iOS App | 要改三個畫面(第 5 節) |

**規則**(都在後端算好,App 不用自己判斷):
- 使用者在卡片設定勾選「這張卡綁定了哪些行動支付」。
- 推薦結果的主清單不變,一律是直接刷卡的結果。
- 用行動支付付款比主清單第 1 名還高時,後端另外回傳一筆 `payment_suggestion`。同分不建議;店家本身被點名、直接刷卡一樣高時也不會出現。
- **只限國內的店**,國外的店不會出現行動支付建議。
- 後端不知道店家收哪些行動支付,所以畫面要寫成「若店家接受…」,讓使用者自己判斷。
- Unicard 任意選:行動支付也可以挑進 8 家(與店家**合計** 8 家),要**有綁定而且有挑**才算。

完整的設計在 [DB_DESIGN.md](DB_DESIGN.md) v0.5(6.1、6.3、7.3 第 7 步、7.5、7.6)。

## 給 agent 的工作範圍

- 要改的是 **iOS App**。後端(`backend/`)、`cards.yaml`、資料表都已經完成,不要修改;如果發現後端有問題,先回報給 Allen,不要自己改。
- **不要在 App 裡計算回饋或判斷規則**,例如「國外不顯示」「同分不顯示」都是後端決定的。App 只照 API 回傳的內容顯示:`payment_suggestion` 是 null 就不顯示,有值就顯示。
- 行動支付的清單從 `/api/cards` 讀,**不要寫死在 App 裡**。
- 不要執行 `db/schema.sql`、`db/seed.sql`,也不要刪除資料庫。這次只需要執行步驟 2 的腳本。

## 1. 更新程式碼

這次的改動用壓縮檔 `credit_card_v0.5_payment_methods.zip` 傳給你,裡面有兩種格式,擇一使用:

| 內容 | 用法 |
|---|---|
| `v0.5_payment_methods.patch` | **建議用這個。** 只套用差異,不會蓋掉你自己改過的檔案 |
| `files/` | 改過與新增的完整檔案,照專案中的路徑放。直接覆蓋,你在這些檔案裡的修改會不見 |

先確認在 `feat/reward-data-schema` 分支,而且這些檔案沒有你自己的修改:

```bash
git checkout feat/reward-data-schema
git status
```

**用 patch**(把 patch 檔放在專案根目錄):

```bash
git apply --check v0.5_payment_methods.patch   # 先檢查,沒有輸出代表可以套用
git apply v0.5_payment_methods.patch
```

`--check` 報錯時代表你的檔案跟 Wilson 的版本不同,先找 Wilson,不要硬套。

**用 files/**:把 `files/` 底下的內容複製到專案根目錄,覆蓋同名檔案。

**確認**:以下檔案存在。

```bash
ls db/changes/2026-10-17_user_cards_payment_methods.sql docs/HANDOFF_ALLEN_v0.5.md
```

## 2. 資料庫:補上使用者卡片的新欄位

既有的卡片設定沒有新欄位。不補也能運作(後端會當成「沒有綁定」),但補上之後資料庫的格式會跟後端儲存的一致。腳本可以重複執行,已經有這些欄位的不會被動到。

建議先備份:

```bash
mysqldump --defaults-extra-file=db/my.local.cnf credit_card_app user_cards > ~/user_cards_backup_20261017.sql
```

執行:

```bash
mysql --defaults-extra-file=db/my.local.cnf credit_card_app < db/changes/2026-10-17_user_cards_payment_methods.sql
```

**確認**:最後印出的 `cards_missing_new_fields` 是 `0`。可以再看一下內容:

```bash
mysql --defaults-extra-file=db/my.local.cnf credit_card_app -e "SELECT user_id, card_id, config FROM user_cards"
```

補完的樣子:

| card_id | config 會多出 |
|---|---|
| `cathay_cube` | `"payment_methods": []` |
| `esun_unicard` | `"payment_methods": []`;任意選另外多 `"chosen_payment_methods": []` |
| `ubot_jiho` | 不變(吉鶴卡這次沒有行動支付) |

## 3. 後端

```bash
pip install -r backend/requirements.txt
python -m pytest backend/tests -q        # 應該 117 個全部通過
python -m backend.app --host 0.0.0.0
```

**確認**:測試全部通過;後端啟動後,`GET /api/cards` 的 Unicard 有 `payment_methods`,第一個是 `LINE Pay`。

## 4. API 改了哪些

以下是新增的欄位,原本的欄位都沒變。完整範例見 [HANDOFF_ALLEN.md](HANDOFF_ALLEN.md) 第 2 節(已更新)。

### `GET /api/cards`:每張卡多兩個欄位

| 欄位 | 內容 |
|---|---|
| `payment_methods` | 可以勾選「有綁定」的行動支付,字串清單。吉鶴卡是 `[]` |
| `pickable_payment_methods` | 挑店時也可以挑的行動支付。目前只有 Unicard 有值,跟 `payment_methods` 相同 |

`max_chosen_merchants` 的意思改成「店家與行動支付**合計**的上限」。

### `PUT /api/user/cards/{card_id}`:config 多兩個欄位

| 欄位 | 什麼時候送 | 內容 |
|---|---|---|
| `payment_methods` | 卡片的 `payment_methods` 不是空的時候 | 勾選的行動支付;沒勾就送 `[]` |
| `chosen_payment_methods` | 選到的方案在 `pick_merchants_when` 裡時(Unicard 任意選) | 挑的行動支付;沒挑就送 `[]` |

```json
{"config": {"level": "Level 2", "kids_club": false, "payment_methods": ["全支付"]}}
{"config": {"plan": "任意選", "e_bill": true, "auto_debit": true, "payment_methods": ["LINE Pay"],
            "chosen_merchants": [54], "chosen_payment_methods": ["LINE Pay"]}}
```

後端會拒絕(400,訊息可直接顯示):不在清單上的行動支付、重複、吉鶴卡帶 `payment_methods`、簡單選或 UP選帶 `chosen_payment_methods`、店家加行動支付超過 8 個。

後端回傳的 `payment_methods` 會照 `/api/cards` 的順序排好,畫面顯示時照這個順序就好。

### `POST /api/recommend`:多兩個欄位

- `results` 的每一筆多了 `payment_methods`。目前一律是 `[]`,代表直接刷卡。
- 最外層多了 `payment_suggestion`,大多數時候是 `null`。有值時:

```json
"payment_suggestion": {
  "card_id": "esun_unicard", "card_name": "Unicard", "bank_name": "玉山銀行",
  "reward_rate": 3.5, "scheme_name": "百大特店", "is_general": false,
  "required_action": "用 LINE Pay、街口支付 其中一種綁定 Unicard 付款",
  "notes": ["實際回饋依當期公告為準"],
  "payment_methods": ["LINE Pay", "街口支付"],
  "direct_reward_rate": 0.0
}
```

- `payment_methods`:回饋率相同的行動支付全部列出,用其中任一種都可以。
- `direct_reward_rate`:同一張卡直接刷卡的回饋率,用來對照。
- 其他欄位跟 `results` 裡的一筆相同。

## 5. iOS App 要改的地方

### 5.1 資料模型

- 卡片選項加上 `payment_methods`、`pickable_payment_methods`。**欄位不存在時當成空清單**:手機上可能還有舊版快取的 `/api/cards`。
- 推薦結果的每一筆加上 `payment_methods`,不存在時當成空清單。
- 推薦回應加上 `payment_suggestion`(可以是 null),內容是一筆推薦結果再加上 `direct_reward_rate`。

### 5.2 卡片設定畫面

- 卡片的 `payment_methods` 不是空的時,多一個區塊「有綁定這張卡的行動支付」,每個行動支付一個開關。
- 區塊下方的說明:「用這些行動支付付款回饋比較高時,推薦結果會另外提示」。
- 儲存時送 `config.payment_methods`。吉鶴卡不顯示這個區塊,也不送這個欄位。
- 編輯既有的卡時,開關要照 config 裡的 `payment_methods` 顯示。

### 5.3 挑店畫面(Unicard 任意選)

- 清單上方多一個「行動支付」區段,列出 `pickable_payment_methods`;下方是原本的店家。搜尋框也要能篩選行動支付。
- 標題的計數與上限改成**店家加行動支付合計**,例如「挑選店家 8 / 8」。超過時跳「已達上限」,訊息改成「最多只能挑 8 家(行動支付也算在內)」。
- 沒有綁定的行動支付,副標題顯示「尚未綁定,不會計算」(還是可以挑)。
- 完成時,店家存成 `chosen_merchants`,行動支付存成 `chosen_payment_methods`。
- 卡片設定畫面「挑選店家」那一列的計數也改成合計。說明文字改成「任意選 只有挑選的店家與行動支付享有加碼回饋,合計最多 8 家」。

### 5.4 推薦結果畫面

- 每張卡多一行「付款方式:直接刷卡」(`payment_methods` 是空的時;有值時用「 / 」把名稱串起來)。
- `payment_suggestion` 不是 null 時,在主清單**下方**多一張「行動支付建議」卡。樣式跟主清單的卡片要有區別,Flutter 版用綠色底和燈泡圖示。內容:
  - 標題「行動支付建議」,右邊是回饋率(例如 `3.5%`)
  - 只有一種:「若店家接受 LINE Pay」;多種:「若店家接受以下任一種:」,下一行「LINE Pay / 街口支付」
  - 「用 Unicard 綁定付款可拿 3.5%(直接刷卡 0%)」
  - 「方案:百大特店」
  - `required_action`(橘色,跟主清單一樣)
  - `notes`(去掉「實際回饋依當期公告為準」,跟主清單一樣)
- 主清單完全不變,不要把建議插進主清單或改變排名。

回饋率顯示跟主清單一樣去掉多餘的 0:`3.5`、`0`、`0.3`。

### 5.5 我的卡片列表

設定摘要可以加上「綁定 2 種行動支付」;「挑選 N 家」改成店家加行動支付的合計。例如「玉山銀行 · 任意選 · 綁定 1 種行動支付 · 挑選 3 家」。

### 參考實作

Wilson 的 Flutter App 都改好了,可以對照:

| 檔案 | 內容 |
|---|---|
| `lib/api/models.dart` | `CardOption`、`CardRecommendation`、`PaymentSuggestion` |
| `lib/pages/card_form_page.dart` | 行動支付開關、挑店計數 |
| `lib/pages/pick_merchants_page.dart` | 行動支付區段、合計上限 |
| `lib/pages/result_page.dart` | 付款方式、行動支付建議卡 |
| `test/cards_test.dart`、`test/home_page_search_test.dart` | 畫面行為的測試 |

## 6. 驗收

後端開著,用 App 操作:

1. 註冊一個新帳號。
2. 新增 **CUBE卡**,選 Level 2,行動支付都不勾。
3. 新增 **Unicard**,選 UP選,勾選 LINE Pay 和街口支付。
4. 搜尋:

| 搜尋 | 應該看到 |
|---|---|
| 鼎泰豐 | 主清單 #1 CUBE卡 3%(樂饗購);下方「行動支付建議」:若店家接受以下任一種 LINE Pay / 街口支付,用 Unicard 綁定付款可拿 3.5%(直接刷卡 0%) |
| 台北101 | 沒有建議卡(Unicard 直接刷卡就是百大特店 3.5%) |
| 日本三越 | 沒有建議卡(國外的店) |
| 完全不存在的店家xyz | 有建議卡,Unicard 3.5%(直接刷卡 0%) |

5. 把 Unicard 改成**簡單選**,再搜尋鼎泰豐:沒有建議卡(2% 低於 CUBE 的 3%)。
6. 把 Unicard 改成**任意選**,在挑店畫面挑 LINE Pay 和 7 家店。再挑第 9 個項目時要跳「已達上限」。儲存後搜尋「完全不存在的店家xyz」:建議卡只列 LINE Pay(街口支付有綁定但沒挑)。
7. 每個推薦結果都有「付款方式:直接刷卡」。

也可以不開 App,直接打 API 確認(先登入取得 token):

```bash
curl -s -X POST http://127.0.0.1:5000/api/recommend \
  -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
  -d '{"query": "鼎泰豐"}'
```

## 7. 這次決定的事

- 第一版只做 Unicard 百大特店與 CUBE 全支付;**吉鶴卡日本行動支付 5% 先不做**。
- 不疊加:直接刷卡與行動支付二擇一,取高的。
- CUBE 全支付要切換到全支付權益方案,**並且**用全支付付款,所以提示寫成「需切換至全支付權益方案,並用 全支付 綁定 CUBE卡 付款」。
- 儲值、繳費不在範圍內:這個系統只處理到店消費。
- 爬蟲中的「玉山Wallet愛心捐款」是捐款,不是付款方式,已經列在 `backend/import_ignore.txt`,匯入時略過。

有問題或發現對不上的地方,直接找 Wilson。
