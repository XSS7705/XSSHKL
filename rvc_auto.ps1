# ================================================================
#  RVC FULL AUTO - ONE CLICK
#  Does: install -> train -> convert -> mix -> final mp3
#  ASCII ONLY. Double-click this file. No manual steps.
# ================================================================
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

function Say($m, $c = "White") { Write-Host $m -ForegroundColor $c }
function Head($m) { Say ""; Say "================================================" Cyan; Say "  $m" Cyan; Say "================================================" Cyan }

Head "RVC FULL AUTO  (install / train / convert / mix)"

# ---------- 0. paths ----------
$desk    = [Environment]::GetFolderPath("Desktop")
$dl      = Join-Path $env:USERPROFILE "Downloads"
$music   = [Environment]::GetFolderPath("MyMusic")
$docs    = [Environment]::GetFolderPath("MyDocuments")
$searchDirs = @($dl, $desk, $music, $docs) | Where-Object { Test-Path $_ }

$workdir = $null
Get-ChildItem $desk -Directory -Filter "RVC*" -ErrorAction SilentlyContinue | ForEach-Object { $workdir = $_.FullName }
if (-not $workdir) {
    Say "[ERROR] No folder starting with 'RVC' on Desktop." Red
    Read-Host "Press Enter to exit"; exit 1
}
$appDir = Join-Path $workdir "Applio"
$core   = Join-Path $appDir "core.py"
if (-not (Test-Path $core)) {
    Say "[ERROR] Missing: $core" Red
    Read-Host "Press Enter to exit"; exit 1
}
Say "[OK] Workdir: $workdir" Green

$dirRec   = Join-Path $workdir "recordings"
$dirRaw   = Join-Path $workdir "datasets\yelan_raw"
$dirIn    = Join-Path $workdir "convert_in"
$dirOut   = Join-Path $workdir "convert_out"
$dirFinal = Join-Path $workdir "final"
foreach ($d in @($dirRec, $dirRaw, $dirIn, $dirOut, $dirFinal)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

# ---------- 1. find python ----------
$py = $null
foreach ($c in @("$env:LocalAppData\Programs\Python\Python312\python.exe",
                 "$env:ProgramFiles\Python312\python.exe",
                 "$env:LocalAppData\Programs\Python\Python313\python.exe",
                 "$env:ProgramFiles\Python313\python.exe")) {
    if ((-not $py) -and (Test-Path $c)) { $py = $c }
}
if (-not $py) { Say "[ERROR] Python 3.12 not found." Red; Read-Host "Enter to exit"; exit 1 }
Say "[OK] Python: $py" Green

# ---------- 2. find INPUTS automatically ----------
# vocal_input.wav  -> the AI vocal to be replaced
# instrumental.wav -> the backing track
# everything else that is audio and not these two -> training data
Say "[..] Scanning for audio files in Downloads / Desktop / Music / Documents ..." Yellow

$allAudio = @()
foreach ($d in $searchDirs) {
    $allAudio += Get-ChildItem $d -File -Recurse -ErrorAction SilentlyContinue -Include *.aac,*.m4a,*.wav,*.mp3,*.flac,*.ogg |
                 Where-Object { $_.FullName -notlike "$workdir*" -and $_.Length -gt 200KB }
}

$vocalIn = $allAudio | Where-Object { $_.Name -match "^vocal_input" } | Select-Object -First 1
$instrIn = $allAudio | Where-Object { $_.Name -match "^instrumental" } | Select-Object -First 1

# --- training data: prefer phone recordings (.aac/.m4a), never the AI song mp3 ---
$cand = $allAudio | Where-Object { $_.Name -notmatch "^(vocal_input|instrumental)" }
$recs = $cand | Where-Object { $_.Extension -match "^\.(aac|m4a)$" }
if (-not $recs) { $recs = $cand | Where-Object { $_.Extension -eq ".wav" } }
if (-not $recs) { $recs = $cand | Where-Object { $_.Extension -match "^\.(flac|mp3)$" } }
$trainSrcs = @($recs | Sort-Object Length -Descending | Select-Object -First 10)

if (-not $trainSrcs -or $trainSrcs.Count -eq 0) {
    Say "[ERROR] No voice recording found. Put your own recording (aac/m4a/wav) in Downloads." Red
    Start-Process explorer.exe $dl
    Read-Host "Press Enter to exit"; exit 1
}
Say "[OK] Training voices ($($trainSrcs.Count) file(s)):" Green
foreach ($t in $trainSrcs) { Say ("     - " + $t.Name + "  (" + [math]::Round($t.Length/1MB,1) + " MB)") Gray }
if ($vocalIn) { Say "[OK] AI vocal       : $($vocalIn.Name)" Green } else { Say "[WARN] vocal_input.wav not found - will skip conversion" Yellow }
if ($instrIn) { Say "[OK] Instrumental   : $($instrIn.Name)" Green } else { Say "[WARN] instrumental.wav not found - final mix will be vocal only" Yellow }
Say ""

# ---------- 3. prepare training wav ----------
$ff = "ffmpeg"
& $ff -version 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    $lib = Join-Path $appDir "ffmpeg.exe"
    if (Test-Path $lib) { $ff = $lib } else { Say "[ERROR] ffmpeg not found." Red; Read-Host "Enter to exit"; exit 1 }
}
Say "[1/6] Preparing training data ..." Yellow
Get-ChildItem $dirRaw -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
$n = 0
foreach ($t in $trainSrcs) {
    $n++
    $dst = Join-Path $dirRaw ("voice_" + $n.ToString("00") + ".wav")
    Say ("  converting: " + $t.Name) Gray
    & $ff -y -loglevel error -i $t.FullName -ac 1 -ar 44100 $dst 2>$null
}
$made = @(Get-ChildItem $dirRaw -Filter "*.wav" -ErrorAction SilentlyContinue).Count
if ($made -eq 0) { Say "[ERROR] ffmpeg convert failed." Red; Read-Host "Enter to exit"; exit 1 }
Say "[OK] $made training wav(s) ready" Green

