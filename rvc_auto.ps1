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

# ---------- 4.5 fix module path + HF mirror ----------
$env:HF_ENDPOINT = "https://hf-mirror.com"
$env:PYTHONPATH = $appDir
Set-Location $appDir

$sc = Join-Path $workdir "env\Lib\site-packages\sitecustomize.py"
@'
import os, sys
os.environ.setdefault("HF_ENDPOINT", "https://hf-mirror.com")
try:
    import requests
    _orig_req = requests.Session.request
    def _patched(self, method, url, *a, **kw):
        if isinstance(url, str) and "huggingface.co" in url:
            url = url.replace("huggingface.co", "hf-mirror.com")
        return _orig_req(self, method, url, *a, **kw)
    requests.Session.request = _patched
except Exception:
    pass
try:
    import huggingface_hub.constants as _c
    if hasattr(_c, "ENDPOINT"):
        _c.ENDPOINT = "https://hf-mirror.com"
except Exception:
    pass
'@ | Set-Content -Path $sc -Encoding ASCII
Say "[OK] HF mirror + module path configured" Green

# ---------- 4.6 fetch required model assets (parallel) ----------
$dlm = Join-Path $workdir "dlm.py"
@'
import sys, os, time, threading, urllib.request, urllib.error

url, out, n = sys.argv[1], sys.argv[2], int(sys.argv[3])

def _open(req, tries=6):
    last = None
    for i in range(tries):
        try:
            return urllib.request.urlopen(req, timeout=180)
        except urllib.error.HTTPError as e:
            last = e
            if e.code in (429, 500, 502, 503, 504) and i < tries - 1:
                time.sleep(3 * (i + 1))
                continue
            raise
        except Exception as e:
            last = e
            if i < tries - 1:
                time.sleep(3 * (i + 1))
                continue
            raise
    raise last

def head(u):
    r = _open(urllib.request.Request(u, method="HEAD"))
    return int(r.headers.get("Content-Length") or 0)

def stream(u, o):
    r = _open(u)
    with open(o, "wb") as f:
        while True:
            c = r.read(1 << 20)
            if not c:
                break
            f.write(c)

def part(u, a, b, o):
    req = urllib.request.Request(u, headers={"Range": "bytes=%d-%d" % (a, b)})
    r = _open(req)
    if getattr(r, "status", 200) != 206:
        raise RuntimeError("no-range")
    with open(o, "wb") as f:
        while True:
            c = r.read(1 << 20)
            if not c:
                break
            f.write(c)

total = head(url)
if total <= 0 or total < 4 * 1024 * 1024:
    stream(url, out)
    sys.exit(0)

step = total // n
parts, ts = [], []
ok = True
try:
    for i in range(n):
        a = i * step
        b = total - 1 if i == n - 1 else a + step - 1
        p = "%s.p%d" % (out, i)
        parts.append(p)
        t = threading.Thread(target=part, args=(url, a, b, p))
        t.start()
        ts.append(t)
    for t in ts:
        t.join()
    if sum(os.path.getsize(p) for p in parts) != total:
        ok = False
    else:
        with open(out, "wb") as fo:
            for p in parts:
                with open(p, "rb") as fi:
                    while True:
                        c = fi.read(1 << 22)
                        if not c:
                            break
                        fo.write(c)
finally:
    for p in parts:
        try:
            os.remove(p)
        except Exception:
            pass
if not ok:
    stream(url, out)

got = os.path.getsize(out) if os.path.exists(out) else 0
if total > 0 and got != total:
    print("[ERROR] size mismatch %d != %d" % (got, total))
    sys.exit(2)
'@ | Set-Content -Path $dlm -Encoding ASCII

