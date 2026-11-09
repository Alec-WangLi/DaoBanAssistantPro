<#
.SYNOPSIS
    一键发布「倒班助手Pro」APK 到 GitHub Releases。

.DESCRIPTION
    流程：
      1. 读取版本号（默认从 app/pubspec.yaml 的 version: x.y.z+build 自动获取）
      2. 定位 APK（优先 dist/倒班助手Pro-v<版本>.apk，缺失则回退到 Flutter 构建输出并复制到 dist/）
      3. 一致性校验（工作区必须干净；任何源码文件不得晚于 APK 构建时间；本地 main 与 origin/main 比对提示）
      4. 生成发布说明（默认模板含 SHA256；可用 -NotesFile 指定）
      5. 人工确认后创建 GitHub Release 并上传 APK（资产名自动为 ASCII：<仓库名>-v<版本>.apk）
      6. 通过 GitHub API 验证并打印下载地址
      7. 更新仓库根目录 latest.json 发布清单（App「检查更新」限流兜底）并提交推送；
         **若当前分支不是 main，再把这份清单同步一份到 main** —— App 的兜底通道读的
         是 main 上那份（`raw.githubusercontent.com/<owner>/<repo>/main/latest.json`），
         而测试版是在 beta 之类分支上发的。这一步失败只告警、不影响已完成的发布

.PARAMETER Version
    手动指定版本号（如 0.3.0）。缺省时从 pubspec.yaml 读取。

.PARAMETER NotesFile
    指定发布说明文件。缺省时自动生成 tools/gh/release-notes-v<版本>.md。
    2026-11-05 出过一次「文件明明在、脚本却判它不存在」的事故：发布前 1 分钟写好的
    说明文件被下面那段模板覆盖成 418 字节的占位稿，根因未查明。**发版一律显式传
    -NotesFile 绝对路径**，绕开这条。

.PARAMETER SkipVerify
    跳过一致性校验（不推荐，仅紧急补发时使用）。
    **它只跳一致性校验，签名校验始终执行**；真要连签名都不验，那是 -SkipSignCheck 的事。

.PARAMETER SkipConfirm
    跳过人工确认（用于脚本化/CI）。

.PARAMETER Prerelease
    标记为「预发布 / 测试版」。与 -Stable 互斥；都不给时按版本号自动判断：
    末位为 0（如 0.2.0 / 0.3.0）→ 正式稳定版；末位非 0（如 0.2.1）→ 预发布测试版。
    预发布不会抢占 Releases 页的「Latest」位置，正式版始终醒目置顶。

.PARAMETER Stable
    强制标记为「正式稳定版」（用于覆盖自动判断）。

.PARAMETER SkipSignCheck
    显式跳过签名校验。**默认不跳过**：校验跑不了（缺 apksigner / keytool，或没吐出证书摘要）
    会直接 throw —— 签名是「这包能不能装到用户手机上」的唯一保证，没有保证不该默认放行。
    2026-11-05 发 v0.12.9 时因为没 dot-source tools\build-env.ps1，这一步空转、只发了 Warning。

.PARAMETER WhatIf
    演练模式：只做检查和打印，不创建 Release。

.EXAMPLE
    .\scripts\release.ps1
    .\scripts\release.ps1 -Version 0.3.0 -NotesFile docs\v0.3.0.md
    .\scripts\release.ps1 -Prerelease          # 强制标记为测试版
    .\scripts\release.ps1 -Stable              # 强制标记为正式版
    .\scripts\release.ps1 -WhatIf

