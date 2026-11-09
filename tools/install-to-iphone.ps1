#Requires -Version 5.1
<#
.SYNOPSIS
    Prepares the iPhone install: checks drivers, finds Sideloadly and opens it with the IPA.

.DESCRIPTION
    Does not sign or install anything by itself. Sideloadly will ask for the
    Apple ID in its own window; that password is never read by this script.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/install-to-iphone.ps1
#>
param(
    [string]$IpaPath = ""
)

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Info([string]$message) { Write-Host $message -ForegroundColor Cyan }
function Good([string]$message) { Write-Host $message -ForegroundColor Green }
function Warn([string]$message) { Write-Host $message -ForegroundColor Yellow }
function Bad([string]$message)  { Write-Host $message -ForegroundColor Red }

Write-Host ""
Write-Host "=== Volna: установка на iPhone ===" -ForegroundColor White
Write-Host ""

# 1. IPA
if ([string]::IsNullOrWhiteSpace($IpaPath)) {
    $IpaPath = Join-Path $root "build\Volna-unsigned.ipa"
}
if (-not (Test-Path $IpaPath)) {
    Bad "IPA не найден: $IpaPath"
    Info "Сначала скачайте сборку: powershell -ExecutionPolicy Bypass -File tools/fetch-ipa.ps1"
    exit 1
}
Good "IPA: $IpaPath ($([math]::Round((Get-Item $IpaPath).Length / 1MB, 1)) МБ)"

# 2. Apple Mobile Device Support
$amdService = Get-Service -Name "Apple Mobile Device Service" -ErrorAction SilentlyContinue
if ($amdService) {
    Good "Apple Mobile Device Service: $($amdService.Status)"
} else {
    Warn "Apple Mobile Device Support не найден."
    Info "Установите: winget install Apple.AppleMobileDeviceSupport"
    Info "или iTunes / Apple Devices из Microsoft Store."
}

# 3. iPhone connection
$phone = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -match 'VID_05AC' -and $_.FriendlyName -match 'iPhone' }
if ($phone) {
    Good "iPhone подключён: $($phone.FriendlyName)"
} else {
    Warn "iPhone не виден. Подключите кабелем, разблокируйте и нажмите «Доверять»."
}

# 4. Sideloadly
$candidates = @(
    (Join-Path $env:LOCALAPPDATA "Programs\Sideloadly\Sideloadly.exe"),
    (Join-Path $env:LOCALAPPDATA "Sideloadly\Sideloadly.exe"),
    "C:\Program Files\Sideloadly\Sideloadly.exe",
    "C:\Program Files (x86)\Sideloadly\Sideloadly.exe"
)
$sideloadly = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $sideloadly) {
    $found = Get-ChildItem "$env:LOCALAPPDATA\Programs" -Recurse -Filter "Sideloadly.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($found) { $sideloadly = $found.FullName }
}

if (-not $sideloadly) {
    Bad "Sideloadly не найден."
    Info "Установите: winget install iOSGods.Sideloadly"
    Info "или скачайте с https://sideloadly.io/"
    exit 1
}
Good "Sideloadly: $sideloadly"

Write-Host ""
Info "Открываю Sideloadly. Дальше:"
Write-Host "  1. Убедитесь, что в строке «Device» выбран ваш iPhone."
Write-Host "  2. Перетащите $IpaPath в окно Sideloadly (или нажмите IPA и выберите файл)."
Write-Host "  3. Введите Apple ID и пароль в окне Sideloadly (2FA поддерживается)."
Write-Host "  4. Нажмите Start и дождитесь окончания."
Write-Host "  5. На iPhone: Настройки → Основные → VPN и управление устройством → Доверять."
Write-Host ""
Start-Process -FilePath $sideloadly -ArgumentList "`"$IpaPath`"" -PassThru | Out-Null
Good "Готово."
