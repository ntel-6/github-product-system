@echo off
setlocal

set "GH_EXE=gh"
where gh >nul 2>&1
if errorlevel 1 set "GH_EXE=%USERPROFILE%\AI_Library\tools\bin\gh.cmd"

if not "%GH_EXE%"=="gh" if not exist "%GH_EXE%" (
  echo GitHub CLI was not found at:
  echo %GH_EXE%
  echo Run scripts\install-tooling.ps1 first.
  pause
  exit /b 2
)

echo Connecting GitHub CLI through the official browser OAuth flow...
echo Use the ntel-6 account. Do not paste passwords or tokens into this window.
echo.

"%GH_EXE%" auth login --hostname github.com --git-protocol https --web
if errorlevel 1 (
  echo.
  echo GitHub login did not complete.
  pause
  exit /b 1
)

"%GH_EXE%" auth setup-git
if errorlevel 1 (
  echo.
  echo Git credential setup failed.
  pause
  exit /b 1
)

"%GH_EXE%" auth status --active --hostname github.com
echo.
echo GitHub CLI connection completed. You can close this window.
pause
