# 資料 Schema 定義（v1）

這份文件是目前為止跟 Allen 對齊資料格式用的規格書。三個核心概念：`merchants`、`merchant_aliases`、每張卡各自的 `card_reward_rules`。

status：草稿定案版，還沒經過完整實作驗證，等 evaluator 改寫後再確認一次。

## 1. merchants

商家本體資料。

| 欄位 | 型別 | 說明 |
|---|---|---|
| `merchant_id` | string | 唯一值 |
| `canonical_name` | string | 系統內部使用的標準名稱 |
| `display_name` | string | 顯示給使用者看的名稱 |
| `primary_category` | string | 單一主分類，給沒有更細緻分類需求時的預設值 |
| `subcategory` | string \| null | 更細的分類 |
| `tags` | string[] | **可以有多個分類標籤**，card_reward_rules 的 `category` 規則是比對這個欄位，不是只比對 `primary_category`（原因：像誠品生活這種商家可能同時符合「書店」和「百貨」兩種分類規則） |
| `channel` | string | `offline` / `online` / `both` |
| `country` | string | 例如 `TW` |
| `active` | bool | |

範例（`lib/data/merchants.json`，由 `scripts/build_merchants.js` 產生）：
```json
{
  "merchant_id": "m_藏壽司",
  "canonical_name": "藏壽司",
  "display_name": "藏壽司",
  "primary_category": "dining",
  "subcategory": null,
  "tags": ["restaurant", "chain_store", "japanese_food"],
  "channel": "offline",
  "country": "TW",
  "active": true
}
```

**category 規則的 `match_value` 必須是 `tags[]` 裡真的會出現的字串**（例如 `restaurant`、`lodging`），不是 `primary_category` 的值（例如 `dining`、`hotel`）——這兩者不一樣，曾經因為搞混這兩個而讓 category 規則完全比對不到，已修正。

## 2. merchant_aliases

正式 schema 是一筆別名一列（欄位如下），但**目前實作用的是簡化版**：`merchants.json` 每筆商家直接帶一個 `aliases: string[]`（2026-08-06 已實作，`MerchantResolver` 完全比對／子字串比對都會一併檢查 `canonical_name` 和 `aliases`）。目前只針對明顯需要別名的商家補了（國際品牌的英文名、常見中文簡稱，例如「肯德基」→`["KFC"]`），不是每一家都有，覆蓋率還很低，一樣標記 `needsReview`。

正式（尚未實作）schema：

| 欄位 | 型別 | 說明 |
|---|---|---|
| `alias_id` | string | |
| `merchant_id` | string | 對應 merchants.merchant_id |
| `alias_text` | string | 原始文字 |
| `alias_normalized` | string | 正規化後文字（去空白、大小寫、全形半形統一後） |
| `language` | string | `zh-TW` / `en` / `ja` 等 |
| `weight` | number | 排序用權重 |
| `active` | bool | |

## 3. card_reward_rules（每張卡一份檔案，例如 `cube_reward_rules.json`）

| 欄位 | 型別 | 說明 |
|---|---|---|
| `rule_id` | string | |
| `card_id` | string | 必須對應到 `WalletCard.cardId`（目前是 `cathay_cube` / `ubot_jiho`，**不是** `cube_card`，之前 mock 檔案裡這個欄位是錯的，這次已修正） |
| `rule_type` | `"merchant" \| "category" \| "default"` | 只有這三種，v1 不需要 `priority`，查詢順序固定寫死為 merchant > category > default |
| `match_value` | string | `merchant` 型別：對應商家名稱（見下方「已知簡化」）；`category` 型別：對應 `merchants.tags` 裡的其中一個標籤；`default` 型別固定為 `"*"` |
| `applicable_level` | string \| null | **這次新增的欄位**。CUBE 卡的玩數位/樂饗購/趣旅行/集精選回饋率會隨 `level_1`/`level_2`/`level_3` 變動，這個欄位用來標示這條規則只在使用者選了哪個等級時適用；`null` 代表跟等級無關（例如吉鶴卡，或 CUBE 的台塑家/全支付方案） |
| `reward_rate` | number | 百分比數字，例如 `3.0` 代表 3.0% |
| `benefit_label` | string | 對應到權益方案名稱，例如「樂饗購」 |
| `required_action` | string \| null | 例如「需切換至樂饗購權益方案」；不需要動作則為 `null` |
| `required_conditions` | string[] | **2026-08-06 新增**。這條規則只有在使用者卡片設定滿足**全部**列出的條件時才算候選（跟 `applicable_level` 一樣是「篩選掉不合格的規則」，不是加分項）。目前用到的值：`"new_customer"`（吉鶴新戶）、`"kids_club"`（CUBE 童樂匯）。空陣列代表沒有額外條件限制。取代了原本用假商家名稱硬塞的做法（見下方 `is_synthetic_condition`）——但只取代了「使用者卡片設定就能直接回答」的那種條件；還需要额外輸入（例如支付方式、目前所在國家）才能判斷的條件，`is_synthetic_condition` 還是繼續用 |
| `constraints` | string[] | 限制條件說明文字 |
| `is_synthetic_condition` | bool | 預設 false。true 代表這條規則的 `match_value` 其實不是真實商家名稱，而是像「新戶日本實體消費(行動支付)」這種情境代稱。**2026-08-06 起，只保留給「需要额外輸入才能判斷」的條件**（例如支付方式、所在國家）——單純的使用者卡片布林設定（新戶、童樂匯）已經改用上面的 `required_conditions` 正式處理，不再用這個欄位 |
| `active` | bool | |

