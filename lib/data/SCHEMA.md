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

一筆別名一列，正式 schema。目前 mock 階段允許簡化成 merchant 上的 `aliases: string[]`。

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
| `constraints` | string[] | 限制條件說明文字 |
| `is_synthetic_condition` | bool | **這次新增的欄位，預設 false**。true 代表這條規則的 `match_value` 其實不是真實商家名稱，而是像「新戶日本實體消費(行動支付)」這種情境代稱，是 v1 為了先跑通、暫時把條件式規則塞進 merchant 規則格式裡的權宜做法，之後要重構 |
| `active` | bool | |

**category 規則的比對邏輯**：檢查候選商家的 `merchants.tags` 是否包含 `match_value`。如果同一張卡的多條 category 規則同時命中同一個商家（例如「餐廳」跟「百貨」都命中），evaluator 取 `reward_rate` 較高的那一條，不需要额外的 priority 欄位。

**已知簡化 / 待辦事項（不是最終設計，只是這次為了先讓資料跑起來的暫時決定）：**
- `merchant` 型別的 `match_value` 目前直接放**正規化後的原始商家名稱字串**，還沒有真的對應到 `merchants.merchant_id`（`RuleMatcher` 是直接字串比對，不是先查表拿 ID 再比對）。
- 「慶生月」「童樂匯」兩個方案，依照之前的決定先不轉換進來，等未來要擴充新方案時再依同樣模式加入。
- `merchants.json` 裡標記 `needsReview: true`（透過 `node scripts/build_merchants.js` 印出）的項目是 AI 第一輪分類，還沒有人工逐一確認過，尤其是新增的知名連鎖品牌清單（非 Allen 爬蟲資料，是額外整理來擴充「使用者搜尋到資料庫沒有的店」這個情境覆蓋率的）。
- `merchants.json` 目前只涵蓋 Allen 爬蟲資料裡出現過的 273 家商家 + 一批額外整理的知名連鎖品牌，遠不是台灣商家的完整清單。使用者搜尋到完全沒收錄的店，還是會落到 `default` 規則。長期怎麼處理「資料庫沒有的店」是目前最大的未解問題，決定是：優先持續擴充 `merchants.json`（離線、人工審核），而不是在查詢當下即時呼叫 AI 判斷分類——後者的不確定性、延遲、成本目前評估不划算。

**已確認、不再是假設的部分（2026-08-06 與 Allen 對齊）：**
- CUBE 卡「一般消費」的預設回饋率確認為 0.3%。
- CUBE 卡「台塑家」「全支付」兩個方案確認也需要切換權益方案，`required_action` 已補上。
- 「樂饗購也涵蓋國內餐廳」「趣旅行也涵蓋國內飯店」這兩條廣義分類條款確認存在，已加進 `cube_reward_rules.json`（`rule_type: category`，`match_value` 分別是 `restaurant` / `lodging`）。適用費率是推論值（比照同方案具名商家費率），沒有另外向 Allen 確認過這個費率本身。
