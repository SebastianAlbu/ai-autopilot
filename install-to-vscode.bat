@echo off
setlocal EnableExtensions

rem ===========================================================================
rem  install-to-vscode.bat
rem  Copy the PR Review agents + skills into the VS Code user "prompts" folder
rem  so they are available globally (in every workspace on this machine).
rem
rem  Usage:
rem    install-to-vscode.bat                     Auto-detect the VS Code folder
rem    install-to-vscode.bat "<prompts folder>"  Copy into an explicit folder
rem
rem  Layout created in the target:
rem    <prompts>\*.agent.md   the reviewer agents
rem    <prompts>\skills\...    the skills they use
rem
rem  NOTE: agents load globally from the prompts folder, but skills do NOT. To use
rem  the skills in every workspace, add the copied skills folder to the user setting
rem  "chat.agentSkillsLocations" (the script prints the exact snippet when it finishes).
rem
rem  Auto-detection looks for a Scoop, stable, or Insiders VS Code install.
rem  If none is found on this PC, you are asked to type a path.
rem ===========================================================================

set "SCRIPT_DIR=%~dp0"
set "AGENTS_SRC=%SCRIPT_DIR%.github\agents"
set "SKILLS_SRC=%SCRIPT_DIR%.github\skills"
set "TARGET="
set "DETECTED="

rem --- Sanity: sources must exist (run this from the repo root) ---
if not exist "%AGENTS_SRC%\" (
    echo [ERROR] Not found: "%AGENTS_SRC%"
    echo Run this script from the ai-agents repository root.
    goto :FAIL
)
if not exist "%SKILLS_SRC%\" (
    echo [ERROR] Not found: "%SKILLS_SRC%"
    echo Run this script from the ai-agents repository root.
    goto :FAIL
)

rem --- 1) An explicit path argument always wins ---
if not "%~1"=="" (
    set "TARGET=%~1"
    set "DETECTED=path from argument"
    goto :HAVE_TARGET
)

rem --- 2) Auto-detect the VS Code user folder on this PC ---
set "C_SCOOP=%USERPROFILE%\scoop\apps\vscode\current\data\user-data\User"
set "C_STABLE=%APPDATA%\Code\User"
set "C_INSIDERS=%APPDATA%\Code - Insiders\User"

if exist "%C_SCOOP%\" (
    set "TARGET=%C_SCOOP%\prompts"
    set "DETECTED=Scoop VS Code"
)
if not defined TARGET if exist "%C_STABLE%\" (
    set "TARGET=%C_STABLE%\prompts"
    set "DETECTED=VS Code (user/system install)"
)
if not defined TARGET if exist "%C_INSIDERS%\" (
    set "TARGET=%C_INSIDERS%\prompts"
    set "DETECTED=VS Code Insiders"
)
if defined TARGET goto :HAVE_TARGET

rem --- 3) Nothing detected: ask the user for a path ---
echo Could not auto-detect a VS Code user folder on this PC.
echo (Looked for Scoop, stable and Insiders installs.)
echo.
:ASK
set "TARGET="
set /p "TARGET=Enter the VS Code prompts folder to copy into (blank = cancel): "
if not defined TARGET (
    echo Cancelled. Nothing was copied.
    goto :FAIL
)
set "DETECTED=path you entered"

:HAVE_TARGET
rem strip surrounding quotes, then a single trailing backslash
set "TARGET=%TARGET:"=%"
if "%TARGET:~-1%"=="\" set "TARGET=%TARGET:~0,-1%"

echo.
echo Source : "%SCRIPT_DIR%.github"
echo Target : "%TARGET%"  (%DETECTED%)
echo    agents -^> "%TARGET%"
echo    skills -^> "%TARGET%\skills"
echo.

rem --- Create the target prompts folder if needed ---
if not exist "%TARGET%\" (
    mkdir "%TARGET%" 2>nul
    if errorlevel 1 (
        echo [ERROR] Could not create "%TARGET%".
        goto :FAIL
    )
)

rem --- Copy agents to the prompts root, skills to prompts\skills ---
xcopy "%AGENTS_SRC%\*" "%TARGET%" /E /I /Y >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy agents.
    goto :FAIL
)
xcopy "%SKILLS_SRC%\*" "%TARGET%\skills" /E /I /Y >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy skills.
    goto :FAIL
)

echo [OK] Agents and skills copied.
echo.

rem --- Register the skills folder so skills load in EVERY workspace ---
rem  Agents load globally from the prompts folder, but skills do NOT: VS Code only
rem  scans workspace skill locations unless we add ours to the user setting
rem  "chat.agentSkillsLocations". Resolve the User folder (parent of prompts).
for %%I in ("%TARGET%\..") do set "USERDIR=%%~fI"
set "SETTINGS_PATH=%USERDIR%\settings.json"
set "SKILLS_DIR=%TARGET%\skills"

rem  Prefer PowerShell 7 (pwsh) if present, else Windows PowerShell.
set "PS=powershell"
where pwsh >nul 2>nul && set "PS=pwsh"

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Add-SkillsLocation.ps1" -SettingsPath "%SETTINGS_PATH%" -SkillsDir "%SKILLS_DIR%"
if errorlevel 1 (
    echo [WARN] Could not update settings.json automatically.
    echo        Add this to your user settings.json manually ^(path must be relative
    echo        or start with "~/"; absolute paths and "\" are not supported^):
    echo          "chat.agentSkillsLocations": { "~/.../User/prompts/skills": true }
)
echo.
echo Next steps in VS Code:
echo   1^) Run "Developer: Reload Window".
echo   2^) Open Chat and pick the "PR Review Orchestrator" agent.
echo.
if "%~1"=="" pause
endlocal
exit /b 0

:FAIL
echo.
if "%~1"=="" pause
endlocal
exit /b 1
