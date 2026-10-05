# 刷哪張卡最划算

輸入店名,從你持有的信用卡中找出回饋最高的一張,並告訴你需不需要切換權益方案。

目前支援國泰世華 CUBE 卡、玉山 Unicard、聯邦吉鶴卡。回饋資料來自 Allen 的爬蟲。

## 架構

```
Flutter App(Wilson 本機測試) ─┐
                               ├─ HTTP ─→ Python 後端 ─→ MySQL
iOS App(Allen,SwiftUI)    ─┘           └ cards.yaml(卡片規則)
```

推薦計算全部在後端:資料庫負責店家與方案資料,`backend/cards.yaml` 負責卡片規則(等級、條件、一般消費、加碼),App 只負責畫面。

## 文件

| 文件 | 內容 |
|---|---|
| [SETUP.md](SETUP.md) | 在新機器上把整個專案跑起來 |
| [backend/README.md](backend/README.md) | 後端:啟動、API、測試、匯入爬蟲資料 |
| [db/README.md](db/README.md) | 資料庫:建立、資料表、修改資料 |
| [docs/DB_DESIGN.md](docs/DB_DESIGN.md) | 資料表與推薦邏輯的完整設計 |
| [docs/HANDOFF_ALLEN.md](docs/HANDOFF_ALLEN.md) | 給 Allen:iOS App 改接新後端要做的事 |