**category 規則的比對邏輯**：檢查候選商家的 `merchants.tags` 是否包含 `match_value`。如果同一張卡的多條 category 規則同時命中同一個商家（例如「餐廳」跟「百貨」都命中），evaluator 取 `reward_rate` 較高的那一條，不需要额外的 priority 欄位。同樣的「取最高」邏輯現在也適用於 `rule_type: default`——一張卡可以有多條 default 規則（例如吉鶴卡的「一般 1.0%」和「新戶 1.5%」），符合條件的裡面取最高。

**已知簡化 / 待辦事項（不是最終設計，只是這次為了先讓資料跑起來的暫時決定）：**
- `merchant` 型別的 `match_value` 目前直接放**正規化後的原始商家名稱字串**，還沒有真的對應到 `merchants.merchant_id`（`RuleMatcher` 是直接字串比對，不是先查表拿 ID 再比對）。
- 「慶生月」依照之前的決定先不轉換進來——它的門檻是「現在是不是持卡人生日當月」，是時間性條件，`required_conditions`（靜態、每次查詢都一樣的旗標）沒辦法表示，跟「童樂匯」性質不同，所以還是繼續擱置。
- `merchants.json` 裡標記 `needsReview: true`（透過 `node scripts/build_merchants.js` 印出）的項目是 AI 第一輪分類，還沒有人工逐一確認過，尤其是新增的知名連鎖品牌清單（非 Allen 爬蟲資料，是額外整理來擴充「使用者搜尋到資料庫沒有的店」這個情境覆蓋率的）。
- `merchants.json` 目前只涵蓋 Allen 爬蟲資料裡出現過的商家 + 一批額外整理的知名連鎖品牌，遠不是台灣商家的完整清單。使用者搜尋到完全沒收錄的店，還是會落到 `default` 規則。長期怎麼處理「資料庫沒有的店」是目前最大的未解問題，決定是：優先持續擴充 `merchants.json`（離線、人工審核），而不是在查詢當下即時呼叫 AI 判斷分類——後者的不確定性、延遲、成本目前評估不划算。
- 吉鶴卡「日本一般消費」底下跟支付方式/所在國家有關的條件列（例如「日本行動支付(Apple Pay/Google Pay)」「新戶日本實體消費(行動支付)」），還是繼續用 `is_synthetic_condition` 標記、還不會被觸發——因為就算做了 `required_conditions`，我們也還沒有任何地方讓使用者輸入「你現在人在日本」「這筆要用什麼支付方式」，缺的是輸入介面，不是規則格式問題。

**已確認、不再是假設的部分（2026-08-06 與 Allen 對齊）：**
- CUBE 卡「一般消費」的預設回饋率確認為 0.3%。
- CUBE 卡「台塑家」「全支付」兩個方案確認也需要切換權益方案，`required_action` 已補上。
- 「樂饗購也涵蓋國內餐廳」「趣旅行也涵蓋國內飯店」這兩條廣義分類條款確認存在，已加進 `cube_reward_rules.json`（`rule_type: category`，`match_value` 分別是 `restaurant` / `lodging`）。適用費率是推論值（比照同方案具名商家費率），沒有另外向 Allen 確認過這個費率本身。

**2026-08-06 重新設計（跟 Allen 的後端邏輯對齊後）：**
- Allen 的 Flask 後端用「使用者卡片的布林狀態（是否新戶／是否開通童樂匯）+ `scheme_name` 比對」處理條件式規則，比我們原本「拿假商家名稱塞進 merchant 規則」的做法更乾淨，所以採用了同樣的精神，加上 `required_conditions` 欄位
- 因此重新啟用「童樂匯」方案（73 筆真實商家資料，門檻是 `required_conditions: ["kids_club"]`，`required_action` 是假設值、尚未跟 Allen 確認）
- 吉鶴卡「新戶自動扣繳加碼(國內一般消費)」這筆也改用 `required_conditions: ["new_customer"]` 的 `default` 規則正式處理（原本 1.0% 一般消費、新戶變成 1.5%），不再是查不到的假商家
