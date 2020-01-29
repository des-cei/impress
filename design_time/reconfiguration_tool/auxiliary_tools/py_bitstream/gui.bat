@echo off
cd %~dp0
portable_python\App\python.exe %~dpn0.py %*
