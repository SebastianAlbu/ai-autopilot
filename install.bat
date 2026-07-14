@echo off
setlocal EnableExtensions

rem ===========================================================================
rem  install.bat  (Windows)
rem  Install the agents + skills GLOBALLY for every AI tool on this machine
rem  (Claude Code, VS Code Copilot, Copilot CLI) and download the caveman skills.
rem  The real work is done by Install-AiAutopilot.ps1 (PowerShell).
rem
rem  Usage:
rem    install.bat               Install for all tools (incl. caveman)
rem    install.bat -NoCaveman    Skip the caveman download
rem ===========================================================================

set "PS=powershell"
where pwsh >nul 2>nul && set "PS=pwsh"

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-AiAutopilot.ps1" %*
set "RC=%ERRORLEVEL%"

if "%~1"=="" pause
endlocal & exit /b %RC%
