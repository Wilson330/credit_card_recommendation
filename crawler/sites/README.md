# 食譜格式(`crawler/sites/<card_id>.yaml`)

一張卡一份食譜,告訴食譜引擎([crawler/recipe.py](../recipe.py))要去哪個網頁、在網頁文字的哪裡找名單、回饋率多少。食譜由 agent 讀過網頁後撰寫,user 確認後存檔;之後重跑照食譜執行,結果固定。

範例:[ubot_jiho.yaml](ubot_jiho.yaml)。

## 欄位

```yaml
card_id: ubot_jiho                 # 檔名也用這個
bank_name: 聯邦銀行                 # 匯出檔的 bank_name
card_name: 吉鶴卡                   # 匯出檔的 card_name,要跟 backend/cards.yaml 的 crawl_name 一致
url: https://...                   # 要抓的網頁(有資料的那一份,例如單頁應用背後的 HTML 片段)
source_url: https://...            # 選填,寫進匯出檔給人看的網址(預設同 url)
terms_urls: [https://...]          # 選填,另外存成條款檔的網頁
levels: [Standard]                 # card_level 的值;沒有等級寫 ['']

blocks:                            # 每個 block 產生一組列
  - scheme_name: 國內人氣餐廳        # 方案名
    section: 指定人氣餐廳            # 選填,網頁上的段落標題
    list:                          # 名單:取 after 與 until 之間的文字切開
      after: 指定人氣餐廳：
      until: 一般消費回饋無上限
      separators: 、               # 預設 、｜/;括號內不切
      group_pattern: '\(\d+\)([^：]+)：'   # 選填,名單中有分組時(組名會接在 section 後面)
    # 或用 items 直接列名稱(每個都要出現在網頁上):
    # items: [國內消費]
    rate: 10                       # 回饋率;各等級不同時寫 {Level 1: 2, Level 2: 3}
    rate_evidence: 人氣餐廳最高現折10%    # 網頁上的原文,可多個;找不到就報錯
    rate_basis: 活動加碼 4% + 國內一般消費 1%   # 選填,回饋率是加總推算時說明算法(會寫進報告)
    valid_evidence: 活動期間115/7/1-115/12/31   # 選填,網頁上的活動期間原文;民國年自動換算
```

## 比對規則

- 網頁文字先去掉 `<script>`、`<style>`,換行與連續空白收成一個空白。
- `after`、`until`、`items`、`*_evidence` 比對時**忽略空白**(網頁常在字中間換行)。
- 每個 `after`、`until`、`items`、`*_evidence` 都一定要在網頁上找得到,找不到就停下來報錯(`食譜與網頁對不上`)。網頁改版時會直接失敗,不會默默產出錯的資料。

## 什麼時候不用食譜

頁面結構很特殊(例如台新Richart卡的回饋率分散在方案卡片、段落標題與等級表三個地方),寫成 Python 模組 `crawler/<card_id>.py`,實作 `URLS` 與 `parse(html, url)`,並加進 `crawler/run.py` 的 `MODULE_CARDS`。範例:[taishin_richart.py](../taishin_richart.py)。