# ---------- 4. env install ----------
$venvPy = Join-Path $workdir "env\Scripts\python.exe"
$rebuild = $true
if (Test-Path $venvPy) {
    $v = & $venvPy --version 2>$null
    if ($v -match "3\.1[23]") { $rebuild = $false }
}
if ($rebuild) {
    Say "[2/6] Creating venv ..." Yellow
    Get-Process python, pythonw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep 2
    Remove-Item (Join-Path $workdir "env") -Recurse -Force -ErrorAction SilentlyContinue
    & $py -m venv (Join-Path $workdir "env")
    if (-not (Test-Path $venvPy)) { Say "[ERROR] venv failed." Red; Read-Host "Enter to exit"; exit 1 }
}
Say "[OK] venv: $(& $venvPy --version)" Green

& $venvPy -m pip install --upgrade pip -q -i https://pypi.tuna.tsinghua.edu.cn/simple 2>$null

& $venvPy -c "import torch" 2>$null
if ($LASTEXITCODE -ne 0) {
    $whTorch = Get-ChildItem $dl -Filter "torch-*cu128*cp312*win_amd64.whl" -ErrorAction SilentlyContinue | Select-Object -First 1
    $whAudio = Get-ChildItem $dl -Filter "torchaudio-*cu128*cp312*win_amd64.whl" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($whTorch -and $whAudio) {
        Say "[3/6] Installing torch from downloaded wheels (offline) ..." Yellow
        & $venvPy -m pip install $whTorch.FullName $whAudio.FullName -i https://pypi.tuna.tsinghua.edu.cn/simple
    } else {
        Say "[3/6] Installing torch cu128 (3.5GB, ~6 min on Aliyun mirror) ..." Yellow
        & $venvPy -m pip install "torch==2.8.0+cu128" "torchaudio==2.8.0+cu128" --find-links https://mirrors.aliyun.com/pytorch-wheels/cu128 -i https://pypi.tuna.tsinghua.edu.cn/simple
    }
    if ($LASTEXITCODE -ne 0) {
        Say "[WARN] Mirror failed, trying official source (slow) ..." Yellow
        & $venvPy -m pip install "torch==2.8.0" "torchaudio==2.8.0" --index-url https://download.pytorch.org/whl/cu128
    }
    if ($LASTEXITCODE -ne 0) { Say "[ERROR] torch install failed - send the red text above." Red; Read-Host "Enter to exit"; exit 1 }
} else { Say "[3/6] torch already present" Green }

& $venvPy -c "import gradio" 2>$null
if ($LASTEXITCODE -ne 0) {
    Say "[3/6] Installing ApplIO requirements (5-15 min) ..." Yellow
    & $venvPy -m pip install -r (Join-Path $appDir "requirements.txt") -i https://pypi.tuna.tsinghua.edu.cn/simple
    if ($LASTEXITCODE -ne 0) { Say "[ERROR] requirements failed - send the red text above." Red; Read-Host "Enter to exit"; exit 1 }
} else { Say "[3/6] requirements already present" Green }

