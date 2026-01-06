@echo off
REM Zerto Compliance Launcher Bootstrapper
REM Checks for .NET 8 Desktop Runtime and launches the tool

SET "LAUNCHER_EXE=%~dp0ZertoComplianceLauncher.exe"
SET "MIN_DOTNET_VERSION=8.0"

REM Check if launcher exists
IF NOT EXIST "%LAUNCHER_EXE%" (
    echo ERROR: ZertoComplianceLauncher.exe not found in %~dp0
    echo Please run the installer first.
    pause
    exit /b 1
)

REM Check for .NET 8 Desktop Runtime
echo Checking for .NET Desktop Runtime...

REM Try to find dotnet
where dotnet >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    echo WARNING: dotnet command not found in PATH
    goto :INSTALL_PROMPT
)

REM Check installed runtimes
dotnet --list-runtimes | findstr /C:"Microsoft.WindowsDesktop.App 8." >nul
IF %ERRORLEVEL% EQU 0 (
    echo .NET Desktop Runtime 8.x detected.
    goto :LAUNCH
)

:INSTALL_PROMPT
echo.
echo ============================================================
echo  .NET 8 Desktop Runtime NOT FOUND
echo ============================================================
echo.
echo The Zerto Compliance Launcher requires .NET 8 Desktop Runtime.
echo.
echo Download from: https://dotnet.microsoft.com/download/dotnet/8.0
echo Look for: ".NET Desktop Runtime 8.0.x" (Windows x64)
echo.
echo After installation, run this bootstrapper again.
echo ============================================================
echo.
choice /C YN /M "Open download page now?"
IF %ERRORLEVEL% EQU 1 (
    start https://dotnet.microsoft.com/download/dotnet/8.0
)
pause
exit /b 1

:LAUNCH
echo Launching Zerto Compliance Tool...
start "" "%LAUNCHER_EXE%"
exit /b 0
