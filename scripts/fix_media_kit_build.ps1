# fix_media_kit_build.ps1
# 修复 media_kit_libs_windows_video 构建问题
# 问题：flutter clean 会清除 libmpv/ANGLE 解压缓存，导致重新构建时因缺少 7-Zip 而失败
# 用法：在项目根目录下运行 script\fix_media_kit_build.ps1

$ErrorActionPreference = "Stop"
$BuildDir = Join-Path $PSScriptRoot "..\build\windows\x64"
$BuildDir = [System.IO.Path]::GetFullPath($BuildDir)

$SevenZipPaths = @(
    "C:\Program Files\7-Zip\7z.exe",
    "C:\Program Files (x86)\7-Zip\7z.exe"
)

# ── 查找或安装 7-Zip ─────────────────────────────────────────────────────
$SevenZip = $null
foreach ($p in $SevenZipPaths) {
    if (Test-Path $p) {
        $SevenZip = $p
        break
    }
}

if (-not $SevenZip) {
    Write-Host "[1/4] 7-Zip 未安装，正在通过 winget 安装..." -ForegroundColor Yellow
    winget install 7zip.7zip --accept-package-agreements --accept-source-agreements
    if (Test-Path $SevenZipPaths[0]) {
        $SevenZip = $SevenZipPaths[0]
    } else {
        Write-Host "错误：7-Zip 安装失败，请手动安装后重试" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[1/4] 7-Zip 已找到: $SevenZip" -ForegroundColor Green
}

# ── 检查构建目录 ──────────────────────────────────────────────────────────
if (-not (Test-Path $BuildDir)) {
    Write-Host "构建目录不存在，请先运行 flutter pub get 和 flutter build windows" -ForegroundColor Red
    exit 1
}

# ── 解压 libmpv ───────────────────────────────────────────────────────────
$LibmpvDir = Join-Path $BuildDir "libmpv"
$LibmpvArchive = Join-Path $BuildDir "mpv-dev-x86_64-20230924-git-652a1dd.7z"
$LibmpvInclude = Join-Path $LibmpvDir "include"

$LibmpvValid = $false
if (Test-Path $LibmpvInclude) {
    $headerFiles = Get-ChildItem $LibmpvInclude -Filter "*.h" -ErrorAction SilentlyContinue
    if ($headerFiles.Count -gt 0) {
        $LibmpvValid = $true
    }
}

if (-not $LibmpvValid) {
    if (-not (Test-Path $LibmpvArchive)) {
        Write-Host "libmpv 压缩包不存在: $LibmpvArchive" -ForegroundColor Red
        Write-Host "请先运行 flutter build windows 让 CMake 下载依赖" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "[2/4] 正在解压 libmpv..." -ForegroundColor Yellow
    # 清理残留
    if (Test-Path $LibmpvDir) { Remove-Item $LibmpvDir -Recurse -Force }
    New-Item -ItemType Directory -Path $LibmpvDir -Force | Out-Null
    & $SevenZip x $LibmpvArchive -o"$LibmpvDir" -y | Out-Null

    # 修正目录结构: include/mpv/ -> include/
    $mpvSubDir = Join-Path $LibmpvDir "include\mpv"
    if (Test-Path $mpvSubDir) {
        $tmpDir = Join-Path $LibmpvDir "mpv_tmp"
        Move-Item $mpvSubDir $tmpDir
        Remove-Item (Join-Path $LibmpvDir "include") -Recurse -Force
        Move-Item $tmpDir $LibmpvInclude
    }
    Write-Host "      libmpv 解压完成" -ForegroundColor Green
} else {
    Write-Host "[2/4] libmpv 已存在，跳过" -ForegroundColor Green
}

# ── 解压 ANGLE ────────────────────────────────────────────────────────────
$AngleDir = Join-Path $BuildDir "ANGLE"
$AngleArchive = Join-Path $BuildDir "ANGLE.7z"

$AngleValid = $false
if (Test-Path $AngleDir) {
    $dllFiles = Get-ChildItem $AngleDir -Filter "*.dll" -ErrorAction SilentlyContinue
    if ($dllFiles.Count -gt 0) {
        $AngleValid = $true
    }
}

if (-not $AngleValid) {
    if (-not (Test-Path $AngleArchive)) {
        Write-Host "ANGLE 压缩包不存在: $AngleArchive" -ForegroundColor Red
        Write-Host "请先运行 flutter build windows 让 CMake 下载依赖" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "[3/4] 正在解压 ANGLE..." -ForegroundColor Yellow
    if (Test-Path $AngleDir) { Remove-Item $AngleDir -Recurse -Force }
    New-Item -ItemType Directory -Path $AngleDir -Force | Out-Null
    & $SevenZip x $AngleArchive -o"$AngleDir" -y | Out-Null
    Write-Host "      ANGLE 解压完成" -ForegroundColor Green
} else {
    Write-Host "[3/4] ANGLE 已存在，跳过" -ForegroundColor Green
}

# ── 清理 CMake 缓存（如果需要） ──────────────────────────────────────────
$CmakeCache = Join-Path $BuildDir "CMakeCache.txt"
if (Test-Path $CmakeCache) {
    $cacheContent = Get-Content $CmakeCache -Raw
    if ($cacheContent -match "SEVEN_ZIP_EXE.*NOTFOUND" -or -not ($cacheContent -match "SEVEN_ZIP_EXE")) {
        Write-Host "[4/4] CMake 缓存中 7-Zip 配置无效，清理缓存..." -ForegroundColor Yellow
        Remove-Item $CmakeCache -Force
        Remove-Item (Join-Path $BuildDir "CMakeFiles") -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "      下次构建时 CMake 将重新配置" -ForegroundColor Green
    } else {
        Write-Host "[4/4] CMake 缓存正常" -ForegroundColor Green
    }
} else {
    Write-Host "[4/4] 无 CMake 缓存，首次构建将自动配置" -ForegroundColor Green
}

Write-Host ""
Write-Host "修复完成！现在可以运行 flutter run -d windows" -ForegroundColor Cyan
