<#
.SYNOPSIS
    一键发布「倒班助手Pro」APK 到 GitHub Releases。

.DESCRIPTION
    流程：
      1. 读取版本号（默认从 app/pubspec.yaml 的 version: x.y.z+build 自动获取）
      2. 定位 APK（优先 dist/倒班助手Pro-v<版本>.apk，缺失则回退到 Flutter 构建输出并复制到 dist/）
      3. 一致性校验（工作区必须干净；任何源码文件不得晚于 APK 构建时间；本地 main 与 origin/main 比对提示）
      4. 生成发布说明（默认模板含 SHA256；可用 -NotesFile 指定）
      5. 人工确认后创建 GitHub Release 并上传 APK
      6. 通过 GitHub API 验证并打印下载地址

.PARAMETER Version
    手动指定版本号（如 0.3.0）。缺省时从 pubspec.yaml 读取。

.PARAMETER NotesFile
    指定发布说明文件。缺省时自动生成 tools/gh/release-notes-v<版本>.md。

.PARAMETER SkipVerify
    跳过一致性校验（不推荐，仅紧急补发时使用）。

.PARAMETER SkipConfirm
    跳过人工确认（用于脚本化/CI）。

.PARAMETER Prerelease
    标记为「预发布 / 测试版」。与 -Stable 互斥；都不给时按版本号自动判断：
    末位为 0（如 0.2.0 / 0.3.0）→ 正式稳定版；末位非 0（如 0.2.1）→ 预发布测试版。
    预发布不会抢占 Releases 页的「Latest」位置，正式版始终醒目置顶。

.PARAMETER Stable
    强制标记为「正式稳定版」（用于覆盖自动判断）。

.PARAMETER WhatIf
    演练模式：只做检查和打印，不创建 Release。

.EXAMPLE
    .\scripts\release.ps1
    .\scripts\release.ps1 -Version 0.3.0 -NotesFile docs\v0.3.0.md
    .\scripts\release.ps1 -Prerelease          # 强制标记为测试版
    .\scripts\release.ps1 -Stable              # 强制标记为正式版
    .\scripts\release.ps1 -WhatIf
#>

[CmdletBinding()]
param(
    [string]$Version,
    [string]$NotesFile,
    [switch]$SkipVerify,
    [switch]$SkipConfirm,
    [switch]$Prerelease,
    [switch]$Stable,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# ---------- 0. 定位仓库根目录与 gh ----------
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $root

$gh = Join-Path $root 'tools\gh\bin\gh.exe'
if (-not (Test-Path $gh)) {
    $cmd = Get-Command gh -ErrorAction SilentlyContinue
    if ($cmd) { $gh = $cmd.Source }
    else { throw "未找到 gh CLI。请下载 https://github.com/cli/cli/releases 的 windows_amd64 zip 解压到 tools\gh\ 或加入 PATH。" }
}
Write-Host "[1/6] gh CLI: $gh"

# ---------- 1. 版本号 ----------
if (-not $Version) {
    $m = Select-String -Path 'app\pubspec.yaml' -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)' | Select-Object -First 1
    if (-not $m) { throw "无法从 app\pubspec.yaml 读取版本号（期望格式 version: 0.2.0+47）" }
    $Version = $m.Matches[0].Groups[1].Value
    $VersionCode = $m.Matches[0].Groups[2].Value
} else {
    $VersionCode = '(未解析，请核对 pubspec.yaml)'
}
Write-Host "[2/6] 版本: v$Version (versionCode $VersionCode)"

# 正式版 / 预发布判断：末位为 0（0.2.0 / 0.3.0）→ 正式稳定版；末位非 0（0.2.1）→ 测试版
if ($Prerelease -and $Stable) { throw "-Prerelease 与 -Stable 不能同时指定" }
if ($Prerelease)      { $isPrerelease = $true;  $relMode = '手动' }
elseif ($Stable)      { $isPrerelease = $false; $relMode = '手动' }
else                  { $isPrerelease = ($Version -notmatch '\.0$'); $relMode = '自动' }
$relType = if ($isPrerelease) { '预发布（测试版）' } else { '正式稳定版' }
Write-Host "      类型: $relType（$relMode 判断）"

# ---------- 2. 定位 APK ----------
$distApk = Join-Path $root "dist\倒班助手Pro-v$Version.apk"
$buildApk = Join-Path $root 'app\build\app\outputs\flutter-apk\app-release.apk'
$apk = $null

if (Test-Path $distApk) {
    $apk = $distApk
    Write-Host "[3/6] APK: $($apk.Substring($root.Length + 1)) (dist 归档)"
} elseif (Test-Path $buildApk) {
    $apk = $buildApk
    Write-Host "[3/6] APK: 未找到 dist 归档，回退到 Flutter 构建输出，将复制到 dist\"
    if (-not $WhatIf) {
        New-Item -ItemType Directory -Force -Path (Split-Path $distApk) | Out-Null
        Copy-Item $buildApk $distApk -Force
        $apk = $distApk
        Write-Host "      已复制: dist\倒班助手Pro-v$Version.apk"
    }
} else {
    throw "未找到 APK：dist\倒班助手Pro-v$Version.apk 和 app\build\app\outputs\flutter-apk\app-release.apk 都不存在。请先 flutter build apk --release --target-platform android-arm64。"
}

$apkSize = '{0:N1} MB' -f ((Get-Item $apk).Length / 1MB)
$apkTime = (Get-Item $apk).LastWriteTime
Write-Host "      大小: $apkSize, 构建时间: $apkTime"