.NOTES
    跑之前先 dot-source 构建环境：

        . .\tools\build-env.ps1
        .\scripts\release.ps1 -Prerelease

    不 dot-source 时 ANDROID_HOME / JAVA_HOME 不在环境里，第 3 步的签名校验找不到
    apksigner / keytool，只会打印「跳过签名校验」而不报错 —— 这一步就空转了。
    2026-11-05 发 v0.12.9 时实际发生过一次，那个包是另外手工验的。

    另一个坑记在这里：2026-11-06 之前，app/test/alarm_screen_test.dart 那条用例拿
    「现在 + 5 分钟」当样本，于是每天 23:55-23:59 之间跑全套会无缘无故红一条 ——
    跨过午夜之后 24 小时值班把它锚在当天，那个时刻已经过去。当天已把用例钉到固定
    时钟；这条不再拦人，留着是因为**时间本身也能让测试变红**：出包前碰上一次
    「谁都没动却红了」，先看表，再查代码。

    签名校验默认**硬拦**（跑不了就 throw），要跳过必须显式加 -SkipSignCheck；
    而且它**不受 -SkipVerify 影响** —— 紧急补发跳一致性校验时，签名照验。
#>

[CmdletBinding()]
param(
    [string]$Version,
    [string]$NotesFile,
    [switch]$SkipVerify,
    [switch]$SkipConfirm,
    [switch]$Prerelease,
    [switch]$Stable,
    [switch]$SkipSignCheck,
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
    Write-Host "[4/6] 一致性校验: 已跳过 (-SkipVerify)；签名校验照跑"
}

# ---- 3b. 签名校验：无论上面是否 -SkipVerify，都跑 ----
# 这一段**不受 -SkipVerify 管**：跳过一致性校验不等于跳过签名校验（2026-11-06 收掉的门）。
#
# v0.11.16 第一次发出去的那个 APK，是在一个 **git worktree** 里构建的 —— 而
# `app/android/key.properties` 与 `keystore/release.jks` **都是 gitignore 的**，
# worktree 里没有，`build.gradle.kts` 于是**静默回退到 debug 证书**。包发出去、
# 版本号 / 资产 / latest.json 全对，用户一装就报「Conflicting app signatures」
# （`Couldn't install (-7)`），只能卸载重装。**签名不对，上面那几条校验一条都照不出来。**
#
# 判据：APK 的签名证书必须与 `release.jks` 里那一枚**逐位相同**。
# 不拿 DN 比（DN 是人填的、可以重名），拿 SHA-256。
$kpPath = Join-Path $root 'app\android\key.properties'
if (-not (Test-Path $kpPath)) {
    throw "app\android\key.properties 不存在 —— 这样构建出来的 APK 会用 **debug 证书**签名，用户装不上（Conflicting app signatures）。请从备份恢复 key.properties 与 keystore\release.jks，然后重新构建。"
}

$btDir = if ($env:ANDROID_HOME) { Join-Path $env:ANDROID_HOME 'build-tools' } else { $null }
$apksigner = $null
if ($btDir -and (Test-Path $btDir)) {
    $apksigner = Get-ChildItem $btDir -Directory |
        Sort-Object { try { [version]$_.Name } catch { [version]'0.0.0' } } |
        ForEach-Object { Join-Path $_.FullName 'apksigner.bat' } |
        Where-Object { Test-Path $_ } | Select-Object -Last 1
}
$keytool = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin\keytool.exe' } else { $null }

