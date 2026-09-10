#Requires -Version 5.1
<#
.SYNOPSIS
    重設本機 MySQL 8.0 的 root 密碼（忘記密碼時使用）。

.DESCRIPTION
    走 MySQL 官方建議的 --init-file 流程：
      1. 停掉 MySQL80 服務
      2. 寫一個只含 ALTER USER 的暫存檔
      3. 用 --init-file 啟動 mysqld，讓它套用新密碼
      4. 關掉它、刪除暫存檔
      5. 恢復正常服務並驗證新密碼可用

    另一種常見作法 --skip-grant-tables 沒有採用，因為那段期間
    任何人都能無密碼連進資料庫，這個流程全程都有認證保護。

.EXAMPLE
    # 以「系統管理員」身分開啟 PowerShell，然後：
    cd C:\Documents\Projects\APP\my_first_app
    powershell -ExecutionPolicy Bypass -File scripts\mysql\reset-root-password.ps1
#>

[CmdletBinding()]
param(
    [string]$ServiceName  = 'MySQL80',
    [string]$MysqlBin     = 'C:\Program Files\MySQL\MySQL Server 8.0\bin',
    [string]$DefaultsFile = 'C:\ProgramData\MySQL\MySQL Server 8.0\my.ini',
    # 重設完是否順手把新密碼寫進 scripts/mysql/my.local.cnf
    [switch]$SkipUpdateLocalCnf
)

$ErrorActionPreference = 'Stop'

function Write-Step($n, $msg) { Write-Host "[$n] $msg" -ForegroundColor Cyan }

# --- 前置檢查 -------------------------------------------------------------

$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "這個腳本需要系統管理員權限（停止 MySQL 服務用）。" -ForegroundColor Red
    Write-Host "請在開始選單搜尋 PowerShell -> 右鍵 -> 以系統管理員身分執行，再跑一次。" -ForegroundColor Red
    exit 1
}

$mysqld     = Join-Path $MysqlBin 'mysqld.exe'
$mysql      = Join-Path $MysqlBin 'mysql.exe'
$mysqladmin = Join-Path $MysqlBin 'mysqladmin.exe'

foreach ($exe in @($mysqld, $mysql, $mysqladmin)) {
    if (-not (Test-Path $exe)) { Write-Host "找不到 $exe" -ForegroundColor Red; exit 1 }
}
if (-not (Test-Path $DefaultsFile)) {
    Write-Host "找不到設定檔 $DefaultsFile" -ForegroundColor Red; exit 1
}
if (-not (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)) {
    Write-Host "找不到服務 $ServiceName" -ForegroundColor Red; exit 1
}

# --- 取得新密碼 -----------------------------------------------------------

function ConvertTo-PlainText([System.Security.SecureString]$secure) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

$pw1 = Read-Host '請輸入新的 root 密碼' -AsSecureString
$pw2 = Read-Host '請再輸入一次確認' -AsSecureString
$NewPassword  = ConvertTo-PlainText $pw1
$confirmation = ConvertTo-PlainText $pw2

if ($NewPassword -ne $confirmation) { Write-Host "兩次輸入不一致。" -ForegroundColor Red; exit 1 }
if ([string]::IsNullOrWhiteSpace($NewPassword)) { Write-Host "密碼不能空白。" -ForegroundColor Red; exit 1 }

