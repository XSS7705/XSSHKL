@echo off
setlocal EnableExtensions
chcp 65001 >nul
title QuantEnv Fix - proxy / offline install
rem ============================================================
rem  Usage:
rem    QuantEnv_Fix.bat            run on the TARGET machine
rem    QuantEnv_Fix.bat build      run on an ONLINE machine to make F:\QuantBundle\wheels
rem ============================================================

set "BUNDLE=F:\QuantBundle"
set "TARGET=D:\QuantEnv\py312"
set "PY=%TARGET%\Scripts\python.exe"
set "UV=%BUNDLE%\uv.exe"
set "REQ=%BUNDLE%\requirements.txt"
set "WHEELS=%BUNDLE%\wheels"
set "M1=https://pypi.tuna.tsinghua.edu.cn/simple"
set "M2=https://mirrors.aliyun.com/pypi/simple"
set "M3=https://mirrors.ustc.edu.cn/pypi/simple"

echo ============================================================
echo  QuantEnv Fix    target = %TARGET%
echo ============================================================
echo.
echo [0/5] Proxy env vars found in this window (will be cleared):
set | findstr /i "proxy" || echo   none
for %%v in (HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy) do set "%%v="
echo   cleared - uv will no longer use a dead proxy (os error 10061 / tunnel error)

if /i "%~1"=="build" goto :build

echo.
echo [1/5] Checking files ...
if not exist "%UV%"  (echo   [ERROR] missing %UV% & goto :fail)
if not exist "%PY%"  (echo   [ERROR] missing %PY% & goto :fail)
if not exist "%REQ%" (echo   [ERROR] missing %REQ% & goto :fail)
echo   ok

echo.
echo [2/5] Windows system proxy (WinINET) ...
set "SYS=0"
reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable 2>nul | findstr /i "0x1" >nul
if not errorlevel 1 set "SYS=1"
if "%SYS%"=="1" (
  echo   [WARN] enabled. Settings ^> Network ^> Proxy : turn it OFF if that proxy is not running.
  reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer 2>nul
) else (
  echo   off
)

echo.
echo [3/5] Direct connectivity test (proxy bypassed) ...
"%PY%" -c "import urllib.request as u;u.build_opener(u.ProxyHandler({})).open('https://pypi.tuna.tsinghua.edu.cn/simple/',timeout=10);print('NET_OK')" 2>nul
if errorlevel 1 (set "NET=0" & echo   NET_FAIL - no direct internet on this machine) else (set "NET=1")

echo.
echo [4/5] Installing requirements ...
if exist "%WHEELS%\*.whl" (
  echo   mode: offline wheelhouse %WHEELS%
  "%UV%" pip install --python "%PY%" --no-index --find-links "%WHEELS%" -r "%REQ%"
  if errorlevel 1 goto :fail
  goto :verify
)
if "%NET%"=="0" goto :no_net

echo   mode: online mirrors
call :try_mirror "%M1%"
if errorlevel 1 call :try_mirror "%M2%"
if errorlevel 1 call :try_mirror "%M3%"
if errorlevel 1 goto :fail

:verify
echo.
echo [5/5] Verify ...
"%UV%" pip check --python "%PY%"
"%PY%" -c "import sys;print('  python',sys.version.split()[0],'ok')"
echo.
echo ============================================================
echo  DONE
echo ============================================================
pause
exit /b 0

:no_net
echo.
echo   No internet and no wheelhouse. Do this:
echo     1. On an ONLINE Windows PC with Python 3.12, copy F:\QuantBundle there
echo     2. Run:  QuantEnv_Fix.bat build
echo     3. Copy F:\QuantBundle\wheels back to this machine, run this script again
echo   Note: if this machine only reaches the internet through a WORKING proxy,
echo         set HTTP_PROXY/HTTPS_PROXY to it and edit this script to skip step 0.
goto :fail

:build
echo Building wheelhouse into %WHEELS% ...
where py >nul 2>nul
if errorlevel 1 (
  echo   [ERROR] 'py' launcher not found. Install Python 3.12 or run pip download manually.
  goto :fail
)
py -3.12 -c "import sys;assert sys.version_info[:2]==(3,12)" >nul 2>nul
if errorlevel 1 (
  echo   [ERROR] Python 3.12 not registered with the py launcher.
  goto :fail
)
if not exist "%WHEELS%" mkdir "%WHEELS%"
py -3.12 -m pip download -r "%REQ%" -d "%WHEELS%" --only-binary=:all: --platform win_amd64 --python-version 3.12 --implementation cp --abi cp312 -i %M1%
if errorlevel 1 (
  echo   [ERROR] download failed. If torch CUDA wheels are needed, add:
  echo     --extra-index-url https://download.pytorch.org/whl/cu128
  goto :fail
)
echo   done. Copy F:\QuantBundle\wheels to the offline machine.
pause
exit /b 0

:try_mirror
echo   trying %~1
"%UV%" pip install --python "%PY%" --index-url %~1 -r "%REQ%"
exit /b %errorlevel%

:fail
echo.
echo ============================================================
echo  FAILED - read the messages above
echo ============================================================
pause
exit /b 1
