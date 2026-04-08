@echo off
REM 开发环境模块部署脚本
REM 用于在本地开发时自动复制 capture_proxy.dll 到正确位置

echo ========================================
echo 部署 Capture Proxy 模块到开发环境
echo ========================================
echo.

REM 获取 AppData 路径
set "MODULE_DIR=%APPDATA%\SlimeWorks\modules\capture_proxy"
set "DLL_SOURCE=rust\target\release\capture_proxy.dll"

echo [1/3] 检查源文件...
if not exist "%DLL_SOURCE%" (
    echo [ERROR] 源文件不存在: %DLL_SOURCE%
    echo 请先运行: cd rust\capture_proxy ^&^& cargo build --release --lib
    goto error
)
echo [OK] 找到源文件

echo.
echo [2/3] 创建目标目录...
if not exist "%MODULE_DIR%" mkdir "%MODULE_DIR%"
echo [OK] 目录: %MODULE_DIR%

echo.
echo [3/3] 复制 DLL 文件...
copy /Y "%DLL_SOURCE%" "%MODULE_DIR%\capture_proxy.dll"
if errorlevel 1 goto error

echo [OK] 部署完成

echo.
echo 模块位置: %MODULE_DIR%\capture_proxy.dll
echo.
echo [3.5/3] 创建版本文件...
echo 1.0.0 > "%MODULE_DIR%\version.txt"
echo [OK] 版本文件已创建

echo.
echo ========================================
echo [SUCCESS] 模块部署成功！
echo ========================================
echo.
echo 现在可以运行: flutter run -d windows
echo.
goto end

:error
echo.
echo ========================================
echo [ERROR] 部署失败！
echo ========================================
echo.
pause
exit /b 1

:end
pause