# SQL 字面值跳脫：密碼含 ' 或 \ 的話不跳脫會讓整句語法爆掉
$sqlEscaped = $NewPassword.Replace('\', '\\').Replace("'", "\'")

$initFile = Join-Path $env:TEMP 'mysql-reset-init.sql'
$logFile  = Join-Path $env:TEMP 'mysql-reset-mysqld.log'
$tempCnf  = Join-Path $env:TEMP 'mysql-reset-client.cnf'
$mysqldProcess = $null

try {
    # --- 1. 停止服務 ------------------------------------------------------
    Write-Step 1 "停止 $ServiceName 服務..."
    if ((Get-Service $ServiceName).Status -ne 'Stopped') {
        Stop-Service -Name $ServiceName -Force
        (Get-Service $ServiceName).WaitForStatus('Stopped', '00:00:30')
    }
    Write-Host "    已停止。"

    # --- 2. 寫 init 檔 ----------------------------------------------------
    # 一定要 UTF-8 無 BOM：PowerShell 5.1 的 Out-File -Encoding utf8 會加 BOM，
    # mysqld 解析 init 檔時會把 BOM 當成語法的一部分而失敗。
    Write-Step 2 "產生暫存 init 檔..."
    $sql = "ALTER USER 'root'@'localhost' IDENTIFIED BY '$sqlEscaped';"
    [System.IO.File]::WriteAllText($initFile, $sql, (New-Object System.Text.UTF8Encoding($false)))

    # --- 3. 帶 init 檔啟動 mysqld ----------------------------------------
    # --defaults-file 不能省，服務就是靠它找到 datadir；少了它 mysqld 會用
    # 預設路徑，等於對著一個空資料庫改密碼，改完看起來成功但實際沒生效。
    Write-Step 3 "以 --init-file 啟動 mysqld（套用新密碼）..."
    $mysqldProcess = Start-Process -FilePath $mysqld -PassThru -NoNewWindow `
        -ArgumentList @(
            "--defaults-file=`"$DefaultsFile`"",
            "--init-file=`"$initFile`"",
            '--console'
        ) `
        -RedirectStandardOutput $logFile -RedirectStandardError "$logFile.err"

    # --- 4. 等它起來並驗證新密碼 -----------------------------------------
    # 密碼寫進暫存設定檔而不是放在命令列參數，避免被 ps / 工作管理員看到
    [System.IO.File]::WriteAllText(
        $tempCnf,
        "[client]`nhost=127.0.0.1`nuser=root`npassword=$NewPassword`n",
        (New-Object System.Text.UTF8Encoding($false)))

    Write-Step 4 "等待 mysqld 就緒..."
    $ready = $false
    foreach ($attempt in 1..30) {
        Start-Sleep -Seconds 2
        & $mysqladmin "--defaults-extra-file=$tempCnf" ping 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        if ($mysqldProcess.HasExited) { break }
    }

    if (-not $ready) {
        Write-Host "mysqld 沒有在時限內接受新密碼，記錄檔內容：" -ForegroundColor Red
        foreach ($f in @($logFile, "$logFile.err")) {
            if (Test-Path $f) { Get-Content $f -Tail 25 }
        }
        throw "重設失敗，服務尚未恢復，請看上面的錯誤訊息。"
    }
    Write-Host "    新密碼已生效。"

    # --- 5. 關掉臨時的 mysqld --------------------------------------------
    Write-Step 5 "關閉暫時啟動的 mysqld..."
    & $mysqladmin "--defaults-extra-file=$tempCnf" shutdown
    if (-not $mysqldProcess.WaitForExit(30000)) {
        $mysqldProcess.Kill()
        Write-Host "    (逾時，已強制結束)" -ForegroundColor Yellow
    }
    $mysqldProcess = $null

    # --- 6. 恢復正常服務 --------------------------------------------------
    Write-Step 6 "重新啟動 $ServiceName 服務..."
    Start-Service -Name $ServiceName
    (Get-Service $ServiceName).WaitForStatus('Running', '00:01:00')

    & $mysql "--defaults-extra-file=$tempCnf" -e "SELECT CONCAT('連線成功，目前身分：', CURRENT_USER()) AS status;"
    if ($LASTEXITCODE -ne 0) { throw "服務已啟動，但用新密碼連線失敗。" }

    # --- 7. 順手更新 my.local.cnf ----------------------------------------
    if (-not $SkipUpdateLocalCnf) {
        $localCnf = Join-Path $PSScriptRoot 'my.local.cnf'
        Write-Step 7 "更新 $localCnf ..."
        [System.IO.File]::WriteAllText(
            $localCnf,
            "[client]`nhost=127.0.0.1`nuser=root`npassword=$NewPassword`ndefault-character-set=utf8mb4`n",
            (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "    已寫入（這個檔案在 .gitignore 內，不會進版控）。"
    }

    Write-Host ""
    Write-Host "完成！root 密碼已重設，MySQL80 服務正常運作中。" -ForegroundColor Green
}
finally {
    # 這兩個暫存檔都含明碼新密碼，無論成功失敗都要清掉
    foreach ($f in @($initFile, $tempCnf)) {
        if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
    # 中途失敗時別把 mysqld 留在背景佔著 3306，否則服務會起不來
    if ($mysqldProcess -and -not $mysqldProcess.HasExited) {
        $mysqldProcess.Kill()
        Write-Host "已清掉中途啟動的 mysqld。" -ForegroundColor Yellow
    }
}
