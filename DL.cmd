@echo off
set PY="%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
if not exist %PY% set PY="%ProgramFiles%\Python312\python.exe"
%PY% "%~dp0dl_torch.py"
pause
