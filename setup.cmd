@echo off
set AIHERE_PAUSE=1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
