@echo off
setlocal
cd /d "%~dp0"
title GitHub Push

set "GIT=C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\Git\cmd\git.exe"
if not exist "%GIT%" set "GIT=C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\Git\cmd\git.exe"
if not exist "%GIT%" set "GIT=git"

echo ========================================
echo  Push to GitHub
echo ========================================
echo Using git: %GIT%
echo.
set /p TOKEN=Paste your GitHub token, then press Enter: 
if "%TOKEN%"=="" goto :end

echo.
echo Pushing...
"%GIT%" -c http.sslBackend=openssl -c credential.helper= push "https://x-access-token:%TOKEN%@github.com/HDDD1123/game.git" main
if %ERRORLEVEL%==0 (
  echo.
  echo [OK] Pushed to GitHub successfully.
) else (
  echo.
  echo [FAILED] exit code %ERRORLEVEL%
)
:end
echo.
pause
