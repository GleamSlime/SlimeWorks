@echo off
echo ========================================
echo Building SlimeWorks Windows Installer
echo ========================================
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
echo [4/4] Creating NSIS installer...
cd installer
if not exist output mkdir output
if exist "C:\Program Files (x86)\NSIS\makensis.exe" (
    "C:\Program Files (x86)\NSIS\makensis.exe" installer.nsi
    if errorlevel 1 (
        cd ..
        goto error
    )
) else (
    echo [ERROR] NSIS not found!
    echo Download: https://nsis.sourceforge.io/Download
    cd ..
    goto error
)
cd ..

echo.
echo ========================================
echo [SUCCESS] Build completed!
echo ========================================
echo Installer: installer\output\SlimeWorks_Setup.exe
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
pause