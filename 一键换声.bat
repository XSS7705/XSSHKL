@echo off
setlocal enabledelayedexpansion
title RVC Batch Voice Convert - yelan
echo ================================================
echo   Batch voice convert with trained yelan model
echo ================================================
echo.

rem ==== find workdir ====
set "WORKDIR="
for /d %%D in ("%USERPROFILE%\Desktop\RVC*") do set "WORKDIR=%%D"
if not defined WORKDIR ( echo [ERROR] RVC folder not found on Desktop & pause & exit /b 1 )
set "VENV_PY=%WORKDIR%\env\Scripts\python.exe"
if not exist "%VENV_PY%" ( echo [ERROR] venv missing. Run setup first. & pause & exit /b 1 )

rem ==== locate model + index ====
set "PTH=%WORKDIR%\Applio\logs\yelan\yelan.pth"
if not exist "%PTH%" (
    echo [ERROR] Model not found: %PTH%
    echo Train first (run 一键训练.bat).
    pause
    exit /b 1
)
set "IDX="
for %%I in ("%WORKDIR%\Applio\logs\yelan\added_*.index") do set "IDX=%%I"
if not defined IDX echo [WARN] no index file, continuing without it

rem ==== input/output folders ====
set "IN=%WORKDIR%\convert_in"
set "OUT=%WORKDIR%\convert_out"
if not exist "%IN%" mkdir "%IN%"
if not exist "%OUT%" mkdir "%OUT%"

echo   model : %PTH%
echo   index : %IDX%
echo   input : %IN%   ^<-- put vocal wavs here
echo   output: %OUT%
echo.

dir /b "%IN%\*.wav" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] No wav files in %IN%
    echo Put the vocal wav files in that folder, then run again.
    pause
    exit /b 1
)

set HF_ENDPOINT=https://hf-mirror.com
for %%F in ("%IN%\*.wav") do (
    echo Converting: %%~nxF
    if defined IDX (
        "%VENV_PY%" "%WORKDIR%\Applio\core.py" infer --pitch 0 --input_path "%%F" --output_path "%OUT%\%%~nF_yelan.wav" --pth_path "%PTH%" --index_path "%IDX%" --index_rate 0.7 --filter_radius 3 --rms_mix_rate 0.25 --protect 0.33 --f0method rmvpe --hop_length 128
    ) else (
        "%VENV_PY%" "%WORKDIR%\Applio\core.py" infer --pitch 0 --input_path "%%F" --output_path "%OUT%\%%~nF_yelan.wav" --pth_path "%PTH%" --index_rate 0.7 --filter_radius 3 --rms_mix_rate 0.25 --protect 0.33 --f0method rmvpe --hop_length 128
    )
    if errorlevel 1 (
        echo [WARN] CLI failed on this file. Send the red text to assistant.
    )
)

echo.
echo ================================================
echo   DONE. Converted files in: %OUT%
echo ================================================
pause
