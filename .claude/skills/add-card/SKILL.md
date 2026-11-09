---
name: add-card
description: 新增一張信用卡到回饋推薦系統:從爬蟲匯出檔與官網條款,寫 backend/cards.yaml、標記爬蟲列、對照店家、匯入資料庫、寫驗證案例並跑測試。Use when the user wants to add a new credit card, onboard a crawl export for a card not yet in backend/cards.yaml, or re-check an existing card's rules against its terms.
---

# 新增卡片

把一張新卡加進系統。產出:

1. `backend/cards.yaml` 中這張卡的一段規則
2. `db/crawl/labels.yaml` 中新出現的標記
3. 資料庫中的方案、回饋率、點名店家(經由 importer),以及重新匯出的 `db/seed.sql`
4. `backend/tests/card_cases/<card_id>.yaml` 驗證案例,測試全部通過
5. 給人看的摘要:做了什麼、決定了什麼、還有哪些待確認

App(Flutter、iOS)的卡片設定畫面依 `/api/cards` 畫,**通常不用改 App**。

## 原則

- **不猜規則。** 爬蟲只告訴你有哪些方案、幾 %、點名哪些店。要不要切換、要不要疊加、要符合什麼條件、一般消費幾 %,都要從官網條款找到出處。找不到就標「待確認」交給人。
- **四個檢查點一定要停下來給人確認**(下面標 ✋)。人確認之前不要往下做會寫入資料庫的步驟。
- **不改計算程式。** 條款中有現有模型表達不了的規則(見 `card_checklist.md` 第 7 節),停下來回報,不要硬塞進 `cards.yaml`。
- **資料庫只透過 importer 的指令寫入**(`--map`、`--new`、匯入)。不要直接下 SQL 修改,不要動 `users`、`user_cards`,不要執行 `db/schema.sql` 或 `db/seed.sql`。
- 指令都在專案根目錄、已 activate 的 Python 環境中執行(Windows 用 Anaconda Prompt)。

## 開始前

向人取得:
- 爬蟲匯出檔(格式見 `docs/CRAWL_FORMAT.md`),放在 `db/crawl/`
- 這張卡的官網條款網址(權益說明、活動辦法)

確認環境正常:

```bash
git status                       # 工作目錄乾淨,在要提交的分支上
python -m pytest backend -q      # 全部通過(需要本機 MySQL)
```

## 步驟 1:格式檢查

```bash
python -m backend.importer db/crawl/<檔名>.json --check
```

有錯誤就停下來,把錯誤交給人轉給 Allen 修正,不要自己改爬蟲檔。警告逐條看過,寫進最後的摘要。

這時會出現「cards.yaml 還沒有這張卡」的警告,是正常的。

## 步驟 2:起草 cards.yaml ✋

1. 從爬蟲檔列出這張卡的所有 `card_level`、`scheme_name`,以及每個方案的回饋率與列數。
2. 讀官網條款。
3. 照 `card_checklist.md` 逐題回答,每題附出處。
4. 檢查有沒有 `card_checklist.md` 第 7 節列的「表達不了的規則」。有的話**停下來回報**,說明是哪一條、影響哪些方案、可以先不計算哪些部分,讓人決定要先改程式還是先做能做的部分。
5. 在 `backend/cards.yaml` 寫入這張卡的一段,從最像的範本卡複製後修改。
6. 確認能載入:

   ```bash
   python -c "from backend.rules import load_rules; from backend.config import BACKEND_DIR; print(load_rules(BACKEND_DIR / 'cards.yaml').cards['<card_id>'])"
   ```

**✋ 檢查點 A**:把問題清單的答案表(含出處與待確認項目)和 `cards.yaml` 段落交給人確認。待確認的項目由人決定,或由人去問 Allen、查條款。確認後才往下。

## 步驟 3:標記爬蟲列

```bash
python -m backend.importer db/crawl/<檔名>.json --dry-run
```

看報告中的「未標記的列」。每個原文判斷是哪一種(類型說明見 `db/crawl/labels.yaml` 開頭):

| 判斷依據(由強到弱) | 例子 |
|---|---|
| 爬蟲的 `section`(網頁段落標題) | 「指定行動支付」→ `payment_method`;「海外指定國家」→ `category` |
| 條款原文 | 條款說「以下行動支付綁定本卡」→ `payment_method` |
| 原文本身 | `國內一般消費` → `general`;`日本` → `category`;捐款 → `ignore` |
| 已有的標記 | 同類的原文在 `labels.yaml` 怎麼標 |

確定的直接標記:

```bash
python -m backend.importer --label "原文" 類型 --note "哪張卡哪個方案,怎麼處理"
```

標成 `category` 或 `payment_method` 的列,回頭確認 `cards.yaml` 對應方案的 `covers` 或 `payment_methods` 有沒有設定;要計算卻沒設定的,補進 `cards.yaml`,不計算的在 `--note` 寫原因。

