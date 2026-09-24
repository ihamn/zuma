# DSH 会话迁移：一键解压 + 改名 + 就位
#
# 用法：把这个文件的全部内容复制，粘进 PowerShell 窗口，回车。
#      不要双击运行 .ps1 —— Windows 默认的执行策略会拦它。

$ErrorActionPreference = 'Stop'

Write-Host ''
Write-Host '===== DSH 会话迁移 =====' -ForegroundColor Cyan

# ---------- 1. 找 zip ----------
$cands = @(
  "$env:USERPROFILE\Downloads\dsh-session.zip",
  "$env:USERPROFILE\Desktop\dsh-session.zip",
  "$env:USERPROFILE\下载\dsh-session.zip",
  ".\dsh-session.zip"
)
$zip = $cands | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $zip) {
  Write-Host '× 没找到 dsh-session.zip' -ForegroundColor Red
  Write-Host '  把它放到「桌面」或「下载」文件夹，再跑一次。'
  return
}
Write-Host "√ 安装包: $zip" -ForegroundColor Green

# ---------- 2. 问项目路径 ----------
$def = Join-Path $env:USERPROFILE 'zuma'
Write-Host ''
$ws = Read-Host "项目放在哪个路径？(直接回车 = $def)"
if ([string]::IsNullOrWhiteSpace($ws)) { $ws = $def }
if (-not (Test-Path $ws)) {
  Write-Host "× 这个路径不存在: $ws" -ForegroundColor Red
  Write-Host '  先在资源管理器里把项目放好（git clone 或解压 zip），路径要一模一样。'
  return
}
Write-Host "√ 项目路径: $ws" -ForegroundColor Green

# ---------- 3. 算会话目录名（复刻 DSH 的 projectKey） ----------
$r = ''
$sep = $false
foreach ($ch in $ws.ToCharArray()) {
  if ($ch -eq '/' -or $ch -eq '\' -or $ch -eq ':') {
    if (-not $sep) { $r += '-' }
    $sep = $true
  } elseif (($ch -match '^[A-Za-z0-9._-]$') -and ($ch -ne '~')) {
    $r += $ch
    $sep = $false
  } else {
    $r += '~' + ([int][char]$ch).ToString('x4').ToUpper()
    $sep = $false
  }
}
$key = '--' + ($r -replace '^-+', '') + '--'
Write-Host "√ 会话目录名: $key" -ForegroundColor Green

# ---------- 4. 解压 + 就位 ----------
$dsh = Join-Path $env:USERPROFILE '.dsh'
$tmp = Join-Path $dsh '_migrate'
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Force $tmp | Out-Null

Expand-Archive -Path $zip -DestinationPath $tmp -Force

$srcDir = Get-ChildItem (Join-Path $tmp 'sessions') -Directory | Select-Object -First 1
if (-not $srcDir) {
  Write-Host '× 包里没有 sessions 目录，可能下载坏了' -ForegroundColor Red
  return
}

$dstRoot = Join-Path $dsh 'sessions'
New-Item -ItemType Directory -Force $dstRoot | Out-Null
$dst = Join-Path $dstRoot $key
if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }

Move-Item $srcDir.FullName $dst
Copy-Item (Join-Path $tmp 'settings.yaml') (Join-Path $dsh 'settings.yaml') -Force
Remove-Item $tmp -Recurse -Force

Write-Host ''
Write-Host '===== 完成 =====' -ForegroundColor Cyan
Write-Host "会话已放到: $dst"
Write-Host ''
Write-Host '现在打开 DeepSeek Harness，工作区选:'
Write-Host "  $ws"
Write-Host '会话列表里应该能看到这段对话。'
