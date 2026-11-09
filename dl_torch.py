# Parallel downloader for torch cu128 wheels (16 connections)
# Usage: python dl_torch.py
# Put this file in Downloads, then double-click it OR run: python dl_torch.py
import os, sys, threading, urllib.request, urllib.parse, time

BASE = "https://mirrors.aliyun.com/pytorch-wheels/cu128/"
FILES = [
    "torch-2.8.0%2Bcu128-cp312-cp312-win_amd64.whl",
    "torchaudio-2.8.0%2Bcu128-cp312-cp312-win_amd64.whl",
]
THREADS = 16
OUTDIR = os.path.join(os.path.expanduser("~"), "Downloads")


def size_of(url):
    req = urllib.request.Request(url, method="HEAD")
    with urllib.request.urlopen(req, timeout=30) as r:
        return int(r.headers["Content-Length"])


def grab(url, start, end, path, total, lock, counter):
    req = urllib.request.Request(url, headers={"Range": "bytes=%d-%d" % (start, end)})
    with urllib.request.urlopen(req, timeout=120) as r, open(path, "wb") as f:
        while True:
            chunk = r.read(262144)
            if not chunk:
                break
            f.write(chunk)
            with lock:
                counter[0] += len(chunk)
                pct = counter[0] * 100.0 / total
                sys.stdout.write("\r  %.1f%%  %.1f MB / %.1f MB   " % (pct, counter[0] / 1048576.0, total / 1048576.0))
                sys.stdout.flush()


def download(name):
    url = BASE + name
    out = os.path.join(OUTDIR, urllib.parse.unquote(name))
    if os.path.exists(out) and os.path.getsize(out) > 100 * 1024 * 1024:
        print("[skip] already exists: " + out)
        return out
    print("[..] checking size: " + name)
    total = size_of(url)
    print("[..] %.1f MB, %d connections" % (total / 1048576.0, THREADS))
    step = total // THREADS
    parts = []
    lock = threading.Lock()
    counter = [0]
    threads = []
    for i in range(THREADS):
        start = i * step
        end = total - 1 if i == THREADS - 1 else (start + step - 1)
        p = out + ".part%d" % i
        parts.append(p)
        t = threading.Thread(target=grab, args=(url, start, end, p, total, lock, counter))
        t.start()
        threads.append(t)
    for t in threads:
        t.join()
    print("")
    with open(out, "wb") as fo:
        for p in parts:
            with open(p, "rb") as fi:
                while True:
                    c = fi.read(4 * 1048576)
                    if not c:
                        break
                    fo.write(c)
            os.remove(p)
    got = os.path.getsize(out)
    if got != total:
        print("[ERROR] size mismatch: %d != %d" % (got, total))
        return None
    print("[OK] " + out + "  (%.1f MB)" % (got / 1048576.0))
    return out


if __name__ == "__main__":
    if not os.path.isdir(OUTDIR):
        os.makedirs(OUTDIR)
    t0 = time.time()
    ok = []
    for f in FILES:
        r = download(f)
        if r:
            ok.append(r)
    print("")
    print("DONE in %.1f min" % ((time.time() - t0) / 60.0))
    print("")
    if len(ok) == len(FILES):
        desk = os.path.join(os.path.expanduser("~"), "Desktop")
        rvc = None
        if os.path.isdir(desk):
            for n in os.listdir(desk):
                if n.startswith("RVC") and os.path.isdir(os.path.join(desk, n)):
                    rvc = os.path.join(desk, n)
                    break
        vpy = os.path.join(rvc, "env", "Scripts", "python.exe") if rvc else "python.exe"
        print("Now paste this ONE line into PowerShell to install:")
        print("")
        print('& "%s" -m pip install "%s"' % (vpy, '" "'.join(ok)))
        print("")
        print("(If the line above is hard to copy, just double-click START.cmd instead -")
        print(" it will detect the downloaded wheels automatically.)")
    else:
        print("Some files failed. Run this script again to resume.")
    input("Press Enter to exit")