沒把握的不要標,列進檢查點 B。

## 步驟 4:對照店家 ✋

重跑 `--dry-run`,看「對不到店家的爬蟲店名」。每個店名報告都附了建議,逐一判斷:

- **既有的店**(改名、異寫、不同卡寫法不同):`--map "店名" 店家編號`。同一家店在不同卡的名單中寫法不同很常見(例如「新光三越百貨」與「新光三越」),要合併到同一個店家,否則搜尋時會漏掉其中一張卡的回饋。
- **新店**:`--new "店名" --category 分類 --country 國別`。分類用資料庫中已有的分類;國別 `TW`、`JP`,多國都有據點的填 `global`。分類和國別都會影響回饋(`covers` 依分類、海外回饋依國別),要依店家實際情況填,不是依方案名稱猜。
- 日本的店名稱前加「日本」(例如「日本 7-ELEVEN」),避免跟台灣的店搞混。用 `--new` 時,店名寫原文;建立後如需改名,寫進 `db/changes/`(見 `db/README.md`)。

**✋ 檢查點 B**:整理成一張表交給人確認,每列一個店名:建議的處理(`--map #編號 店名` 或 `--new 分類 國別`)與理由;加上步驟 3 沒把握的標記。人確認後才執行 `--map`、`--new`(這兩個指令會寫入資料庫)。

執行完重跑 `--dry-run`,直到「未標記的列」和「對不到店家的爬蟲店名」都沒有了。

## 步驟 5:匯入

再看一次 `--dry-run` 報告的其他部分:

- **匯入計畫**:每個方案的點名店家數、各等級回饋率,跟官網對得上嗎
- **一般消費與 cards.yaml 不同**:爬蟲數字和 `general` 不同時,以條款為準,但要寫進摘要
- **例外不一致**、**同方案重複店家**:看是爬蟲的問題還是條款本來就這樣
- **類別列:cards.yaml 沒有設定 covers,目前不計算**:確認是刻意不計算

沒問題就正式匯入,然後重新匯出 `db/seed.sql`(指令見 `db/README.md`「重新匯出 seed.sql」,要在 Git Bash 執行):

```bash
python -m backend.importer db/crawl/<檔名>.json
```

啟動後端確認一致性檢查沒有警告(看到 `Running on` 就可以 Ctrl+C):

```bash
python -m backend.app
```

## 步驟 6:驗證案例 ✋

寫 `backend/tests/card_cases/<card_id>.yaml`,格式見 `backend/tests/test_card_cases.py` 開頭,範例見同目錄的 `cathay_cube.yaml`、`ubot_jiho.yaml`。

案例要涵蓋這張卡的每一條規則,每條至少一個「適用」和一個「不適用」的案例:

- 每個方案:點名的店;有 `covers` 的方案加一家沒被點名、靠分類涵蓋的店
- 每個等級或方案選項至少出現一次
- 每個開關:開和關各一次
- 疊加、加碼:算出來的數字(例如 2.5 + 1 = 3.5)
- 要挑店的方案:有挑、沒挑
- 行動支付:該建議、不該建議(直接刷卡比較高、國外的店)
- 一般消費的每一層;國內、國外、找不到店家(`merchant: null`)
- 方案和一般消費同分、或一般消費比方案高的情況

**預期值從條款推算,不要拿程式的輸出當預期值。** 每個案例寫 `source`。店家用資料庫中的完整店名。

**✋ 檢查點 C**:把案例表交給人確認(可以整理成「店家 / 設定 / 預期 / 依據」的表格)。人確認後再跑:

```bash
python -m pytest backend/tests/test_card_cases.py -q
```

測試失敗時,先判斷是案例錯了、`cards.yaml` 錯了,還是資料錯了。**不要為了讓測試通過而改預期值**;改了預期值要讓人知道原因。

## 步驟 7:收尾 ✋

```bash
python -m pytest backend -q     # 全部通過
flutter test                    # 應該不受影響
```

- `README.md` 開頭「目前支援」的卡片清單加上這張卡。
- 卡面圖(選配):圖檔放 `assets/card_faces/`,在 `lib/constants/card_art.dart` 加上 `card_id` → 圖檔的對照;沒有圖會顯示灰底的卡片圖示。iOS 那邊由 Allen 自己處理。

**✋ 檢查點 D**:交給人一份摘要,然後等人決定要不要 commit:

- 新增的方案、回饋率、點名店家數
- 檢查點 A 的決定與仍待確認的項目
- 新增的標記、`--map`、`--new`(列出每一個,另一台資料庫要照做)
- 不計算的部分與原因(表達不了的規則、`covers` 未設定的類別列)
- 格式檢查與匯入報告中的警告
- 改過的檔案

commit 時確認 `git status` 中沒有 `db/my.local.cnf`、`backend/.secret_key`、`app.py`。
