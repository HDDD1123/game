@echo off
chcp 65001 >nul
cd /d "%~dp0"
title 推送代码到 GitHub
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0推送.ps1"
