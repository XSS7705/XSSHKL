#!/usr/bin/env python3
"""扫描本机常见的本地模型部署，生成 Markdown / CSV 清单。

用法:
    python3 model_inventory.py            # 打印并写入当前目录
    python3 model_inventory.py -o ./out   # 指定输出目录

支持: Ollama / LM Studio / HuggingFace 缓存 / GPT4All / Jan / llama.cpp 的 gguf 文件
"""
import argparse
import csv
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

HOME = Path.home()
MODEL_EXTS = {".gguf", ".safetensors", ".bin", ".mlmodel", ".onnx"}
SKIP_DIRS = {".git", "node_modules", "__pycache__", "blobs"}

# 常见本地模型目录（不存在会自动跳过）
CANDIDATE_DIRS = [
    HOME / ".ollama" / "models",
    HOME / ".cache" / "huggingface" / "hub",
    HOME / ".lmstudio" / "models",
    HOME / ".cache" / "lm-studio" / "models",
    HOME / "Library" / "Application Support" / "LM Studio" / "models",
    HOME / "Library" / "Application Support" / "Jan" / "models",
    HOME / ".local" / "share" / "nomic.ai" / "GPT4All",
    HOME / ".cache" / "gpt4all",
    HOME / "AppData" / "Local" / "nomic.ai" / "GPT4All",
    HOME / "AppData" / "Roaming" / "Jan" / "models",
    HOME / "models",
    HOME / ".cache" / "llama.cpp",
]


def human(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return f"{n:.1f} {unit}" if unit != "B" else f"{n} B"
        n /= 1024
    return f"{n:.1f} TB"


def ollama_models():
    """优先用 ollama CLI，失败则解析 manifests 目录。"""
    try:
        out = subprocess.run(
            ["ollama", "list"], capture_output=True, text=True, timeout=15
        )
        if out.returncode == 0 and out.stdout.strip():
            rows = []
            for line in out.stdout.splitlines()[1:]:
                parts = line.split()
                if len(parts) >= 3:
                    rows.append({
                        "名称": parts[0],
                        "运行时": "Ollama",
                        "位置": "ollama store",
                        "大小": " ".join(parts[2:4]) if len(parts) > 3 else parts[2],
                        "来源": "ollama list",
                    })
            if rows:
                return rows
    except (FileNotFoundError, subprocess.SubprocessError):
        pass

    # 回退：解析 manifests，统计对应 blob 大小
    rows = []
    manifests = HOME / ".ollama" / "models" / "manifests"
    if manifests.is_dir():
        for p in manifests.rglob("*"):
            if not p.is_file():
                continue
            rel = p.relative_to(manifests).parts
            if len(rel) < 4:
                continue
            name = f"{rel[-2]}:{rel[-1]}"
            rows.append({
                "名称": name,
                "运行时": "Ollama",
                "位置": str(p.parent),
                "大小": "-",
                "来源": "manifests",
            })
    return rows


def scan_files(base: Path):
    rows = []
    if not base.is_dir():
        return rows
    for root, dirs, files in os.walk(base):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for f in files:
            if Path(f).suffix.lower() not in MODEL_EXTS:
                continue
            fp = Path(root) / f
            try:
                size = fp.stat().st_size
            except OSError:
                continue
            if size < 5 * 1024 * 1024:  # 忽略 <5MB 的碎片
                continue
            rows.append({
                "名称": fp.stem,
                "运行时": base.name,
                "位置": str(fp.parent),
                "大小": human(size),
                "来源": str(fp),
            })
    return rows


def hf_models():
    rows = []
    hub = HOME / ".cache" / "huggingface" / "hub"
    if not hub.is_dir():
        return rows
    for d in sorted(hub.iterdir()):
        if not d.is_dir() or not d.name.startswith("models--"):
            continue
        size = 0
        for root, _, files in os.walk(d):
            for f in files:
                try:
                    size += (Path(root) / f).stat().st_size
                except OSError:
                    pass
        rows.append({
            "名称": d.name.replace("models--", "").replace("--", "/"),
            "运行时": "HuggingFace",
            "位置": str(d),
            "大小": human(size),
            "来源": str(d),
        })
    return rows


def merge(rows):
    seen, out = set(), []
    for r in rows:
        key = (r["名称"], r["位置"])
        if key in seen:
            continue
        seen.add(key)
        out.append(r)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--out", default=".")
    args = ap.parse_args()
    outdir = Path(args.out).expanduser().resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    rows = merge(
        ollama_models()
        + hf_models()
        + [r for d in CANDIDATE_DIRS for r in scan_files(d)]
    )

    cols = ["名称", "运行时", "位置", "大小", "来源"]
    md = [
        "# 本地模型清单",
        "",
        f"- 生成时间：{datetime.now():%Y-%m-%d %H:%M:%S}",
        f"- 主机：{os.uname().nodename if hasattr(os, 'uname') else os.getenv('COMPUTERNAME', '?')}",
        f"- 模型数量：{len(rows)}",
        "",
    ]
    if rows:
        md.append("| " + " | ".join(cols) + " |")
        md.append("|" + "|".join(["---"] * len(cols)) + "|")
        for r in rows:
            md.append("| " + " | ".join(str(r[c]).replace("|", "\\|") for c in cols) + " |")
    else:
        md.append("未检测到本地模型。")

    md_path = outdir / "本地模型清单.md"
    csv_path = outdir / "本地模型清单.csv"
    md_path.write_text("\n".join(md) + "\n", encoding="utf-8")
    with csv_path.open("w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)

    print("\n".join(md))
    print(f"\n已写入: {md_path}\n已写入: {csv_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
