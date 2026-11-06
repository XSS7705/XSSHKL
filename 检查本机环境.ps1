# 夜阑 RVC 环境自检
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null

Write-Host "================================================" -ForegroundColor Cyan
Write-Host " 夜阑 RVC 环境自检" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

Write-Host "`n[1] 显卡 / 驱动" -ForegroundColor Yellow
Get-CimInstance Win32_VideoController | ForEach-Object {
    Write-Host ("  名称: " + $_.Name)
    Write-Host ("  驱动: " + $_.DriverVersion)
    if ($_.AdapterRAM -gt 0) { Write-Host ("  显存: " + [math]::Round($_.AdapterRAM/1GB,1) + " GB") }
}
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    Write-Host "`n  --- nvidia-smi ---"
    nvidia-smi --query-gpu=name,driver_version,memory.total,cuda_version --format=csv,noheader
} else {
    Write-Host "  [警告] 未找到 nvidia-smi（驱动可能没装好）" -ForegroundColor Red
}

Write-Host "`n[2] Python 版本" -ForegroundColor Yellow
if (Get-Command py -ErrorAction SilentlyContinue) {
    Write-Host "  已安装的 Python:"
    py -0p
    Write-Host "`n  默认 python:"
    python --version
} else {
    Write-Host "  [失败] 未找到 py 启动器（Python 没装或没加 PATH）" -ForegroundColor Red
}

Write-Host "`n[3] FFmpeg" -ForegroundColor Yellow
if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
    (ffmpeg -version | Select-Object -First 1)
} else {
    Write-Host "  [失败] 未找到 ffmpeg" -ForegroundColor Red
}

Write-Host "`n[4] 磁盘 / 内存" -ForegroundColor Yellow
Get-PSDrive C | ForEach-Object {
    Write-Host ("  C盘 剩余: " + [math]::Round($_.Free/1GB,1) + " GB")
}
$ram = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
Write-Host ("  物理内存: " + [math]::Round($ram/1GB,1) + " GB")

Write-Host "`n[5] ApplIO 目录" -ForegroundColor Yellow
$p = "C:\Users\Administrator\Desktop\RVC夜阑"
if (Test-Path $p) {
    Write-Host "  目录存在: $p"
    if (Test-Path "$p\Applio\app.py") { Write-Host "  Applio\app.py: OK" -ForegroundColor Green }
    else { Write-Host "  Applio\app.py: 缺失（需要 git clone）" -ForegroundColor Red }
    if (Test-Path "$p\env\Scripts\python.exe") { Write-Host "  env 虚拟环境: 存在" -ForegroundColor Green }
    else { Write-Host "  env 虚拟环境: 不存在（首次启动会自动建）" -ForegroundColor Yellow }
} else {
    Write-Host "  [失败] 目录不存在: $p" -ForegroundColor Red
}

Write-Host "`n[6] Git" -ForegroundColor Yellow
if (Get-Command git -ErrorAction SilentlyContinue) { git --version }
else { Write-Host "  [失败] 未安装 git" -ForegroundColor Red }

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host " 自检结束，请把以上全部内容复制发给助手" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Read-Host "`n按回车退出"
