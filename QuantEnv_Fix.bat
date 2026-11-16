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
set "ISET=HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
set "PROXYFIX=0"

echo ============================================================
echo  QuantEnv Fix    target = %TARGET%
echo ============================================================
echo.
echo [0/5] Cleaning proxy environment variables ...
set | findstr /i "proxy" || echo   none
for %%v in (HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy) do set "%%v="
set "NO_PROXY=*"
set "no_proxy=*"

if /i "%~1"=="build" goto :build

echo.
echo [1/5] Checking files ...
if not exist "%UV%"  (echo   [ERROR] missing %UV% & goto :fail)
if not exist "%PY%"  (echo   [ERROR] missing %PY% & goto :fail)
if not exist "%REQ%" (echo   [ERROR] missing %REQ% & goto :fail)
echo   ok

echo.
echo [2/5] Direct connectivity test (proxy bypassed) ...
"%PY%" -c "import urllib.request as u;u.build_opener(u.ProxyHandler({})).open('https://pypi.tuna.tsinghua.edu.cn/simple/',timeout=10);print('NET_OK')" 2>nul
if errorlevel 1 (set "NET=0" & echo   NET_FAIL - no direct internet on this machine) else (set "NET=1")

echo.
echo [3/5] Windows system proxy (registry, read by uv/reqwest) ...
if "%NET%"=="0" (
  echo   skipped - no direct internet, existing proxy settings kept
  goto :after_sysproxy
)
set "SYS=0"
for /f "tokens=3" %%a in ('reg query "%ISET%" /v ProxyEnable 2^>nul ^| findstr /i "ProxyEnable"') do set "SYS=%%a"
if /i not "%SYS%"=="0x1" (
  echo   off
  goto :after_sysproxy
)
set "SYSSRV="
for /f "tokens=3*" %%a in ('reg query "%ISET%" /v ProxyServer 2^>nul ^| findstr /i "ProxyServer"') do set "SYSSRV=%%a %%b"
reg add "%ISET%" /v ProxyEnable /t REG_DWORD /d 0 /f >nul
set "PROXYFIX=1"
echo   was ON  %SYSSRV%
echo   now OFF  -^> dead proxy no longer breaks uv (os error 10061 / tunnel error)
:after_sysproxy

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
if "%PROXYFIX%"=="1" echo  NOTE: system proxy was switched OFF. Re-enable it in Settings if you start that proxy app again.
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
echo         start that proxy app first, then run this script again.
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
