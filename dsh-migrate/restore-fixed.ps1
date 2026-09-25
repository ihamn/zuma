# DSH 会话迁移：一键解压 + 改名 + 就位【修正版】
#
# 与原版 restore.ps1 的区别（原版有两个坑）：
#   ① 原版会 `Remove-Item $dst -Recurse -Force` 删掉整个工作区会话目录。
#      如果那个工作区**已经有会话**（本机开过一次就会出现），原版会把它们全删了。
#      本版只做加法：逐个会话目录拷进去，已存在的跳过，绝不删除。
#   ② 原版把 settings.yaml 直接覆盖过去。本版先备份再放。
#   ③ 原版漏了最关键的一步：会话列表是登记制（workspace.json 的 sessionIds），
#      光把文件放进去，侧边栏不一定看得到。本版补上登记。
#
# 用法：把本文件全部内容复制，粘进 PowerShell 窗口，回车。
#      不要双击运行 .ps1 —— Windows 默认执行策略会拦它。

$ErrorActionPreference = 'Stop'

# 迁移包里的主会话（深度 0，就是"我们这段对话"）
$MAIN_SESSION = 'session-ae41f6ae-5bc1-44fd-b646-6148d2177947'

Write-Host ''
Write-Host '===== DSH 会话迁移（修正版）=====' -ForegroundColor Cyan

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

# ---------- 4. 解压到临时目录 ----------
$dsh = Join-Path $env:USERPROFILE '.dsh'
$tmp = Join-Path $dsh '_migrate'
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }   # 只删自己的临时目录
New-Item -ItemType Directory -Force $tmp | Out-Null
Expand-Archive -Path $zip -DestinationPath $tmp -Force

$srcKeyDir = Get-ChildItem (Join-Path $tmp 'sessions') -Directory | Select-Object -First 1
if (-not $srcKeyDir) {
  Write-Host '× 包里没有 sessions 目录，可能下载坏了' -ForegroundColor Red
  return
}
$srcSessions = Get-ChildItem $srcKeyDir.FullName -Directory
Write-Host "√ 包里找到 $($srcSessions.Count) 个会话目录" -ForegroundColor Green

# ---------- 5. 只做加法地拷贝进去 ----------
$dstKeyDir = Join-Path (Join-Path $dsh 'sessions') $key
New-Item -ItemType Directory -Force $dstKeyDir | Out-Null

$installed = @()
foreach ($s in $srcSessions) {
  $target = Join-Path $dstKeyDir $s.Name
  if (Test-Path $target) {
    Write-Host "  - 已存在，跳过: $($s.Name)" -ForegroundColor Yellow
  } else {
    Copy-Item $s.FullName $target -Recurse
    Write-Host "  + 已放入: $($s.Name)" -ForegroundColor Green
    $installed += $s.Name
  }
}

# ---------- 6. settings.yaml（先备份） ----------
$srcSettings = Join-Path $tmp 'settings.yaml'
$dstSettings = Join-Path $dsh 'settings.yaml'
if (Test-Path $srcSettings) {
  if (Test-Path $dstSettings) {
    $bak = "$dstSettings.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item $dstSettings $bak -Force
    Write-Host "  ! 原有 settings.yaml 已备份为: $bak" -ForegroundColor Yellow
  }
  Copy-Item $srcSettings $dstSettings -Force
  Write-Host '  + settings.yaml 已就位' -ForegroundColor Green
}

Remove-Item $tmp -Recurse -Force

# ---------- 7. 登记进 workspace.json ----------
$wsFile = Join-Path (Join-Path $dsh 'storages') 'workspace.json'
if (Test-Path $wsFile) {
  $bak = "$wsFile.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
  Copy-Item $wsFile $bak -Force
  Write-Host "  ! workspace.json 已备份为: $bak" -ForegroundColor Yellow

  $doc = Get-Content $wsFile -Raw -Encoding UTF8 | ConvertFrom-Json
  $target = $null
  foreach ($p in $doc.tables.workspaces.PSObject.Properties) {
    if ($p.Value.path -eq $ws) { $target = $p.Value; break }
  }

  if (-not $target) {
    Write-Host "  ~ 工作区「$ws」还没在 DSH 里打开过，无法登记。" -ForegroundColor Yellow
    Write-Host '    先打开 DSH、把这个路径添加为工作区，再跑一次本脚本。' -ForegroundColor Yellow
  } else {
    $want = @($MAIN_SESSION) + $installed
    $want = $want | Where-Object { $_ -match '^session-' } | Select-Object -Unique
    $added = @()
    foreach ($id in $want) {
      if ($target.sessionIds -notcontains $id) { $target.sessionIds += $id; $added += $id }
    }
    if ($added.Count -eq 0) {
      Write-Host '  - 会话已登记过，无需重复' -ForegroundColor Yellow
    } else {
      $target.updatedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
      $doc | ConvertTo-Json -Depth 32 | Set-Content $wsFile -Encoding UTF8
      # 写完立刻验证，坏了就还原
      try {
        Get-Content $wsFile -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
        Write-Host "  + 已登记 $($added.Count) 个会话" -ForegroundColor Green
      } catch {
        Copy-Item $bak $wsFile -Force
        Write-Host '  × 写入后解析失败，已自动还原备份' -ForegroundColor Red
      }
    }
    Write-Host '    注意：子代理会话（3 个裸 uuid 目录）不需要登记，它们是挂在主会话下的。' -ForegroundColor Gray
  }
} else {
  Write-Host '  ~ 没找到 workspace.json，跳过登记' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '===== 完成 =====' -ForegroundColor Cyan
Write-Host '打开 DeepSeek Harness，工作区选:'
Write-Host "  $ws"
Write-Host ''
Write-Host '侧边栏里应该能看到这段对话。看不到的话：'
Write-Host '  1. 刷新页面（Ctrl+F5）'
Write-Host '  2. 还不行就完全退出 DSH 再打开（workspace.json 是启动时读的）'
Write-Host '  3. 再不行把这段输出发我'