if (-not $apksigner -or -not $keytool -or -not (Test-Path $keytool)) {
    # 工具不全 → 默认拦下来（2026-11-06 用户定：签名是「这包能不能装到用户手机上」的唯一保证，
    # 跑不了就等于没有保证，而「没有保证」不该是默认放行）。确实要跳过时显式加 -SkipSignCheck。
    $signWhy = "找不到 apksigner / keytool（ANDROID_HOME / JAVA_HOME 没设？）—— 签名校验跑不了。"
    if ($SkipSignCheck) {
        Write-Warning "$signWhy`n  （已显式 -SkipSignCheck：跳过。这次没人替你确认过这个 APK 用的是不是 release.jks。）"
    } else {
        throw @"
${signWhy}签名是「这包能不能装到用户手机上」的唯一保证 —— 跑不了就等于没有保证，所以默认拦下。装错签名的包，用户只会看到 Conflicting app signatures 然后装不上。
  先 dot-source 构建环境再跑：   . .\tools\build-env.ps1
  确实要跳过（这台机器没有工具链、只是补发）：  加 -SkipSignCheck
"@
    }
} else {
    # 这一段全是原生命令、且 stderr 上写的都是常规输出，照 8b 那条规矩临时放宽
    # ErrorActionPreference（`2>&1` 在 `Stop` 下会把常规提示包成异常抛出来）。
    $prevEapSign = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $props = @{}
        Get-Content $kpPath | ForEach-Object {
            if ($_ -match '^\s*([^#=]+?)\s*=\s*(.+?)\s*$') { $props[$Matches[1]] = $Matches[2] }
        }
        $storeFile = $props['storeFile']
        if ($storeFile -and -not [System.IO.Path]::IsPathRooted($storeFile)) {
            $storeFile = Join-Path (Join-Path $root 'app\android') $storeFile
        }
        $ksOut = & $keytool -list -v -keystore $storeFile -storepass $props['storePassword'] -alias $props['keyAlias'] 2>&1 | Out-String
        $ksDigest = ([regex]::Match($ksOut, 'SHA256:\s*([0-9A-Fa-f:]+)')).Groups[1].Value -replace ':', ''
        $apkOut = & $apksigner verify --print-certs $apk 2>&1 | Out-String
        $apkDigest = ([regex]::Match($apkOut, 'SHA-256 digest:\s*([0-9A-Fa-f:]+)')).Groups[1].Value -replace ':', ''
    } finally {
        $ErrorActionPreference = $prevEapSign
    }

    if (-not $ksDigest -or -not $apkDigest) {
        $signWhy2 = "签名校验没跑成（keytool 或 apksigner 没吐出证书摘要）—— 无法确认这个 APK 是用 release.jks 签的。"
        if ($SkipSignCheck) {
            Write-Warning "$signWhy2`n  （已显式 -SkipSignCheck：跳过。）"
        } else {
            throw @"
${signWhy2}工具在、却没吐出摘要：多半是 keystore 路径 / storePassword / keyAlias 与 key.properties 对不上，或者 apksigner 版本太老。
  确认过要跳过：  加 -SkipSignCheck
"@
        }
    } elseif ($ksDigest -ne $apkDigest) {
        throw @"
APK 的签名证书与 release.jks 对不上 —— 用户会看到「Conflicting app signatures」而装不上（Couldn't install (-7)）。
  release.jks : $($ksDigest.ToLower())
  这个 APK    : $($apkDigest.ToLower())
多半是在一个**没有 key.properties 的地方**构建的（比如 git worktree —— 它和 release.jks 都是 gitignore 的）。请在本仓库根目录下重新构建。
"@
    } else {
        Write-Host "      ✅ 签名证书与 release.jks 一致（$($apkDigest.Substring(0, 16).ToLower())…）"
    }
}


