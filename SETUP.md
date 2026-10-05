# 在新機器上重現這個專案

把整個專案在另一台電腦(或重灌後)重新建起來。要跑起來需要三個部分:MySQL 資料庫、Python 後端、Flutter App。

> **用 `git clone`,不要複製整個資料夾。** 資料夾裡有大量 build 產物,還有幾個故意不進 git 的檔案(含密碼,見最後一節),複製資料夾會把它們一起帶走。

## 需要安裝的工具

| 工具 | 用途 |
|---|---|
| Git | 取得程式碼 |
| MySQL Server 8.0 | 資料庫 |
| Python 3.9 以上(Wilson 用 Anaconda) | 後端 |
| [Flutter SDK](https://docs.flutter.dev/get-started/install)(Dart `^3.12.2`,裝最新穩定版即可) | App |
| Chrome | 在電腦上測 App |

## 1. 取得程式碼

```bash
git clone https://github.com/Wilson330/credit_card_recommendation.git
cd credit_card_recommendation
git checkout feat/reward-data-schema
```

以下指令都在專案根目錄執行。

## 2. 資料庫

照 [db/README.md](db/README.md) 的「新機器建資料庫」:建立 `db/my.local.cnf`(填 MySQL root 密碼),執行 `db/schema.sql` 與 `db/seed.sql`。

## 3. 後端

```powershell
pip install -r backend/requirements.txt
python -m pytest backend/tests -q      # 應該全部通過,代表資料庫與後端都正常
python -m backend.app                  # 跑在 http://127.0.0.1:5000,這個視窗保持開著
```

Windows 用 Anaconda 時,要在 Anaconda Prompt 或 activate 過的環境(提示字元前有 `(base)`)執行,不然連 MySQL 會出現 SSL 錯誤。更多說明見 [backend/README.md](backend/README.md)。

## 4. Flutter App

另開一個視窗:

```powershell
flutter pub get
flutter test                 # 應該全部通過
flutter run -d chrome        # 用 Chrome 開 App
```

App 預設連 `http://127.0.0.1:5000`。後端在別台機器時:

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://192.168.x.x:5000
```

此時後端要用 `python -m backend.app --host 0.0.0.0` 啟動。Android 模擬器會自動改連 `10.0.2.2`(模擬器裡指向電腦本身的位址)。

第一次開 App 先註冊帳號,再到「設定我的卡片」加卡,就可以搜尋店家。

**用真的後端測 App 的 API 呼叫**(後端要開著):

```powershell
$env:API_INTEGRATION=1; flutter test test/api_integration_test.dart
```

## clone 不會帶過去的檔案

| 檔案 | 怎麼補 |
|---|---|
| `db/my.local.cnf` | 從 `db/my.local.cnf.example` 複製並填密碼 |
| `backend/.secret_key` | 後端第一次啟動時自動產生。換了這個檔案,之前發出的登入 token 都會失效,重新登入即可 |
| `app.py`、`ContentView.swift` | Allen 原本的後端與 iOS 畫面,不在本 repo,這個專案用不到 |
| `build/`、`.dart_tool/` | `flutter pub get`、`flutter run` 會自動產生 |

## 專案結構

```
backend/     Python 後端:API、推薦計算、爬蟲匯入、卡片規則 cards.yaml
db/          資料庫:建表檔、資料、人工修改紀錄、爬蟲匯出檔
docs/        設計文件 DB_DESIGN.md、給 Allen 的交接說明
lib/         Flutter App
  api/       呼叫後端 API
  state/     登入狀態、我的卡片、搜尋紀錄
  pages/     畫面(Cupertino / iOS 風格)
test/        Flutter 測試(用假後端;api_integration_test 連真的後端)
```
