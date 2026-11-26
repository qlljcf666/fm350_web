@echo off
chcp 65001 >nul
REM ================================================================
REM  FM350 Web Console · 350 一键部署
REM ================================================================
REM  自动查找 bash (Git Bash 优先, WSL 兜底) 然后调用 deploy.sh
REM  也支持命令行参数: 350一键部署.bat install / status / ...
REM ================================================================

setlocal
cd /d "%~dp0"

REM 检查 adb
where adb >nul 2>&1
if errorlevel 1 (
    echo [错误] 未找到 adb 命令
    echo        请安装 Android Platform Tools 并加入 PATH
    echo        https://developer.android.com/tools/releases/platform-tools
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
    echo        Git Bash: https://git-scm.com/download/win
    pause
    exit /b 1
)

:bash_found

echo ============================================================
echo   FM350 Web Console · 350 一键部署工具
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
echo   FM350 Web Console · 350 一键部署
echo ============================================================
echo.
echo   [1] install    - 推送文件并安装
echo   [2] start      - 安装 + 启动全部服务
echo   [3] stop       - 停止全部服务
echo   [4] restart    - 重启服务
echo   [5] status     - 查看运行状态
echo   [6] enable     - 写入开机自启 (rc.local)
echo   [7] disable    - 关闭开机自启
echo   [8] push       - 只推送文件 (不启动)
echo   [9] uninstall  - 卸载全部
echo   [0] 退出
echo.
echo   bash: %BASH_CMD%
echo   adb : 就绪
echo   目录: %cd%
echo.
set "CHOICE="
set /p "CHOICE=请选择 (0-9): "

if "%CHOICE%"=="0" goto :end
if "%CHOICE%"=="1" set "ARG=install"   & goto :run
if "%CHOICE%"=="2" set "ARG=start"     & goto :run
if "%CHOICE%"=="3" set "ARG=stop"      & goto :run
if "%CHOICE%"=="4" set "ARG=restart"   & goto :run
if "%CHOICE%"=="5" set "ARG=status"    & goto :run
if "%CHOICE%"=="6" set "ARG=enable"    & goto :run
if "%CHOICE%"=="7" set "ARG=disable"   & goto :run
if "%CHOICE%"=="8" set "ARG=push"      & goto :run
if "%CHOICE%"=="9" set "ARG=uninstall" & goto :run

echo 无效选择, 请输入 0-9
pause
goto :menu

:run
echo.
echo ------------------------------------------------------------
echo  执行:  deploy.sh %ARG%
echo  bash:  %BASH_CMD%
echo  目录:  %cd%
echo ------------------------------------------------------------
echo.

%BASH_CMD% ./deploy.sh %ARG%

if errorlevel 1 (
    echo.
    echo [错误] deploy.sh 返回非零退出码
) else (
    echo.
    echo [完成] 部署成功
)

echo.
pause
goto :menu

:end
endlocal