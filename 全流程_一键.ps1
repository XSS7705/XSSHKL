# ============================================================
#  RVC FULL PIPELINE - ONE CLICK (install + train + convert)
#  ASCII ONLY. Put this file anywhere and double-click it.
# ============================================================
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

function Say($msg, $color = "White") { Write-Host $msg -ForegroundColor $color }

Say "================================================" Cyan
Say "  RVC FULL PIPELINE  (install + train + convert)" Cyan
Say "================================================" Cyan
Say ""

# ---------- 1. locate workdir ----------
$workdir = $null
$desktop = [Environment]::GetFolderPath("Desktop")
Get-ChildItem $desktop -Directory -Filter "RVC*" -ErrorAction SilentlyContinue | ForEach-Object { $workdir = $_.FullName }
if (-not $workdir) {
    Say "[ERROR] RVC folder not found on Desktop (expected a folder named starting with 'RVC')" Red
    Read-Host "Press Enter to exit"; exit 1
}
Say "[OK] Workdir: $workdir" Green
$appPy = Join-Path $workdir "Applio\app.py"
if (-not (Test-Path $appPy)) {
    Say "[ERROR] Missing: $appPy" Red
    Read-Host "Press Enter to exit"; exit 1
}

# ---------- 2. locate python 3.12 ----------
$py = $null
$candidates = @(
    "$env:LocalAppData\Programs\Python\Python312\python.exe",
    "$env:ProgramFiles\Python312\python.exe",
    "$env:LocalAppData\Programs\Python\Python313\python.exe",
    "$env:ProgramFiles\Python313\python.exe"
)
foreach ($c in $candidates) { if ((-not $py) -and (Test-Path $c)) { $py = $c } }
if (-not $py) {
    Say "[ERROR] Python 3.12 not found. Install it first." Red
    Read-Host "Press Enter to exit"; exit 1
}
Say "[OK] Python: $py" Green
& $py --version

# ---------- 3. venv ----------
$venvPy = Join-Path $workdir "env\Scripts\python.exe"
$needRebuild = $true
if (Test-Path $venvPy) {
    $v = & $venvPy --version 2>$null
    if ($v -match "3\.1[23]") { $needRebuild = $false }
}
if ($needRebuild) {
    Say "[..] Creating venv ..." Yellow
    Get-Process python, pythonw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (Test-Path (Join-Path $workdir "env")) {
        Remove-Item (Join-Path $workdir "env") -Recurse -Force -ErrorAction SilentlyContinue
    }
    & $py -m venv (Join-Path $workdir "env")
    if (-not (Test-Path $venvPy)) {
        Say "[ERROR] venv creation failed" Red
        Read-Host "Press Enter to exit"; exit 1
    }
}
Say "[OK] venv: $(& $venvPy --version)" Green

# ---------- 4. pip / torch / requirements ----------
Say "[..] Upgrading pip ..." Yellow
& $venvPy -m pip install --upgrade pip -q -i https://pypi.tuna.tsinghua.edu.cn/simple

& $venvPy -c "import torch" 2>$null
if ($LASTEXITCODE -ne 0) {
    Say "[..] Installing torch cu128 (3.4GB, 10-20 min) ..." Yellow
    & $venvPy -m pip install torch==2.8.0 torchaudio==2.8.0 --index-url https://download.pytorch.org/whl/cu128
    if ($LASTEXITCODE -ne 0) {
        Say "[ERROR] torch install failed. Copy the red text above." Red
        Read-Host "Press Enter to exit"; exit 1
    }
} else {
    Say "[OK] torch already installed" Green
}

& $venvPy -c "import gradio" 2>$null
if ($LASTEXITCODE -ne 0) {
    Say "[..] Installing ApplIO requirements (5-15 min) ..." Yellow
    & $venvPy -m pip install -r (Join-Path $workdir "Applio\requirements.txt") -i https://pypi.tuna.tsinghua.edu.cn/simple
    if ($LASTEXITCODE -ne 0) {
        Say "[ERROR] requirements install failed. Copy the red text above." Red
        Read-Host "Press Enter to exit"; exit 1
    }
} else {
    Say "[OK] requirements already installed" Green
}

Say ""
Say "[GPU] checking ..." Yellow
& $venvPy -c "import torch; print('  GPU:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else '!!! NO GPU !!!')"
Say ""

# ---------- 5. collect recordings ----------
Say "[1/4] Collecting recordings from: $workdir\recordings" Yellow
$recDir = Join-Path $workdir "recordings"
$ds = Join-Path $workdir "datasets\yelan_raw"
if (-not (Test-Path $recDir)) { New-Item -ItemType Directory -Path $recDir -Force | Out-Null }
if (-not (Test-Path $ds)) { New-Item -ItemType Directory -Path $ds -Force | Out-Null }

