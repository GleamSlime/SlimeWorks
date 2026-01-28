@echo off
setlocal enabledelayedexpansion

REM Get script directory and navigate to project root
set "INSTALLER_DIR=%~dp0"
cd /d "%INSTALLER_DIR%\.."
set "PROJECT_ROOT=%CD%"

echo ========================================
echo Building SlimeWorks Windows Installer
echo ========================================
echo Project Root: %PROJECT_ROOT%
echo.

echo [1/4] Cleaning project...
call flutter clean
if errorlevel 1 goto error

echo.
echo [2/4] Getting dependencies...
call flutter pub get
if errorlevel 1 goto error

echo.
echo [3/4] Building Windows release...
call flutter build windows --release
if errorlevel 1 goto error

echo.
echo [3.5/4] Building and copying capture_proxy module...
cd /d "%PROJECT_ROOT%\rust\capture_proxy"
call cargo build --release --lib
if errorlevel 1 (
    echo [WARNING] Failed to build capture_proxy.dll
) else (
    cd /d "%PROJECT_ROOT%"
    if not exist "build\windows\x64\runner\Release\modules\capture_proxy" mkdir "build\windows\x64\runner\Release\modules\capture_proxy"
    copy /Y "rust\target\release\capture_proxy.dll" "build\windows\x64\runner\Release\modules\capture_proxy\capture_proxy.dll"
    if errorlevel 1 (
        echo [WARNING] Failed to copy capture_proxy.dll
    ) else (
        echo [SUCCESS] capture_proxy.dll copied successfully
    )
)

echo.
echo [4/4] Creating NSIS installer...
cd /d "%INSTALLER_DIR%"
if not exist output mkdir output
if exist "C:\Program Files (x86)\NSIS\makensis.exe" (
    "C:\Program Files (x86)\NSIS\makensis.exe" installer.nsi
    if errorlevel 1 goto error
) else (
    echo [ERROR] NSIS not found!
    echo Download: https://nsis.sourceforge.io/Download
    goto error
)

echo.
echo ========================================
echo [SUCCESS] Build completed!
echo ========================================
echo Installer: %INSTALLER_DIR%output\SlimeWorks_Setup.exe
echo.
goto end

:error
echo.
echo ========================================
echo [ERROR] Build failed!
echo ========================================
echo.
pause
exit /b 1

:end
endlocal
pause
