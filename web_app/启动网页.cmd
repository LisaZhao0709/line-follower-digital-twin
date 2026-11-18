@echo off
chcp 65001 >nul
set PYTHONUTF8=1
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
    echo Python environment missing. See README.md for setup.
    pause
    exit /b 1
)
".venv\Scripts\python.exe" -B app.py --open-browser
pause
