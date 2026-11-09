# 爬蟲(Wilson 版)

從銀行官網抓信用卡回饋資料,產出符合 [docs/CRAWL_FORMAT.md](../docs/CRAWL_FORMAT.md) 的匯出檔。起始說明見 [docs/CRAWLER_KICKOFF.md](../docs/CRAWLER_KICKOFF.md)。

圖解版說明:[docs/CRAWLER.html](../docs/CRAWLER.html)(用瀏覽器開)。

設計:**agent 介入的爬蟲**。agent 找官網頁面、為每個網站寫一份「食譜」(user 確認),之後由程式照食譜執行,結果固定;程式自動檢查後,agent 先審核、寫審核報告,再交給 user。整個流程寫在 skill [.claude/skills/crawl-card/SKILL.md](../.claude/skills/crawl-card/SKILL.md)(對 Claude 說「爬某某銀行的某某卡」就會用到)。

| 卡 | 解析方式 | 狀態 |
|---|---|---|
| 台新Richart卡 `taishin_richart` | 模組 [taishin_richart.py](taishin_richart.py) | 646 列,新卡,`cards.yaml` 還沒有 |
| 聯邦吉鶴卡 `ubot_jiho` | 食譜 [sites/ubot_jiho.yaml](sites/ubot_jiho.yaml) | 72 列,店名與 0908 相同;回饋率照抄網頁不加總,2 個方案跟 0908 不同 |

## 安裝

```bash
pip install -r crawler/requirements.txt     # requests、beautifulsoup4、PyYAML
```

Python 3.9,Anaconda 環境。請在 **Anaconda Prompt** 執行(或先 `conda activate base`):沒有 activate 時 Python 找不到 SSL 的 DLL,抓 https 會出現 `SSL module is not available`。

## 執行

在專案根目錄:

```bash
python -m crawler.run ubot_jiho                    # 有快取就讀快取
python -m crawler.run ubot_jiho --refresh          # 重新抓網頁
python -m crawler.run ubot_jiho --compare db/crawl/card_rewards_export_0908.json
python -m backend.importer db/crawl/card_rewards_export_20261110_ubot_jiho.json --check
python -m pytest crawler/tests -q                  # 不連網路
```

一次執行會產出:

| 產出 | 位置 |
|---|---|
| 匯出檔 | `db/crawl/card_rewards_export_<抓取日期>_<card_id>.json` |
| 條款檔 | `db/crawl/terms/<card_id>/` |
| 自動報告 | `crawler/reports/<card_id>_<抓取日期>.md`:列數與回饋率、解析備註、自動檢查、與參考檔的差異。每次執行重寫 |
| agent 審核 | `crawler/reports/<card_id>_<抓取日期>.review.md`:手寫,重跑不會蓋掉 |
| 原始網頁快取 | `crawler/.cache/<card_id>/`(不進版控) |

- 匯出檔名多了 `_<card_id>`,避免同一天爬不同卡時互相覆蓋。
- **參考檔**:沒指定 `--compare` 時,自動找 `db/crawl` 中同一張卡最近的另一份匯出檔;沒有的話找含有這張卡的綜合匯出檔(例如 0908)。
- **重跑一致**:網頁讀快取,`updated_at` 用快取的抓取時間,列依(卡、等級、方案、段落、名稱)排序後編號,網頁沒變時輸出逐位元組相同。

## 檔案

| 檔案 | 內容 |
|---|---|
| `common.py` | 共用:抓網頁(robots.txt、請求間隔 3 秒、快取)、整理空白、切店名(括號內不切)、排序編號、寫檔 |
| `recipe.py` | 食譜引擎,格式見 [sites/README.md](sites/README.md) |
| `sites/<card_id>.yaml` | 各卡食譜 |
| `taishin_richart.py` | 台新Richart卡的解析模組(頁面太特殊,沒用食譜) |
| `checks.py` | 自動檢查 |
| `diff.py` | 比較兩份匯出檔 |
| `run.py` | 執行入口 |
| `tests/` | 測試 |

## 自動檢查(`checks.py`)

檢查「抄得對不對」;格式由 `backend.importer --check` 負責。

| 檢查 | 等級 | 內容 |
|---|---|---|
| 溯源 | 錯誤 | `merchant_name`、`section` 要逐字出現在網頁上(忽略空白)。擋解析錯誤與編造 |
| 回饋率 | 錯誤 | 要大於 0,且不超過網頁上出現過的最大「最高 X%」 |
| 回饋率出處 | 警告 | 回饋率的數字沒出現在網頁上,可能是加總推算的 |
| 分隔符號 / 句子 / 過長 | 警告 | 名稱可能沒切乾淨,或其實是說明文字 |
| 重複 | 警告或提示 | 同等級、方案、名稱出現多次;回饋率不同是警告 |
| 等級 | 警告 | 各等級的(方案、段落、名稱)應該一樣 |
| 期間 | 警告或提示 | 已過期或還沒開始的列 |

食譜引擎另有一層保護:食譜中的錨點、名稱、回饋率依據原文在網頁上找不到就直接失敗,網頁改版不會默默產出錯的資料。

## 各卡說明

### 台新Richart卡

- 網頁:<https://mkp.taishinbank.com.tw/s/2025/RichartCard_2025/index.html>(靜態 HTML,網站沒有 robots.txt)
- 回饋率分散在方案卡片(LEVEL2)、段落標題(Chill刷、Pay著刷)、等級表(LEVEL1)三處,所以寫成模組
- `section`:Chill刷 有兩層,用 ` > ` 接起來,例如 `瘋聚會 > 【日常續命】`
- 待確認事項見 [reports/taishin_richart_20261110.review.md](reports/taishin_richart_20261110.review.md)

### 聯邦吉鶴卡

- 卡片頁是 Vue 單頁應用;資料在 HTML 片段 `https://card.ubot.com.tw/ecard_source/html/CardDetail/cardDetail202.htm`,片段檔名來自卡片清單 API `https://card.ubot.com.tw/eCardServiceAPI/api/Cards`。不需要 Playwright
- `scheme_name` 沿用 0908;回饋率照抄網頁(加碼、一般消費、行動支付各自一列,不加總)
- 已知頁面記在 [banks.yaml](banks.yaml)
- 待確認事項見 [reports/ubot_jiho_20261110.review.md](reports/ubot_jiho_20261110.review.md)

## 已知限制

- 只處理靜態 HTML(含單頁應用背後的 HTML 片段或 API)。需要執行 JavaScript 才看得到的頁面要另外加 Playwright,目前沒裝。
- 圖片中的資料還沒有自動處理;skill 要求 agent 下載圖片自己讀,並在報告標明。
- 設計上待討論的事項見 [QUESTIONS.md](QUESTIONS.md)。