$base = "https://hf-mirror.com/IAHispano/Applio/resolve/main/Resources"
$assets = @(
    @{ u = "$base/predictors/rmvpe.pt";                    d = "rvc\models\predictors\rmvpe.pt" },
    @{ u = "$base/embedders/contentvec/pytorch_model.bin"; d = "rvc\models\embedders\contentvec\pytorch_model.bin" },
    @{ u = "$base/embedders/contentvec/config.json";       d = "rvc\models\embedders\contentvec\config.json" }
)
foreach ($as in $assets) {
    $out = Join-Path $appDir $as.d
    $parent = Split-Path $out
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    if ((Test-Path $out) -and ((Get-Item $out).Length -gt 100KB)) { continue }
    if (Test-Path $out) { Remove-Item $out -Force -ErrorAction SilentlyContinue }
    Say ("  downloading: " + (Split-Path $out -Leaf)) Gray
    & $venvPy $dlm $as.u $out 8
    if (-not (Test-Path $out) -or ((Get-Item $out).Length -lt 100KB)) {
        Say ("[ERROR] failed to fetch " + $as.d) Red
        Read-Host "Enter to exit"; exit 1
    }
}
Say "[OK] pitch + embedder models ready" Green

# ---------- 5. train (skipped if the model already exists) ----------
$logsDir = Join-Path $appDir "logs\yelan"
$weightsDir = Join-Path $appDir "assets\weights"

function Get-BestPth {
    $cand = @()
    if (Test-Path $logsDir) { $cand += Get-ChildItem $logsDir -Filter "*.pth" -Recurse -ErrorAction SilentlyContinue }
    if (Test-Path $weightsDir) { $cand += Get-ChildItem $weightsDir -Filter "*.pth" -Recurse -ErrorAction SilentlyContinue }
    $cand = @($cand | Where-Object { $_.Name -notmatch '^(G_|D_)' })
    if ($cand.Count -eq 0) { return $null }
    return ($cand | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

$pth = Get-BestPth
if ($pth) {
    Say "[5/6] Model already exists - skipping training" Green
} else {
Say "[4/6] Preprocess ..." Yellow
& $venvPy $core preprocess --model-name yelan --dataset-path $dirRaw --sample-rate 40000 --cpu-cores 8 --cut-preprocess Automatic
if ($LASTEXITCODE -ne 0) { Say "[ERROR] preprocess failed." Red; Read-Host "Enter to exit"; exit 1 }

Say "[4/6] Extract features ..." Yellow
& $venvPy $core extract --model-name yelan --f0-method rmvpe --cpu-cores 8 --gpu 0 --sample-rate 40000 --embedder-model contentvec
if ($LASTEXITCODE -ne 0) { Say "[ERROR] extract failed." Red; Read-Host "Enter to exit"; exit 1 }

Say "[5/6] Training 200 epochs (1.5-3 hours). You can leave ..." Yellow
& $venvPy $core train --model-name yelan --save-every-epoch 20 --total-epoch 200 --sample-rate 40000 --batch-size 8 --gpu 0 --pretrained --save-every-weights
if ($LASTEXITCODE -ne 0) { Say "[ERROR] train failed." Red; Read-Host "Enter to exit"; exit 1 }

Say "[5/6] Building index ..." Yellow
& $venvPy $core index --model-name yelan --index-algorithm Auto

$pth = Get-BestPth
if (-not $pth) { Say "[ERROR] Model not produced under logs\yelan or assets\weights." Red; Read-Host "Enter to exit"; exit 1 }
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
$idx = Get-ChildItem (Split-Path $pth) -Filter "*.index" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
if (-not $idx -and (Test-Path $logsDir)) {
    $idx = Get-ChildItem $logsDir -Filter "*.index" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $idx) {
    Say "[6/6] Index missing - rebuilding ..." Yellow
    & $venvPy $core index --model-name yelan --index-algorithm Auto
    if (Test-Path $logsDir) { $idx = Get-ChildItem $logsDir -Filter "*.index" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName }
}
if (-not $idx) { Say "[ERROR] No .index file found - cannot run inference." Red; Read-Host "Enter to exit"; exit 1 }

$env:HF_ENDPOINT = "https://hf-mirror.com"
$a = @($core, "infer", "--input-path", $aiVocalWav, "--output-path", $outVocal,
       "--pth-path", $pth, "--index-path", $idx,
       "--pitch", "0", "--index-rate", "0.7", "--volume-envelope", "0.25",
       "--protect", "0.33", "--f0-method", "rmvpe", "--export-format", "WAV")
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
