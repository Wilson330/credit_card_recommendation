# 爬蟲:起始說明

給開始做爬蟲的人與 agent 讀的第一份文件。Wilson 和 Allen 各自做一版爬蟲,做完拿兩邊的結果比較,再決定用哪一版或怎麼合併。

## 目標

寫一支爬蟲,從銀行官網抓三張卡的回饋資料,產出**符合 [CRAWL_FORMAT.md](CRAWL_FORMAT.md) 的匯出檔**。

完成的標準:

1. `python -m backend.importer <匯出檔> --check` 通過(格式正確)
2. `python -m backend.importer <匯出檔> --dry-run` 的報告中,跟 0908 比起來沒有漏掉方案或店家;多出來的要能說明是官網新增的
3. 同一支爬蟲重跑,結果一致(網頁沒變的話)

## 範圍

| 卡片 | 銀行 | `card_name` | `card_level` | 0908 的方案(列數) |
|---|---|---|---|---|
| CUBE卡 | 國泰世華 | `CUBE卡` | `Level 1`、`Level 2`、`Level 3` | 樂饗購 120、玩數位 72、趣旅行 168、集精選 42、台塑家 33、全支付 9、童樂匯 213、慶生月 204、固定回饋 6 |
| Unicard | 玉山銀行 | `Unicard` | `簡單選`、`任意選`、`UP選` | 百大特店 297 |
| 吉鶴卡 | 聯邦銀行 | `吉鶴卡` | `Standard`(或 `""`) | 國內人氣餐廳 31、國內日系特店 23、日本熱門商店 11、日本交通卡儲值 3、日本消費 2、國內一般消費 1、國外一般消費 1 |

共 1,236 列。`card_name`、`card_level`、`scheme_name` 要跟 0908 一致,後端才對得上(對照設定在 `backend/cards.yaml` 的 `crawl_name` 與 `schemes`)。官網改了名稱的話照抄新名稱,並在交檔時說明。

## 原則

- **照抄網頁原文,不要判斷。** 店名、方案名、括號裡的限制都照網頁寫。「這一列是店家還是行動支付」「數字含不含基本回饋」由後端判斷,爬蟲不用處理。
- **網頁上列在方案底下的東西都要抓**,包括一般消費、行動支付、國家、整類消費(例如「國內餐飲(不含餐券)」),不只店家。後端會用 `db/crawl/labels.yaml` 標記它們是什麼。
- **盡量填選填欄位**:
  - `section`:這一列在網頁上的段落標題。最重要,後端靠它判斷這一列是什麼。
  - `source_url`:這一列出自哪個網頁。
  - `valid_from` / `valid_to`:網頁上寫的活動期間。
- **每個等級各一列**:同一家店在 Level 1、2、3 都有回饋,就是三列,即使數字一樣。
- **條款頁面另存**:每張卡的權益說明、活動辦法頁面,把文字存成檔案(見下方「產出」)。後端寫 `cards.yaml` 時要從條款判斷要不要切換方案、要不要疊加一般消費、有什麼條件,這些不在回饋列表裡。
- **對銀行網站客氣一點**:請求之間加延遲、不要平行狂抓、遵守 robots.txt,有登入或驗證碼的頁面不要繞過。

## 參考答案:0908

`db/crawl/card_rewards_export_0908.json` 是 Allen 之前的爬蟲結果(7 月底到 9 月初抓的),已經匯入資料庫並驗證過,可以當比對基準:

- 欄位、名稱的寫法照它
- 爬完拿來比對:哪些方案、店家 0908 有、新版沒有(漏抓還是官網拿掉了),反過來也一樣

0908 已知的問題,新版請注意:

- **Unicard 百大特店底下有 18 個國家**(日本、韓國、美國…)。這代表在這些國家消費也算百大特店,請確認網頁上的段落與說明,填進 `section`。
- **行動支付混在店家名單裡**(Unicard 百大特店的 LINE Pay、街口支付等 11 種;CUBE 全支付方案的「全支付國內合作通路」)。照抄即可,有段落標題的話填 `section`。
- **整類消費混在店家名單裡**:例如 CUBE 樂饗購的「國內餐飲(不含餐券)」、趣旅行的「國內飯店住宿」「海外實體消費」。
- **限制寫在店名括號裡**:例如「金子半之助(限週一至週四)」。照抄,不用拆。
- 一般消費放在獨立的方案下:CUBE 的「固定回饋」、吉鶴卡的「國內一般消費」「國外一般消費」「日本消費」。

## 產出

| 產出 | 位置 |
|---|---|
| 爬蟲程式 | `crawler/`(結構自己決定;建議一張卡一個模組,共用的請求、存檔邏輯另外放) |
| 匯出檔 | `db/crawl/card_rewards_export_YYYYMMDD.json`(或 `.csv`) |
| 條款頁面 | `db/crawl/terms/<card_id>/`,一頁一個 `.txt` 或 `.md`,檔案開頭寫來源網址與抓取日期。`card_id`:`cathay_cube`、`esun_unicard`、`ubot_jiho` |
| 說明 | `crawler/README.md`:怎麼安裝、怎麼執行、抓了哪些網頁、已知的限制 |

套件加進 `crawler/requirements.txt`(不要改 `backend/requirements.txt`)。專案用 Python 3.9(Wilson 用 Anaconda)。

## 分支

在 `feat/reward-data-schema` 之上各自開分支,不要直接改 `feat/reward-data-schema`:

```bash
git checkout feat/reward-data-schema
git pull
git checkout -b crawler-wilson     # Allen 用 crawler-allen
```

做完各自 push,比較時看兩個分支的 `crawler/` 和匯出檔。

## 不要碰

- `backend/`(後端、`cards.yaml`、importer)。發現 importer 或格式規格有問題,寫下來回報,不要自己改。
- 資料庫:只跑 `--check` 和 `--dry-run`,**不要正式匯入**(不加 `--dry-run` 會寫入資料庫),也不要用 `--map`、`--new`、`--label`。匯入是之後用 `.claude/skills/add-card` 的流程做的事。
- `db/crawl/labels.yaml`、`db/seed.sql`。

## 驗證

```bash
python -m backend.importer db/crawl/<匯出檔> --check       # 格式,不需要資料庫
python -m backend.importer db/crawl/<匯出檔> --dry-run     # 匯入報告,需要本機資料庫(見 db/README.md)
```

`--dry-run` 報告要看的地方:

- **匯入計畫**:每個方案的點名店家數、各等級回饋率,跟 0908 比
- **未標記的列**:新出現、不是店家的原文。不用處理,列在交檔說明中即可
- **對不到店家的爬蟲店名**:新店或改名的店。同上,列出來就好
- **離開方案名單的店家**:0908 有、新版沒有的店。確認是漏抓還是官網拿掉了

## 相關文件

| 文件 | 內容 |
|---|---|
| [CRAWL_FORMAT.md](CRAWL_FORMAT.md) | 匯出檔格式(必讀) |
| [db/crawl/labels.yaml](../db/crawl/labels.yaml) | 0908 中不是店家的原文怎麼分類,可以看出網頁上會出現哪些東西 |
| [DB_DESIGN.md](DB_DESIGN.md) 第 8 節 | 匯入流程 |
| [backend/cards.yaml](../backend/cards.yaml) | 三張卡的規則,看 `crawl_name`、`schemes`、`skip_crawl_schemes` 怎麼對照爬蟲 |
| [db/README.md](../db/README.md) | 在本機建資料庫(跑 `--dry-run` 需要) |