# ---------- 4. 发布说明 ----------
if ($NotesFile) {
    if (-not (Test-Path $NotesFile)) { throw "指定的发布说明文件不存在: $NotesFile" }
    $notes = (Resolve-Path $NotesFile).Path
} else {
    # ⚠️ 2026-11-05 的事故：$notes 这个文件在发版前 1 分钟刚写好（2270 B），这里的
    #    Test-Path 仍判它不存在，于是下面按模板生成、把同名文件覆盖成了 418 B 的占位稿
    #    （Release 正文一度是「（待补充…）」）。事后同一个路径 Test-Path 返回 True，
    #    脚本里也没有 stash / clean / Remove-Item，根因没查出来。
    #    所以：发版一律显式传 -NotesFile 绝对路径，别依赖这条自动查找。
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
Write-Host "[6/8] 创建 $relType Release 并上传 APK..."
$remote = git remote get-url origin
if ($remote -match 'github\.com[:/]([^/]+)/([^/]+?)(\.git)?$') {
    $repo = "$($Matches[1])/$($Matches[2])"
    # 资产名用 ASCII：GitHub Release 资产名不支持非 ASCII，中文会被静默剥离。
    $assetName = "$($Matches[2])-v$Version.apk"
} else {
    $repo = $null
    $assetName = "DaoBanAssistantPro-v$Version.apk"
    Write-Warning "无法从 remote 解析仓库地址，资产名回退为 $assetName"
}
$prereleaseArgs = @()
if ($isPrerelease) { $prereleaseArgs = @('--prerelease') }
# 用 ASCII 文件名副本上传：GitHub 会剥离资产名中的非 ASCII，而 gh 的「路径#新名」在部分版本不可靠。
$uploadApk = Join-Path (Split-Path $apk) $assetName
Copy-Item $apk $uploadApk -Force
& $gh release create $tag $uploadApk --title $title --notes-file $notes --target (git rev-parse --abbrev-ref HEAD) @prereleaseArgs
if ($LASTEXITCODE -ne 0) {
    throw "gh release create 失败（exit $LASTEXITCODE）。若 tag 已存在，可先手动删除或改用新版本号。"
}

# 上传之后再对一次名：2026-11-05 发 v0.12.10 时，上面那个「先 Copy-Item 成 ASCII 名再传」
# 在 Windows 上仍然传成了 app-release.apk（gh 不理会「路径#新名」，且这里没走那条语法），
# 结果 latest.json 里的 asset / url 与实物对不上，App「检查更新」拼出来的地址 404。
# 所以这里**读回来的名字不对就用 API 改名**，改名不改内容（size 与 digest 不变）。
if ($repo) {
    try {
        $rawRel = & $gh api "repos/$repo/releases/tags/$tag"
        if ($LASTEXITCODE -eq 0) {
            $relObj = ($rawRel -join '') | ConvertFrom-Json
            foreach ($a in $relObj.assets) {
                if ($a.name -ne $assetName) {
                    & $gh api -X PATCH "repos/$repo/releases/assets/$($a.id)" -f "name=$assetName" | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "      ✅ 资产名已校正：$($a.name) → $assetName"
                    } else {
                        Write-Warning "资产名校正失败（exit $LASTEXITCODE）：实测名 $($a.name) 与期望 $assetName 不一致，latest.json 的 url 会 404。"
                    }
                }
            }
        }
    } catch {
        Write-Warning "资产名校验没跑成：$_（请手动确认 Release 上的资产名是 $assetName）"
    }
}

# ---------- 7. 验证 ----------
if ($repo) {
    # 两条都与 7b 步同源，见那一段的长注释：
    #   ① `gh api … 2>&1 | ConvertFrom-Json` 不能要 —— stderr 一有输出，`2>&1` 就会在
    #      `$ErrorActionPreference = 'Stop'` 下抛 NativeCommandError；而且 gh 真失败时
    #      那串错误文本会被直接喂进 ConvertFrom-Json，报的是「JSON 解析失败」而不是
    #      「gh 失败了」，看不出真因。所以 stderr 让它照常打到控制台，只管 stdout。
    #   ② **这一步跑在 Release 已经建好之后**，在这儿抛异常会让一次成功的发布看起来
    #      像失败。所以照 7b 立下的同一条规矩办：只告警、不改变发布结论。
    try {
        $raw = & $gh api "repos/$repo/releases/tags/$tag"
        if ($LASTEXITCODE -ne 0) {
            throw "gh api 退出码 $LASTEXITCODE（多为网络或鉴权问题）"
        }
        $rel = ($raw -join '') | ConvertFrom-Json
        Write-Host ""
        Write-Host "✅ 发布成功！"
        Write-Host "   仓库  : $($rel.html_url)"
        foreach ($a in $rel.assets) {
            Write-Host "   资产  : $($a.name)  ($([math]::Round($a.size / 1MB, 1)) MB)"
            Write-Host "   下载  : $($a.browser_download_url)"
        }
    } catch {
        Write-Warning "发布验证没跑成：$_"
        Write-Warning "Release 本身已经建好了（上面那步没报错的话），去仓库页确认一下："
        Write-Warning "  https://github.com/$repo/releases/tag/$tag"
    }
} else {
    Write-Host "✅ Release $tag 已创建（无法从 remote 解析仓库地址，请手动确认）。"
}