Say ""; & $venvPy -c "import torch; print('  GPU:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else '!!! NO GPU !!!')"; Say ""

# ---------- 5. train (skipped if the model already exists) ----------
$pth = Join-Path $appDir "logs\yelan\yelan.pth"
if (Test-Path $pth) {
    Say "[5/6] Model already exists - skipping training" Green
} else {
Say "[4/6] Preprocess ..." Yellow
& $venvPy $core preprocess --model-name yelan --dataset-path $dirRaw --sample-rate 40000 --cpu-cores 8 --cut-preprocess true --process-effects true
if ($LASTEXITCODE -ne 0) { Say "[ERROR] preprocess failed." Red; Read-Host "Enter to exit"; exit 1 }

Say "[4/6] Extract features ..." Yellow
& $venvPy $core extract --model-name yelan --rvc-version v2 --f0method rmvpe --hop-length 128 --cpu-cores 8 --gpu 0 --sample-rate 40000 --embedder-model contentvec
if ($LASTEXITCODE -ne 0) { Say "[ERROR] extract failed." Red; Read-Host "Enter to exit"; exit 1 }

Say "[5/6] Training 200 epochs (1.5-3 hours). You can leave ..." Yellow
& $venvPy $core train --model-name yelan --rvc-version v2 --save-every-epoch 20 --total-epoch 200 --sample-rate 40000 --batch-size 8 --gpu 0 --pitch-guidance true --save-every-weights true
if ($LASTEXITCODE -ne 0) { Say "[ERROR] train failed." Red; Read-Host "Enter to exit"; exit 1 }

& $venvPy $core index --model-name yelan --rvc-version v2
if (-not (Test-Path $pth)) { Say "[ERROR] Model not produced: $pth" Red; Read-Host "Enter to exit"; exit 1 }
}
Say "[OK] Model: $pth" Green

# ---------- 6. convert + mix ----------
if (-not $vocalIn) {
    Say ""
    Say "Training finished. Download vocal_input.wav into Downloads, then run this file again to convert." Yellow
    Read-Host "Press Enter to exit"; exit 0
}

Say "[6/6] Converting AI vocal to your voice ..." Yellow
$aiVocalWav = Join-Path $dirIn "ai_vocal.wav"
& $ff -y -loglevel error -i $vocalIn.FullName -ac 1 -ar 40000 $aiVocalWav
$outVocal = Join-Path $dirOut "converted_vocal.wav"
$idx = Get-ChildItem (Split-Path $pth) -Filter "added_*.index" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
$env:HF_ENDPOINT = "https://hf-mirror.com"
$a = @($core, "infer", "--pitch", "0", "--input-path", $aiVocalWav, "--output-path", $outVocal,
       "--pth-path", $pth, "--index-rate", "0.7", "--filter-radius", "3",
       "--rms-mix-rate", "0.25", "--protect", "0.33", "--f0method", "rmvpe", "--hop-length", "128")
if ($idx) { $a += @("--index-path", $idx) }
& $venvPy @a
if (-not (Test-Path $outVocal)) { Say "[ERROR] inference failed - send the red text above." Red; Read-Host "Enter to exit"; exit 1 }

# mix
$finalMp3 = Join-Path $dirFinal "final_yelan.mp3"
Say "[MIX] Building final track ..." Yellow
if ($instrIn) {
    & $ff -y -loglevel error -i $outVocal -i $instrIn.FullName -filter_complex "[1:a]volume=1.0[bg];[0:a]volume=1.0[v];[v][bg]amix=inputs=2:duration=longest:normalize=0,alimiter=limit=0.97,loudnorm=I=-14:TP=-1.5:LRA=11" -ar 44100 -b:a 320k $finalMp3
} else {
    & $ff -y -loglevel error -i $outVocal -filter_complex "alimiter=limit=0.97,loudnorm=I=-14:TP=-1.5:LRA=11" -ar 44100 -b:a 320k $finalMp3
}

Head "ALL DONE"
if (Test-Path $finalMp3) {
    Say "  Final track : $finalMp3" Green
    Say "  Your vocal  : $outVocal" Green
    Start-Process explorer.exe $dirFinal
} else {
    Say "  Vocal done but mix failed. Files in: $dirOut" Yellow
    Start-Process explorer.exe $dirOut
}
Read-Host "Press Enter to exit"
