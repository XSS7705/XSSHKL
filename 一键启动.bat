@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion
title ApplIO 夜阑版 - 一键启动

echo ================================================
echo   ApplIO 夜阑专用版 - 自动安装 + 启动
echo ================================================
echo.

set "WORKDIR=%~dp0"
cd /d "%WORKDIR%"

rem ============ 1. 定位 Python 3.12 ============
echo [1/6] 检查 Python 3.12...
set "PY312="
py -3.12 --version >nul 2>&1
if not errorlevel 1 set "PY312=py -3.12"
if not defined PY312 if exist "%LocalAppData%\Programs\Python\Python312\python.exe" set "PY312=%LocalAppData%\Programs\Python\Python312\python.exe"
if not defined PY312 if exist "%ProgramFiles%\Python312\python.exe" set "PY312=%ProgramFiles%\Python312\python.exe"
if not defined PY312 if exist "%LocalAppData%\Programs\Python\Python313\python.exe" set "PY312=%LocalAppData%\Programs\Python\Python313\python.exe"

if not defined PY312 (
    echo.
    echo !!!! 未检测到 Python 3.12 !!!!
    echo 请从 https://www.python.org/downloads/release/python-31210/ 下载
    echo "Windows installer (64-bit)"，安装时勾选 "Add python.exe to PATH"
    echo.
    pause
    exit /b 1
)
echo       使用: %PY312%
%PY312% --version
echo.

rem ============ 2. 创建/重建虚拟环境 ============
echo [2/6] 准备虚拟环境 env ...
if not exist "%WORKDIR%env\Scripts\python.exe" (
    echo       env 不存在，正在创建...
    if exist "%WORKDIR%env" rmdir /s /q "%WORKDIR%env"
    %PY312% -m venv "%WORKDIR%env"
    if errorlevel 1 (
        echo !!!! 创建虚拟环境失败 !!!!
        pause
        exit /b 1
    )
)
set "VENV_PY=%WORKDIR%env\Scripts\python.exe"
"%VENV_PY%" --version
echo.

rem ============ 3. 升级 pip ============
echo [3/6] 升级 pip...
"%VENV_PY%" -m pip install --upgrade pip -q -i https://pypi.tuna.tsinghua.edu.cn/simple
echo       OK
echo.

rem ============ 4. 安装 PyTorch cu128 ============
echo [4/6] 检查 PyTorch (cu128, 约3.4GB, 首次需下载)...
"%VENV_PY%" -c "import torch" >nul 2>&1
if errorlevel 1 (
    echo       未安装，开始下载 torch cu128 ...
    "%VENV_PY%" -m pip install torch==2.8.0 torchaudio==2.8.0 --index-url https://download.pytorch.org/whl/cu128
    if errorlevel 1 (
        echo !!!! PyTorch 安装失败，请检查网络 !!!!
        pause
        exit /b 1
    )
) else (
    echo       已安装，跳过
)
echo.

rem ============ 5. 安装 ApplIO 依赖 ============
echo [5/6] 检查 ApplIO 依赖...
"%VENV_PY%" -c "import gradio" >nul 2>&1
if errorlevel 1 (
    echo       开始安装依赖 (使用清华镜像，约5-15分钟) ...
    "%VENV_PY%" -m pip install -r "%WORKDIR%Applio\requirements.txt" -i https://pypi.tuna.tsinghua.edu.cn/simple
    if errorlevel 1 (
        echo.
        echo !!!! 依赖安装失败 !!!!
        echo 请把上面的红色错误信息复制给助手
        pause
        exit /b 1
    )
) else (
    echo       已安装，跳过
)
echo.

rem ============ 6. 显卡检查 + 启动 ============
echo [6/6] 显卡检查：
"%VENV_PY%" -c "import torch;print('  GPU:',torch.cuda.get_device_name(0) if torch.cuda.is_available() else '!!! 未检测到GPU !!!')"
echo.

set HF_ENDPOINT=https://hf-mirror.com
echo ================================================
echo   启动 ApplIO，浏览器将自动打开 localhost:6969
echo ================================================
start "" http://localhost:6969
"%VENV_PY%" "%WORKDIR%Applio\app.py" --port 6969
pause
