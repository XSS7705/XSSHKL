@echo off
setlocal enabledelayedexpansion
title RVC Train - yelan
echo ================================================
echo   RVC Auto-Train: yelan (200 epochs)
echo ================================================
echo.

rem ==== find workdir ====
set "WORKDIR="
for /d %%D in ("%USERPROFILE%\Desktop\RVC*") do set "WORKDIR=%%D"
if not defined WORKDIR ( echo [ERROR] RVC folder not found on Desktop & pause & exit /b 1 )
set "VENV_PY=%WORKDIR%\env\Scripts\python.exe"
if not exist "%VENV_PY%" (
    echo [ERROR] venv missing. Run the setup bat first.
    pause
    exit /b 1
)
echo Workdir: %WORKDIR%

rem ==== 1. collect recordings ====
echo.
echo [1/5] Collecting voice recordings ...
set "DS=%WORKDIR%\datasets\yelan_raw"
if not exist "%DS%" mkdir "%DS%"
set /a FOUND=0
for %%D in ("%USERPROFILE%\Desktop" "%USERPROFILE%\Downloads" "%USERPROFILE%\Documents" "%USERPROFILE%\Music" "%USERPROFILE%\Videos" "%WORKDIR%\recordings") do (
    if exist %%D (
        for %%E in (aac m4a wav mp3 ogg flac) do (
            for %%F in ("%%~D\*光*.%%E" "%%~D\*2026*.%%E" "%%~D\*yelan*.%%E" "%%~D\*夜阑*.%%E") do (
                if exist %%F (
                    echo   found: %%F
                    ffmpeg -y -loglevel error -i "%%F" -ac 1 -ar 44100 "%DS%\rec_!FOUND!.wav"
                    if not errorlevel 1 set /a FOUND+=1
                )
            )
        )
    )
)
if !FOUND!==0 (
    echo.
    echo [ERROR] No recordings found.
    echo Put your aac/wav recordings into: %WORKDIR%\recordings
    echo then run this bat again.
    pause
    exit /b 1
)
echo   total: !FOUND! files -^> %DS%

rem ==== 2. preprocess ====
echo.
echo [2/5] Preprocess dataset ...
"%VENV_PY%" "%WORKDIR%\Applio\core.py" preprocess --model_name yelan --dataset_path "%DS%" --sample_rate 40000 --cpu_cores 8 --cut_preprocess true --process_effects true
if errorlevel 1 goto CLI_FAIL

rem ==== 3. extract f0 + embed ====
echo.
echo [3/5] Extract features (rmvpe + contentvec) ...
"%VENV_PY%" "%WORKDIR%\Applio\core.py" extract --model_name yelan --rvc_version v2 --f0method rmvpe --hop_length 128 --cpu_cores 8 --gpu 0 --sample_rate 40000 --embedder_model contentvec
if errorlevel 1 goto CLI_FAIL

rem ==== 4. train ====
echo.
echo [4/5] Training 200 epochs (1.5-3 hours on 5060 Ti) ...
"%VENV_PY%" "%WORKDIR%\Applio\core.py" train --model_name yelan --rvc_version v2 --save_every_epoch 20 --total_epoch 200 --sample_rate 40000 --batch_size 8 --gpu 0 --pitch_guidance true --save_only_latest false --save_every_weights true
if errorlevel 1 goto CLI_FAIL

rem ==== 5. index ====
echo.
echo [5/5] Building index ...
"%VENV_PY%" "%WORKDIR%\Applio\core.py" index --model_name yelan --rvc_version v2
if errorlevel 1 goto CLI_FAIL

echo.
echo ================================================
echo   TRAIN DONE. Model: %WORKDIR%\Applio\logs\yelan\yelan.pth
echo ================================================
pause
exit /b 0

:CLI_FAIL
echo.
echo [WARN] CLI mode failed. Opening web UI instead.
echo Copy the red text above and send to assistant.
echo Use these values in the Train tab:
echo   Model name: yelan   Sample rate: 40000   Version: v2
echo   Epochs: 200   Batch: 8   Save every: 20   f0: rmvpe
set HF_ENDPOINT=https://hf-mirror.com
start "" http://localhost:6969
"%VENV_PY%" "%WORKDIR%\Applio\app.py" --port 6969
pause
