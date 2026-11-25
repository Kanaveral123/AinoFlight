<#
.SYNOPSIS
  用 SSSU（siglus-ssu）编译「爱乃初次飞行」小游戏所在的场景包。

.DESCRIPTION
  所有路径都相对于本脚本所在的文件夹。默认只编译，结果在 build\Scene.pck，
  不改动游戏文件夹。详细说明见 README.md。

.EXAMPLE
  .\build.ps1                     # 只编译
  .\build.ps1 -Test               # 编译并运行全部离线测试
  .\build.ps1 -Deploy             # 编译并安装到 ..\game
  .\build.ps1 -Python ..\..\sssu_main\.venv\Scripts\python.exe
#>
param(
    # 装有 siglus-ssu 的 Python。留空时按 README 中的顺序自动查找。
    [string]$Python = '',
    # 游戏文件夹（含 SiglusEngine.exe）。相对路径以本文件夹为起点。
    [string]$GameDir = '..\game',
    # 编译后把 Scene.pck 和 11 个新素材复制到游戏文件夹（游戏须先关闭）。
    [switch]$Deploy,
    # 把 save\ 中的 900 号测试存档复制到游戏的 savedata\。
    [switch]$InstallSave,
    # 从游戏原有的 g00 / wav 重新生成地标贴图和引擎声，写回 assets\。
    [switch]$RegenerateAssets,
    # 仅供制作测试存档：编出的包启动后直接进入飞行前的剧情点。
    [switch]$CreateTestSave,
    # 编译后运行全部离线测试。
    [switch]$Test
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$buildDir = Join-Path $root 'build'
$sceneDir = Join-Path $root 'scene'
$toolsDir = Join-Path $root 'tools'
if (-not [IO.Path]::IsPathRooted($GameDir)) { $GameDir = Join-Path $root $GameDir }
$GameDir = [IO.Path]::GetFullPath($GameDir)
$script:ExitCode = 0
$savedOutputEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)

function Step([string]$text) { Write-Host "== $text" -ForegroundColor Cyan }

# Runs the chosen Python; stderr is kept as plain text, never turned into a PowerShell error.
function Invoke-Py([string[]]$Arguments, [string]$Log = '') {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($Log) {
            & $script:Py @Arguments 2>&1 | ForEach-Object { "$_" } | Out-File -LiteralPath $Log -Encoding utf8
        } else {
            & $script:Py @Arguments 2>&1 | ForEach-Object { "$_" } | Out-Host
        }
        $script:ExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $old
    }
}

function Test-SssuPython([string]$exe) {
    if (-not $exe) { return $false }
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $v = & $exe -I -c "import importlib.metadata as m; print(m.version('siglus-ssu'))" 2>$null
        if ($LASTEXITCODE -eq 0 -and $v) {
            $script:SssuVersion = "$v".Trim()
            return $true
        }
    } catch {
    } finally {
        $ErrorActionPreference = $old
    }
    return $false
}