# ---------- 8. 更新发布清单 latest.json（App「检查更新」限流时的兜底通道） ----------
if ($repo) {
    $manifestPath = Join-Path $root 'latest.json'
    $downloadUrl = "https://github.com/$repo/releases/download/$tag/$assetName"
    $update = [pscustomobject]@{
        version    = $Version
        url        = $downloadUrl
        prerelease = [bool]$isPrerelease
        asset      = $assetName
    }
    $manifest = $null
    if (Test-Path $manifestPath) {
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    }
    if (-not $manifest) { $manifest = [pscustomobject]@{} }
    if ($isPrerelease) {
        $manifest | Add-Member -Force -MemberType NoteProperty -Name 'prerelease' -Value $update
    } else {
        $manifest | Add-Member -Force -MemberType NoteProperty -Name 'stable' -Value $update
    }
    # updatedAt 必须是真的 UTC。2026-11-05 发 v0.12.10 时这里被手工写成「本地时间贴个 Z」
    # （00:25:00Z，实际是 08:25 本地），比真值早/晚 8 小时 —— 所以下面一律走 ToUniversalTime()，
    # 谁要手工改 latest.json 也必须用 Get-Date -AsUTC 或换算后再贴 Z。
    $manifest | Add-Member -Force -MemberType NoteProperty -Name 'updatedAt' -Value ((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
    [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))
    Write-Host "[8/8] latest.json 已更新（stable=$($manifest.stable.version) / prerelease=$($manifest.prerelease.version)）"

    $dirty = @(git status --porcelain -- latest.json)
    if ($dirty.Count -gt 0) {
        git add latest.json | Out-Null
        git commit -m "chore(release): 更新发布清单至 v$Version" | Out-Null
        git push origin HEAD
        Write-Host "      ✅ latest.json 已提交并推送"
    } else {
        Write-Host "      latest.json 无变化，跳过提交"
    }

    # ---- 8b. 非 main 分支时：把这份清单也同步到 main ----
    #
    # App 的**兜底**更新通道读的是 raw.githubusercontent.com/<owner>/<repo>/main/latest.json
    # （主通道走 Releases API，与分支无关）。所以测试版在 beta 之类分支上发完之后，
    # 这份清单必须也落到 main —— 否则 GitHub API 被限流（403）时，App 读到的清单会
    # 停在旧版本，表现是「明明有更新的测试版，App 却说已是最新」。
    #
    # ⚠️ 只把**本次发布那个通道**的字段写进 main 那份，不是把本分支的整份文件搬过去。
    #    原先这里写的是 `git checkout $branchNow -- latest.json`（整份覆盖）—— 而正式版
    #    在 main 上发、测试版在 beta 上发，beta 那份的 `stable` 永远停在它自己上次见到的
    #    旧值，于是**每在 beta 发一次测试版，就把 main 上正确的 stable 覆盖回去一次**。
    #    v0.11.0 就是这么丢的：8d25b78（在 main 上）把 stable 写成 0.11.0，紧接着的
    #    972192f（v0.11.1 同步 beta）整份搬过来，stable 退回 0.10.0 并一直卡在那里 ——
    #    表现是停在 0.10.x 的用户在**正式通道**里永远看不到 0.11.0（2026-10-13 查清）。
    $branchNow = git rev-parse --abbrev-ref HEAD
    if ($branchNow -ne 'main') {
        # 本次发布写哪个通道，判据与第 8 步同一处。
        $channel = if ($isPrerelease) { 'prerelease' } else { 'stable' }
        Write-Host "      同步 latest.json 的 $channel 通道到 main（兜底通道读的是 main 上那份）..."

        # 这一段里的 git 调用，stderr 上写的全是**正常提示**（切换分支时 git 会往
        # stderr 写「Switched to branch 'main'」）。而在脚本顶部的
        # `$ErrorActionPreference = 'Stop'` 下，`git … 2>&1 | Out-Null` 会把那行提示
        # 包成 NativeCommandError **抛出来** —— git 明明成功了也照抛。
        #
        # 2026-09-23 实测（PowerShell 5.1）：带 `2>&1` 必抛、不带 `2>&1` 不抛、
        # `2>$null` 也抛。所以不是「偶尔失败」，是**必然失败** —— 7b 步上线后发过
        # 两次测试版（v0.9.4 / v0.9.5），两次都挂在这一行、两次都靠手动补 main。
        #
        # 修法：这一段临时放宽成 Continue，成败只看下面的 $LASTEXITCODE（本来就逐个
        # 查着）。`throw` 不受 ErrorActionPreference 影响，下面那几条判断照常生效。
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            git checkout main 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "git checkout main 失败" }

            # **先把本地 main 对齐到 origin/main。** 本地那个 ref 很容易是旧的：
            # 在 beta 上干活时它一动不动，而从别处（比如 worktree）直接
            # `git push origin HEAD:main` 也只更新远端。一旦落后，下面那次
            # `git push origin main` 会被拒（non-fast-forward）—— v0.11.16 那次
            # 就是这么挂的，靠手工 reset 才补上。
            # 只允许**快进**：真有未推送的提交（那才是该由人看一眼的情况）就抛出去
            # 走下面那条告警路径，绝不替人丢掉东西。
            git fetch origin main 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "git fetch origin main 失败" }
            git merge --ff-only origin/main 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "本地 main 无法快进到 origin/main（可能有未推送的提交）" }

            # 读 main 自己那份，只改本次发布那个通道 —— 另一个通道原样留着，
            # 它可能就是 main 上刚发过的正式版，正是「整份覆盖」会弄丢的东西。
            $mainManifest = $null
            if (Test-Path $manifestPath) {
                $mainManifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            }
            if (-not $mainManifest) { $mainManifest = [pscustomobject]@{} }
            $mainManifest | Add-Member -Force -MemberType NoteProperty -Name $channel -Value $update
            $mainManifest | Add-Member -Force -MemberType NoteProperty -Name 'updatedAt' -Value ((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
            [System.IO.File]::WriteAllText($manifestPath, ($mainManifest | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))

            if (@(git status --porcelain -- latest.json).Count -gt 0) {
                git add latest.json | Out-Null
                git commit -m "chore(release): 更新发布清单至 v$Version（同步 $branchNow）" | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "提交到 main 失败" }
                git push origin main
                if ($LASTEXITCODE -ne 0) { throw "推送 main 失败" }
                Write-Host "      ✅ main 上的 latest.json 已同步（$channel = v$Version）"
            } else {
                Write-Host "      main 上已经是这份，跳过"
            }
        } catch {
            # 发布本身已经成功（tag 与资产都在），别让这一步把它变成「失败」——
            # 告警 + 把手动命令打出来。
            Write-Warning "latest.json 同步到 main 失败：$_"
            Write-Warning ("请手动切到 main，把 latest.json 的 '$channel' 改成本次发布的 v$Version" +
                "（version / url / asset 照 $branchNow 那份），顺带更新 updatedAt，" +
                "commit -m 'chore(release): 更新发布清单至 v$Version（同步 $branchNow）' 后 git push origin main，最后切回 $branchNow。")
            Write-Warning "⚠️ 别用 'git checkout $branchNow -- latest.json' 整份覆盖 —— 那会把 main 上另一个通道一起改掉。"
            Write-Warning "⚠️ 若挂在 'git push origin main' 的 non-fast-forward 上，是**本地 main 落后于 origin/main**：先 'git fetch origin' 再 'git reset --hard origin/main'，然后照上面重做一遍。"
        } finally {
            # 切回原分支这行同样会往 stderr 写提示，所以必须仍在 Continue 下跑，
            # 跑完再把 ErrorActionPreference 还原（脚本尾部还有别的动作）。
            git checkout $branchNow 2>&1 | Out-Null
            $ErrorActionPreference = $prevEap
        }
    }
}