# ---------- 3. 一致性校验 ----------
if (-not $SkipVerify) {
    Write-Host "[4/6] 一致性校验..."

    $dirty = @(git status --porcelain)
    if ($dirty.Count -gt 0) {
        throw "工作区有未提交改动，源码与已提交内容不一致，请先 git add/commit：`n$($dirty -join "`n")"
    }

    $srcFiles = @(Get-ChildItem 'app\lib', 'app\test', 'app\android\app\src' -Recurse -File -ErrorAction SilentlyContinue)
    $srcFiles += @(Get-Item 'app\pubspec.yaml', 'app\android\app\build.gradle.kts' -ErrorAction SilentlyContinue)
    $violations = @($srcFiles | Where-Object { $_.LastWriteTime -gt $apkTime })
    if ($violations.Count -gt 0) {
        throw "以下源码文件晚于 APK 构建时间($apkTime)，APK 与当前源码不对应，请重新构建：`n$($violations | Select-Object -First 5 | ForEach-Object { $_.FullName.Substring($root.Length + 1) })"
    }

    $branch = git rev-parse --abbrev-ref HEAD
    $localMain = git rev-parse HEAD
    $remoteMain = @(git ls-remote origin "refs/heads/$branch" | ForEach-Object { ($_ -split "[\s`t]")[0] })
    if ($remoteMain.Count -gt 0 -and $localMain -ne $remoteMain[0]) {
        Write-Warning "本地 $branch 与 origin/$branch 不一致，Release tag 将指向本地提交 $($localMain.Substring(0,7))（未推送的提交不会被其他人看到）。"
    }

    Write-Host "      ✅ 工作区干净；无源码晚于构建；branch=$branch"
} else {
    Write-Host "[4/6] 一致性校验: 已跳过 (-SkipVerify)"
}

# ---------- 4. 发布说明 ----------
if ($NotesFile) {
    if (-not (Test-Path $NotesFile)) { throw "指定的发布说明文件不存在: $NotesFile" }
    $notes = (Resolve-Path $NotesFile).Path
} else {
    $notes = Join-Path $root "tools\gh\release-notes-v$Version.md"
    if (-not (Test-Path $notes)) {
        $sha = (Get-FileHash $apk -Algorithm SHA256).Hash
        $commit = (git log -1 --format='%h %ci')
        $tpl = @"
## 倒班助手Pro v$Version

### 本次更新
- （待补充：此处描述新功能 / 修复内容）

### 构建信息
- 版本：$Version（versionCode $VersionCode）
- 包名：com.daoban.shiftassistantpro，minSdk 26
- APK 大小：$apkSize，构建时间：$apkTime
- 对应源码提交：$commit
- SHA256：$sha
"@
        Set-Content -Path $notes -Value $tpl -Encoding UTF8
        Write-Host "      已生成发布说明模板: $($notes.Substring($root.Length + 1))（可编辑后重跑，已存在则直接复用）"
    } else {
        Write-Host "      复用发布说明: $($notes.Substring($root.Length + 1))"
    }
}
Write-Host "[5/6] 发布说明: $($notes.Substring($root.Length + 1))"

# ---------- 5. 确认 ----------
$tag = "v$Version"
$title = "倒班助手Pro $tag"
Write-Host ""
Write-Host "========== 发布预览 =========="
Write-Host "  Release : $title"
Write-Host "  类型    : $relType"
Write-Host "  Tag     : $tag  (指向当前 HEAD: $((git rev-parse --short HEAD)))"
Write-Host "  APK     : $($apk.Substring($root.Length + 1))  ($apkSize)"
Write-Host "  说明    : $($notes.Substring($root.Length + 1))"
Write-Host "=============================="

if ($WhatIf) {
    Write-Host "[演练模式 -WhatIf] 以上为将执行的操作，未创建任何 Release。"
    exit 0
}

if (-not $SkipConfirm) {
    $answer = Read-Host "确认创建 Release 并上传？(y/N)"
    if ($answer -notmatch '^[yY]') { Write-Host "已取消，未做任何修改。"; exit 0 }
}

# ---------- 6. 创建 Release 并上传 ----------
Write-Host "[6/6] 创建 $relType Release 并上传 APK..."
$prereleaseArgs = @()
if ($isPrerelease) { $prereleaseArgs = @('--prerelease') }
& $gh release create $tag $apk --title $title --notes-file $notes --target (git rev-parse --abbrev-ref HEAD) @prereleaseArgs
if ($LASTEXITCODE -ne 0) {
    throw "gh release create 失败（exit $LASTEXITCODE）。若 tag 已存在，可先手动删除或改用新版本号。"
}

# ---------- 7. 验证 ----------
$remote = git remote get-url origin
if ($remote -match 'github\.com[:/]([^/]+)/([^/]+?)(\.git)?$') {
    $repo = "$($Matches[1])/$($Matches[2])"
    $rel = & $gh api "repos/$repo/releases/tags/$tag" 2>&1 | ConvertFrom-Json
    Write-Host ""
    Write-Host "✅ 发布成功！"
    Write-Host "   仓库  : $($rel.html_url)"
    foreach ($a in $rel.assets) {
        Write-Host "   资产  : $($a.name)  ($([math]::Round($a.size / 1MB, 1)) MB)"
        Write-Host "   下载  : $($a.browser_download_url)"
    }
} else {
    Write-Host "✅ Release $tag 已创建（无法从 remote 解析仓库地址，请手动确认）。"
}
