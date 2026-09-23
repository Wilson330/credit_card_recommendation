# 在新機器上重現這個專案

這份文件說明怎麼把整個專案在另一台電腦(或重灌後)重新建起來。

> **重點:用 `git clone`,不要複製整個資料夾。**
> 資料夾裡有大量 build 產物(`build/`、`.dart_tool/`、各平台的 generated 檔)不該搬,
> 而且有幾個檔案是**故意不進 git 的**(見下方「clone 不會帶過去的檔案」)——複製資料夾
> 會把本機密碼也一起搬走,clone 則乾淨。

---

## 需要安裝的工具

| 工具 | 用途 | 備註 |
|---|---|---|
| Git | 取得程式碼 | |
| [Flutter SDK](https://docs.flutter.dev/get-started/install) | 跑 App | 需含 Dart `^3.12.2`(裝最新穩定版即可) |
| [Node.js](https://nodejs.org/) | 跑資料產生腳本 | **不需 `npm install`**,腳本只用內建模組 |
| MySQL Server 8.0 | 後端資料庫 | **選用**——只有要測 Allen 後端整合時才需要 |
| VS Code + Claude Code 擴充 | 開發環境 | |

App 本體只依賴 `provider` 與 `cupertino_icons` 兩個套件(見 `pubspec.yaml`),`flutter pub get`
會自動下載。

---

## 步驟一:取得程式碼

```bash
git clone https://github.com/Wilson330/credit_card_recommendation.git
cd credit_card_recommendation
git checkout feat/reward-data-schema
```

---

## 步驟二:跑起 Flutter App(必要)

```bash
flutter pub get
flutter doctor    # 檢查工具鏈缺什麼,照它的指示補(Android SDK、模擬器等)
flutter test      # 應該全部通過 → 代表邏輯層 OK
flutter run       # 在模擬器/實機上跑
```

這一版 App 讀的是**打包在 App 內的 JSON**(`lib/data/*.json`),不連資料庫也能完整運作。
所以只想繼續開發 App 的話,做到這裡就夠了。

---

## 步驟三:MySQL(選用,後端整合才需要)

資料庫內容是本機的,repo 只有「怎麼建」的腳本。完整說明在 [scripts/mysql/README.md](scripts/mysql/README.md),摘要:

```bash
# 1. 從範本建自己的連線設定,填入本機 MySQL root 密碼
cp scripts/mysql/my.local.cnf.example scripts/mysql/my.local.cnf
#    然後編輯 my.local.cnf 把 password= 換成真的密碼

# 2. 建資料庫與資料表,再灌入資料(路徑依你的 MySQL 安裝位置調整)
MYSQL="/c/Program Files/MySQL/MySQL Server 8.0/bin/mysql.exe"
"$MYSQL" --defaults-extra-file=scripts/mysql/my.local.cnf < scripts/mysql/schema.sql
"$MYSQL" --defaults-extra-file=scripts/mysql/my.local.cnf < scripts/mysql/seed_card_rewards.sql
"$MYSQL" --defaults-extra-file=scripts/mysql/my.local.cnf < scripts/mysql/seed_merchants.sql
```

> Windows PowerShell 的呼叫語法不同:變數用 `$MYSQL = "C:\..."`、執行含空白路徑的程式要在前面加 `&`。
> 忘記 root 密碼時,可用 `scripts/mysql/reset-root-password.ps1`(需系統管理員 PowerShell)。

建立的資料表:

| 資料表 | 內容 |
|---|---|
| `card_rewards` | 各卡各方案回饋率 |
| `merchants` / `merchant_aliases` / `merchant_tags` | 模糊搜尋商家目錄 |
| `users` | 帳號(擱置中,空表) |

---

## clone 不會帶過去的檔案(要另外處理)

這些都在 `.gitignore` 內,clone 後不會出現:

| 檔案 | 怎麼補 |
|---|---|
| `scripts/mysql/my.local.cnf` | 從 `.example` 複製並填密碼(見步驟三)。密碼只留本機是刻意設計。 |
| `app.py` / `ContentView.swift` | Allen 的後端與 iOS UI 原始檔,**不在本 repo**。要跑後端/Swift 才需要,跟 Allen 拿。純跑 Flutter App 不需要。 |
| `swift_port.zip` | 當初打包給 Allen 的壓縮檔。需要的話從 `swift_port/` 重新壓即可。 |
| `build/`、`.dart_tool/`、各平台 generated 檔 | 不用管,`flutter pub get` / `flutter run` 會自動重建。 |

---

## 資料重建流程(改資料時才需要)

`lib/data/*.json` 與 `scripts/mysql/seed_*.sql` 都是**產生出來的**,來源是 `lib/data/allen/` 裡
Allen 的爬蟲匯出檔。Allen 出新版資料時的重建鏈:

```
Allen 匯出檔 (lib/data/allen/*.json)
  │
  ├─ node scripts/convert_allen_rewards.js   → lib/data/{cube,jiho}_reward_rules.json  (回饋規則)
  │
  ├─ node scripts/build_merchants.js         → lib/data/merchants.json                 (商家目錄)
  │
  ├─ node scripts/mysql/build_seed_sql.js    → scripts/mysql/seed_card_rewards.sql
  └─ node scripts/mysql/build_merchants_sql.js → scripts/mysql/seed_merchants.sql
```

產完 SQL 後,重跑步驟三的灌入指令即可更新資料庫。詳細規格見 `lib/data/SCHEMA.md`。

---

## 專案結構速覽

```
lib/
  data/            打包進 App 的 JSON + SCHEMA.md（資料規格）+ allen/（原始爬蟲檔）
  models/          資料模型(卡片、回饋規則、商家)
  services/        核心邏輯:MerchantResolver / RuleMatcher / evaluators / orchestrator
  pages/           Cupertino(iOS 風)UI
scripts/           資料產生腳本(Node)
  mysql/           MySQL schema、seed、連線與重設工具
swift_port/        邏輯層的 Swift 移植(給 Allen 的 SwiftUI App 用)
test/              Dart 測試
```
