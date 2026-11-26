@echo off
chcp 65001 >nul
REM ============================================================
REM  FM350 一键补齐 — Windows 启动器
REM ============================================================
REM  自动查找 bash (Git Bash 优先, WSL 兜底) 然后调用 deploy.sh
REM  也支持命令行参数: 一键补齐.bat install / status / ...
REM ============================================================

setlocal
cd /d "%~dp0"

REM 确保 rootfs 目录存在
if not exist rootfs (
    echo [错误] rootfs 目录不存在!
    echo        请确保 deploy.sh 和 rootfs\ 在同一目录
    pause
    exit /b 1
)

REM 检查 adb
where adb >nul 2>&1
if errorlevel 1 (
    echo [错误] 未找到 adb.exe
    echo        请安装 Android Platform Tools 并加入 PATH
    pause
    exit /b 1
)

REM 找 bash: Git Bash 优先, WSL 兜底
set "BASH_CMD="

where bash >nul 2>&1
if not errorlevel 1 (
    for /f "delims=" %%i in ('where bash ^| findstr /i "Git Bash" 2^>nul') do (
        set "BASH_CMD=%%i"
    )
)

if not defined BASH_CMD (
    for /f "delims=" %%i in ('where bash 2^>nul') do (
        set "BASH_CMD=%%i"
        goto :bash_found
    )
)

if not defined BASH_CMD (
    where wsl >nul 2>&1
    if not errorlevel 1 (
        set "BASH_CMD=wsl.exe bash"
    )
)

if not defined BASH_CMD (
    echo [错误] 未找到 bash
    echo        请安装 Git for Windows 或启用 WSL
    pause
    exit /b 1
)

:bash_found

echo ============================================================
echo   FM350 一键补齐部署工具
echo ============================================================
echo.
echo  bash: %BASH_CMD%
echo  包路径: %cd%
echo.

REM 如果有命令行参数, 直接透传
if "%~1" NEQ "" (
    echo 动作: %*
    echo.
    %BASH_CMD% ./deploy.sh %*
    goto :end
)

REM 交互式菜单
:menu
cls
echo ============================================================
echo   FM350 一键补齐 - 主菜单
echo ============================================================
echo.
echo   [1] 安装并启动       (推送所有文件 + chmod + 启动服务)
echo   [2] 只推送文件       (不启动服务)
echo   [3] 启动补齐服务     (fw3 + dnsmasq + dropbear + uhttpd + rpcd)
echo   [4] 停止补齐服务
echo   [5] 重启补齐服务
echo   [6] 查看服务状态
echo   [7] 设置开机自启
echo   [8] 取消开机自启
echo   [9] 卸载补齐
echo   [0] 退出
echo.
set /p "CHOICE=请选择 (0-9): "

if "%CHOICE%"=="1" goto :install
if "%CHOICE%"=="2" goto :push
if "%CHOICE%"=="3" goto :start
if "%CHOICE%"=="4" goto :stop
if "%CHOICE%"=="5" goto :restart
if "%CHOICE%"=="6" goto :status
if "%CHOICE%"=="7" goto :enable
if "%CHOICE%"=="8" goto :disable
if "%CHOICE%"=="9" goto :uninstall
if "%CHOICE%"=="0" goto :end
goto :menu

:install
%BASH_CMD% ./deploy.sh install
pause
goto :menu
:push
%BASH_CMD% ./deploy.sh push
pause
goto :menu
:start
%BASH_CMD% ./deploy.sh start
pause
goto :menu
:stop
%BASH_CMD% ./deploy.sh stop
pause
goto :menu
:restart
%BASH_CMD% ./deploy.sh restart
pause
goto :menu
:status
%BASH_CMD% ./deploy.sh status
pause
goto :menu
:enable
%BASH_CMD% ./deploy.sh enable
pause
goto :menu
:disable
%BASH_CMD% ./deploy.sh disable
pause
goto :menu
:uninstall
%BASH_CMD% ./deploy.sh uninstall
pause
goto :menu

:end
endlocal