$found = 0
$audio = Get-ChildItem $recDir -File -Include *.aac,*.m4a,*.wav,*.mp3,*.ogg,*.flac -Recurse -ErrorAction SilentlyContinue
if (-not $audio) {
    Say ""
    Say "  No audio found in: $recDir" Yellow
    Say "  --> Copy your recording files into that folder, then run this file again." Yellow
    Say ""
    Start-Process explorer.exe $recDir
    Read-Host "Press Enter to exit"; exit 1
}
foreach ($f in $audio) {
    $outWav = Join-Path $ds ("rec_" + $found + ".wav")
    Say ("  converting: " + $f.Name) Gray
    ffmpeg -y -loglevel error -i $f.FullName -ac 1 -ar 44100 $outWav 2>$null
    if ($LASTEXITCODE -eq 0) { $found++ }
}
Say "[OK] $found wav files -> $ds" Green
Say ""

# ---------- 6. preprocess / extract / train / index ----------
$core = Join-Path $workdir "Applio\core.py"

Say "[2/4] Preprocess ..." Yellow
& $venvPy $core preprocess --model_name yelan --dataset_path $ds --sample_rate 40000 --cpu_cores 8 --cut_preprocess true --process_effects true
if ($LASTEXITCODE -ne 0) { goto Fail }

Say "[3/4] Extract features ..." Yellow
& $venvPy $core extract --model_name yelan --rvc_version v2 --f0method rmvpe --hop_length 128 --cpu_cores 8 --gpu 0 --sample_rate 40000 --embedder_model contentvec
if ($LASTEXITCODE -ne 0) { goto Fail }

Say "[4/4] Training 200 epochs (1.5-3 hours) ..." Yellow
& $venvPy $core train --model_name yelan --rvc_version v2 --save_every_epoch 20 --total_epoch 200 --sample_rate 40000 --batch_size 8 --gpu 0 --pitch_guidance true --save_only_latest false --save_every_weights true
if ($LASTEXITCODE -ne 0) { goto Fail }

Say "[+] Building index ..." Yellow
& $venvPy $core index --model_name yelan --rvc_version v2

$pth = Join-Path $workdir "Applio\logs\yelan\yelan.pth"
if (-not (Test-Path $pth)) { goto Fail }

Say ""
Say "================================================" Green
Say "  TRAIN DONE: $pth" Green
Say "================================================" Green
Say ""

# ---------- 7. auto convert if input exists ----------
$inDir = Join-Path $workdir "convert_in"
$outDir = Join-Path $workdir "convert_out"
if (-not (Test-Path $inDir)) { New-Item -ItemType Directory -Path $inDir -Force | Out-Null }
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$wavs = Get-ChildItem $inDir -Filter "*.wav" -ErrorAction SilentlyContinue
if (-not $wavs) {
    Say "No vocal wav in: $inDir" Yellow
    Say "Put the vocal wav there, then run this file again (training will be skipped)." Yellow
    Start-Process explorer.exe $inDir
    Read-Host "Press Enter to exit"; exit 0
}

$idx = Get-ChildItem (Split-Path $pth) -Filter "added_*.index" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
Say "[CONVERT] $($wavs.Count) file(s)" Yellow
$env:HF_ENDPOINT = "https://hf-mirror.com"
foreach ($w in $wavs) {
    $outWav = Join-Path $outDir ($w.BaseName + "_yelan.wav")
    Say ("  -> " + $w.Name) Gray
    $a = @($core, "infer", "--pitch", "0", "--input_path", $w.FullName, "--output_path", $outWav,
           "--pth_path", $pth, "--index_rate", "0.7", "--filter_radius", "3",
           "--rms_mix_rate", "0.25", "--protect", "0.33", "--f0method", "rmvpe", "--hop_length", "128")
    if ($idx) { $a += @("--index_path", $idx) }
    & $venvPy @a
}

Say ""
Say "================================================" Green
Say "  ALL DONE. Output: $outDir" Green
Say "================================================" Green
Start-Process explorer.exe $outDir
Read-Host "Press Enter to exit"
exit 0

Fail:
Say ""
Say "[WARN] Pipeline failed. Opening ApplIO web UI ..." Yellow
Say "Values for Train tab:" Yellow
Say "  name=yelan  sr=40000  version=v2  epochs=200  batch=8  save_every=20  f0=rmvpe" Yellow
$env:HF_ENDPOINT = "https://hf-mirror.com"
Start-Process "http://localhost:6969"
& $venvPy $appPy --port 6969
Read-Host "Press Enter to exit"