function Get-Sha256([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower() }

try {
    New-Item -ItemType Directory -Force $buildDir | Out-Null

    Step '查找 SSSU'
    $candidates = @()
    if ($Python) { $candidates += $Python }
    if ($env:SIGLUS_SSU_PYTHON) { $candidates += $env:SIGLUS_SSU_PYTHON }
    foreach ($rel in '..\..\sssu_main', '..\sssu_main', 'sssu_main') {
        $candidates += (Join-Path (Join-Path $root $rel) '.venv\Scripts\python.exe')
    }
    $candidates += 'python', 'py'
    $script:Py = $null
    foreach ($c in $candidates) {
        $exe = $c
        if (($c -match '[\\/]') -and -not [IO.Path]::IsPathRooted($c)) { $exe = Join-Path $root $c }
        if (($exe -match '[\\/]') -and -not (Test-Path -LiteralPath $exe)) { continue }
        if (Test-SssuPython $exe) { $script:Py = $exe; break }
    }
    if (-not $script:Py) {
        throw '找不到装有 siglus-ssu 的 Python。请用 -Python 指定，或按 README.md「准备 SSSU」安装。'
    }
    $shown = $script:Py
    if ($shown -match '[\\/]') { $shown = [IO.Path]::GetFullPath($shown) }
    Write-Host "Python: $shown"
    Write-Host "siglus-ssu $script:SssuVersion"
    if ($script:SssuVersion -ne '0.5.4') {
        Write-Warning '本包用 siglus-ssu 0.5.4 编译验证；换用其他版本时运行包哈希可能不同。'
    }

    if ($RegenerateAssets) {
        Step "从游戏原素材重新生成地标贴图和引擎声（$GameDir）"
        Invoke-Py @('-X', 'utf8', (Join-Path $toolsDir 'prepare_flight_audio.py'), '--game', $GameDir)
        if ($script:ExitCode -ne 0) { throw '引擎声生成失败。' }
        Invoke-Py @('-X', 'utf8', (Join-Path $toolsDir 'prepare_flight_landmarks.py'), '--game', $GameDir)
        if ($script:ExitCode -ne 0) { throw '地标贴图生成失败（需要 Pillow）。' }
    }

    # _start.ss must be the game's own unless a test-save build is running.
    $startSs = Join-Path $sceneDir '_start.ss'
    $startOriginal = Join-Path $root 'original\_start.ss'
    if ((Get-Sha256 $startSs) -ne (Get-Sha256 $startOriginal)) {
        Copy-Item -LiteralPath $startOriginal -Destination $startSs -Force
        Write-Host '已把 scene\_start.ss 恢复为原版。'
    }
    if ($CreateTestSave) {
        Step '临时改写 _start.ss（测试存档制作用）'
        Invoke-Py @('-X', 'utf8', (Join-Path $toolsDir 'bootstrap_save.py'))
        if ($script:ExitCode -ne 0) { throw '无法改写 _start.ss。' }
    }

    Step '编译场景（串行，PYTHONHASHSEED=0，可逐字节复现）'
    $compiled = Join-Path $buildDir 'Scene.compiled.pck'
    $runtime = Join-Path $buildDir 'Scene.pck'
    $log = Join-Path $buildDir 'build.log'
    $env:PYTHONUTF8 = '1'
    $env:PYTHONHASHSEED = '0'
    try {
        Invoke-Py @('-I', '-X', 'utf8', '-m', 'siglus_ssu', '-c', '--serial', $sceneDir, $compiled) $log
    } finally {
        Remove-Item Env:PYTHONHASHSEED -ErrorAction SilentlyContinue
        Remove-Item Env:PYTHONUTF8 -ErrorAction SilentlyContinue
        if ($CreateTestSave) {
            Copy-Item -LiteralPath $startOriginal -Destination $startSs -Force
        }
    }
    if ($script:ExitCode -ne 0) {
        Get-Content -LiteralPath $log -Tail 60
        throw "SSSU 编译失败，详见 build\build.log。"
    }
    Get-Content -LiteralPath $log -Tail 7 | Where-Object { $_ -notmatch 'anemoi_' }

    Step '转换为游戏可直接读取的运行包'
    Invoke-Py @('-X', 'utf8', (Join-Path $toolsDir 'runtime_pack.py'), $compiled, $runtime)
    if ($script:ExitCode -ne 0) { throw '运行包转换失败。' }
    $hash = Get-Sha256 $runtime
    Write-Host "build\Scene.pck  SHA256 $hash"
    if ($CreateTestSave) {
        Write-Host '这是测试存档制作用的包，制作完成后请再运行一次普通构建。' -ForegroundColor Yellow
    }

    if ($Test) {
        Step '离线测试'
        foreach ($t in 'test_flight_sim.py', 'test_flight_render.py', 'test_flight_controls.py',
                       'test_flight_audio.py', 'audit_text_layout.py') {
            Write-Host "-- $t"
            Invoke-Py @('-X', 'utf8', (Join-Path $toolsDir $t)) (Join-Path $buildDir ($t + '.log'))
            if ($script:ExitCode -ne 0) {
                Get-Content -LiteralPath (Join-Path $buildDir ($t + '.log')) -Tail 30
                throw "$t 未通过。"
            }
            $pass = Get-Content -LiteralPath (Join-Path $buildDir ($t + '.log')) -Encoding UTF8 | Where-Object { $_ -match '^PASS' }
            if ($pass) { $pass } else { 'PASS' }
        }
    }

    if ($Deploy -or $InstallSave) {
        if (-not (Test-Path -LiteralPath (Join-Path $GameDir 'SiglusEngine.exe'))) {
            throw "游戏文件夹里没有 SiglusEngine.exe：$GameDir（可用 -GameDir 指定）"
        }
        if (Get-Process SiglusEngine -ErrorAction SilentlyContinue) { throw '请先关闭游戏再安装。' }
    }
    if ($Deploy) {
        Step "安装到 $GameDir"
        $target = Join-Path $GameDir 'Scene.pck'
        if ((Test-Path -LiteralPath $target) -and ((Get-Sha256 $target) -ne $hash)) {
            Copy-Item -LiteralPath $target -Destination (Join-Path $buildDir 'Scene.previous.pck') -Force
            Write-Host '原 Scene.pck 已备份为 build\Scene.previous.pck'
        }
        Copy-Item -LiteralPath $runtime -Destination $target -Force
        foreach ($kind in 'g00', 'wav') {
            New-Item -ItemType Directory -Force (Join-Path $GameDir $kind) | Out-Null
            Get-ChildItem -LiteralPath (Join-Path $root "assets\$kind") -File | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $GameDir "$kind\$($_.Name)") -Force
            }
        }
        Write-Host '已安装 Scene.pck、9 张地标贴图和 2 个引擎声。'
    }
    if ($InstallSave) {
        Step '安装 900 号测试存档'
        $saveDir = Join-Path $GameDir 'savedata'
        $backup = Join-Path $buildDir 'savedata-previous'
        New-Item -ItemType Directory -Force $saveDir, $backup | Out-Null
        foreach ($n in '0900.sav', '0900.png') {
            $dst = Join-Path $saveDir $n
            if (Test-Path -LiteralPath $dst) { Copy-Item -LiteralPath $dst -Destination (Join-Path $backup $n) -Force }
            Copy-Item -LiteralPath (Join-Path $root "save\$n") -Destination $dst -Force
        }
        Write-Host '已安装；原有的 900 号存档备份在 build\savedata-previous。'
    }
    Write-Host '完成。' -ForegroundColor Green
} finally {
    [Console]::OutputEncoding = $savedOutputEncoding
}
