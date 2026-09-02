@echo off
setlocal enabledelayedexpansion
rem  goEMM installer for Windows, for the Command Prompt.
rem
rem  cmd rather than PowerShell because cmd is what people open, and
rem  because PowerShell's execution policy turns a one-line install into a
rem  conversation about signing policy on somebody's first minute with the
rem  program.
rem
rem  Batch can do this honestly only because the downloads repository is
rem  public: the latest/download alias gives direct URLs, so there is no
rem  JSON to parse. curl.exe ships with Windows 10 1803 and later, and
rem  certutil computes the checksum. Nothing else is needed.
rem
rem  Every step fails loudly. That is the whole point:
rem    - curl -f makes an HTTP error an error, instead of saving the error
rem      page under the name the binary was supposed to have
rem    - the checksum is compared against the published manifest entry for
rem      this exact file, not merely computed and printed
rem    - the installed binary has to prove itself by running
rem
rem  Usage:
rem    install.bat            install, or report an existing install
rem    install.bat --force    install over one that is already there

set "REPO=tkraljevic/goEMM"
set "BASE=https://github.com/%REPO%/releases/latest/download"
if "%EMM_INSTALL_DIR%"=="" (set "DIR=%USERPROFILE%\.emm") else (set "DIR=%EMM_INSTALL_DIR%")
set "FORCE="
if /i "%~1"=="--force" set "FORCE=1"
if /i "%~1"=="-force" set "FORCE=1"

rem --- which build -------------------------------------------------------
if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" set "ASSET=emm-windows-amd64.exe"
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "ASSET=emm-windows-arm64.exe"
rem  A 32-bit cmd on a 64-bit machine reports x86 and names the real one here.
if /i "%PROCESSOR_ARCHITEW6432%"=="AMD64" set "ASSET=emm-windows-amd64.exe"
if /i "%PROCESSOR_ARCHITEW6432%"=="ARM64" set "ASSET=emm-windows-arm64.exe"
if "%ASSET%"=="" (
  echo.
  echo goEMM has no build for %PROCESSOR_ARCHITECTURE%. Supported: AMD64 and ARM64.
  exit /b 1
)
echo Installing goEMM for windows/%PROCESSOR_ARCHITECTURE% into %DIR%

rem --- already here? -----------------------------------------------------
if exist "%DIR%\emm.exe" if not defined FORCE (
  echo.
  echo goEMM is already installed at %DIR%\emm.exe
  echo.
  echo To move to the newest version, use its own updater, which keeps a copy
  echo of the one it replaces:
  echo.
  echo     "%DIR%\emm.exe" update
  echo.
  echo To install over it anyway:  install.bat --force
  echo   ^(that replaces the program only - your memories are a separate file.
  echo    Close goEMM first: "%DIR%\emm.exe" http stop, and quit it from the tray.^)
  exit /b 1
)

where curl.exe >nul 2>&1
if errorlevel 1 (
  echo.
  echo This needs curl.exe, which Windows has shipped since version 1803.
  echo On an older Windows, download the file by hand from
  echo   https://github.com/%REPO%/releases/latest
  exit /b 1
)

set "TMPD=%TEMP%\emm-install-%RANDOM%"
mkdir "%TMPD%" >nul 2>&1

rem --- download ----------------------------------------------------------
rem  -f so that an HTTP error is an error. Without it curl saves the error
rem  page under the name the binary should have had, and the failure turns
rem  up much later as a program that will not start.
echo Downloading %ASSET%...
curl -fsSL -o "%TMPD%\%ASSET%" "%BASE%/%ASSET%"
if errorlevel 1 (
  echo.
  echo Could not download %ASSET% from %BASE%
  echo Check the network, then try again. Nothing was installed.
  rmdir /s /q "%TMPD%" >nul 2>&1
  exit /b 1
)
curl -fsSL -o "%TMPD%\SHA256SUMS.txt" "%BASE%/SHA256SUMS.txt"
if errorlevel 1 (
  echo.
  echo Could not download the checksums. Nothing was installed.
  rmdir /s /q "%TMPD%" >nul 2>&1
  exit /b 1
)

rem --- prove it is what it claims ---------------------------------------
set "WANT="
for /f "tokens=1,2" %%A in ('type "%TMPD%\SHA256SUMS.txt"') do (
  if /i "%%B"=="%ASSET%" set "WANT=%%A"
  if /i "%%B"=="*%ASSET%" set "WANT=%%A"
)
if "!WANT!"=="" (
  echo.
  echo The checksum file does not list %ASSET%.
  echo That means the release is incomplete, not that your download is bad.
  echo Nothing was installed.
  rmdir /s /q "%TMPD%" >nul 2>&1
  exit /b 1
)

set "GOT="
for /f "skip=1 tokens=*" %%H in ('certutil -hashfile "%TMPD%\%ASSET%" SHA256') do (
  if not defined GOT set "GOT=%%H"
)
rem  certutil prints the hash with spaces on some versions; take them out.
set "GOT=!GOT: =!"

if /i not "!GOT!"=="!WANT!" (
  echo.
  echo The download does not match its published checksum.
  echo.
  echo   expected  !WANT!
  echo   got       !GOT!
  echo.
  echo Nothing was installed. Try again; if it repeats, say so - a mismatch
  echo that survives a retry is worth knowing about.
  rmdir /s /q "%TMPD%" >nul 2>&1
  exit /b 1
)
echo Checksum verified.

rem --- put it in place and make it prove itself -------------------------
if not exist "%DIR%" mkdir "%DIR%" >nul 2>&1
rem  2>nul as well as >nul: without it Windows prints its own "Access
rem  is denied." first, and the message written for this case arrives
rem  underneath an error that names no process and no remedy.
move /y "%TMPD%\%ASSET%" "%DIR%\emm.exe" >nul 2>nul
if errorlevel 1 (
  echo.
  echo Could not put emm.exe in %DIR%, most likely because goEMM is running.
  echo Windows will not replace a file that is open, and the tray usually
  echo has it running. Close it first:
  echo.
  echo     "%DIR%\emm.exe" http stop
  echo     ^(and quit goEMM from the system tray, if it is there^)
  echo.
  echo Nothing was changed. Your memories are in a separate file and are not
  echo affected either way.
  rmdir /s /q "%TMPD%" >nul 2>&1
  exit /b 1
)
rmdir /s /q "%TMPD%" >nul 2>&1

rem  The zone marker Windows puts on anything downloaded, which otherwise
rem  makes the first run a SmartScreen dialog rather than a program.
if exist "%DIR%\emm.exe:Zone.Identifier" del "%DIR%\emm.exe:Zone.Identifier" >nul 2>&1

"%DIR%\emm.exe" version >nul 2>&1
if errorlevel 1 (
  echo.
  echo The binary was installed but will not run:
  echo     "%DIR%\emm.exe" version
  echo failed. The file is in place; nothing else was changed.
  exit /b 1
)
for /f "tokens=*" %%V in ('"%DIR%\emm.exe" version') do set "INSTALLED=%%V"
echo Installed: !INSTALLED!

echo.
echo Next:
echo     "%DIR%\emm.exe" demo          see what it does, on a throwaway database
echo     "%DIR%\emm.exe" setup         connect your AI assistants
echo     "%DIR%\emm.exe" setup path    so you can type 'emm' from anywhere
endlocal
exit /b 0
