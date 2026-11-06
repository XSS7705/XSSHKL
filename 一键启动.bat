@echo off
setlocal
title ApplIO Auto Setup
echo ================================================
echo   ApplIO Auto Setup + Start
echo ================================================
echo.

rem ==== Find RVC folder by wildcard (no non-ASCII in this file) ====
set "WORKDIR="
for /d %%D in ("%USERPROFILE%\Desktop\RVC*") do set "WORKDIR=%%D"
if not defined WORKDIR (
    echo [ERROR] RVC folder not found on Desktop.
    pause
    exit /b 1
)
echo Workdir: %WORKDIR%
if not exist "%WORKDIR%\Applio\app.py" (
    echo [ERROR] Applio\app.py not found under workdir.
    pause
    exit /b 1
)

rem ==== 1. Python 3.12 ====
echo [1/6] Checking Python 3.12 ...
set "PY312="
py -3.12 --version >nul 2>&1
if not errorlevel 1 set "PY312=py -3.12"
if not defined PY312 if exist "%LocalAppData%\Programs\Python\Python312\python.exe" set "PY312=%LocalAppData%\Programs\Python\Python312\python.exe"
if not defined PY312 if exist "%ProgramFiles%\Python312\python.exe" set "PY312=%ProgramFiles%\Python312\python.exe"
if not defined PY312 (
    echo [ERROR] Python 3.12 not found.
    pause
    exit /b 1
)
echo       Using: %PY312%
%PY312% --version
echo.

rem ==== 2. venv (rebuild only if wrong version) ====
echo [2/6] Preparing venv ...
set "REBUILD=1"
if exist "%WORKDIR%\env\Scripts\python.exe" (
    "%WORKDIR%\env\Scripts\python.exe" --version 2>nul | findstr /C:"3.12" /C:"3.13" >nul && set "REBUILD=0"
)
if "%REBUILD%"=="1" (
    echo       Creating env ...
    if exist "%WORKDIR%\env" rmdir /s /q "%WORKDIR%\env"
    %PY312% -m venv "%WORKDIR%\env"
    if errorlevel 1 (
        echo [ERROR] venv creation failed.
        pause
        exit /b 1
    )
) else (
    echo       env OK, skip.
)
set "VENV_PY=%WORKDIR%\env\Scripts\python.exe"
"%VENV_PY%" --version
echo.

rem ==== 3. pip ====
echo [3/6] Upgrading pip ...
"%VENV_PY%" -m pip install --upgrade pip -q -i https://pypi.tuna.tsinghua.edu.cn/simple
echo       OK
echo.

rem ==== 4. torch cu128 ====
echo [4/6] Checking PyTorch cu128 (3.4GB first time) ...
"%VENV_PY%" -c "import torch" >nul 2>&1
if errorlevel 1 (
    echo       Downloading torch cu128 ...
    "%VENV_PY%" -m pip install torch==2.8.0 torchaudio==2.8.0 --index-url https://download.pytorch.org/whl/cu128
    if errorlevel 1 (
        echo [ERROR] torch install failed. Check network.
        pause
        exit /b 1
    )
) else (
    echo       Already installed, skip.
)
echo.

rem ==== 5. requirements ====
echo [5/6] Checking ApplIO requirements ...
"%VENV_PY%" -c "import gradio" >nul 2>&1
if errorlevel 1 (
    echo       Installing requirements (5-15 min) ...
    "%VENV_PY%" -m pip install -r "%WORKDIR%\Applio\requirements.txt" -i https://pypi.tuna.tsinghua.edu.cn/simple
    if errorlevel 1 (
        echo [ERROR] requirements install failed.
        echo Copy the red text above and send to assistant.
        pause
        exit /b 1
    )
) else (
    echo       Already installed, skip.
)
echo.

rem ==== 6. GPU + start ====
echo [6/6] GPU check:
"%VENV_PY%" -c "import torch;print('  GPU:',torch.cuda.get_device_name(0) if torch.cuda.is_available() else '  !!! NO GPU DETECTED !!!')"
echo.
set HF_ENDPOINT=https://hf-mirror.com
echo ================================================
echo   Starting ApplIO - browser opens localhost:6969
echo ================================================
start "" http://localhost:6969
"%VENV_PY%" "%WORKDIR%\Applio\app.py" --port 6969
pause
