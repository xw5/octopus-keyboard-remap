@echo off
setlocal enabledelayedexpansion
REM Build OctopusKeyRemap - requires Lazarus installed at C:\lazarus
REM Usage: build.bat [build|release|test]  (release = build + package zip)
cd /d "%~dp0"

set "FPC=C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe"
set "WINDRES=C:\lazarus\fpc\3.2.2\bin\x86_64-win64\windres.exe"
REM windres needs cpp (C preprocessor) from the same bin dir on PATH
set "PATH=C:\lazarus\fpc\3.2.2\bin\x86_64-win64;%PATH%"

REM ---- -gl line info bloats the exe to ~27MB (COFF debug sections);
REM ---- release strips it (-Xs, ~3MB), dev builds keep -gl for crash.log.
REM ---- Crash diagnosis of release exe: build.bat trace (-O- -gl trace exe)
set "DBG=-gl"
if /i "%~1"=="release" set "DBG=-Xs"

if not exist "%FPC%" (
  echo ERROR: FPC not found at "%FPC%"
  exit /b 1
)

REM ---- engine tests: no LCL needed, exit code gates the build ----
if /i "%~1"=="test" (
  cd /d "%~dp0tests"
  "%FPC%" -Fu..\src test_remap.lpr
  if errorlevel 1 exit /b 1
  .\test_remap.exe
  set "RC=%errorlevel%"
  exit /b !RC!
)

REM ---- diagnostic build with FPC line info (-gl) for crash.log backtraces ----
if /i "%~1"=="trace" (
  if not exist lib\trace mkdir lib\trace
  "%FPC%" -O- -gl -Sh -WG -Fusrc -FUlib\trace -FEbin -oOctopusKeyRemap-trace.exe ^
    -FuC:\lazarus\lcl\units\x86_64-win64 ^
    -FuC:\lazarus\lcl\units\x86_64-win64\win32 ^
    -FuC:\lazarus\components\lazutils\lib\x86_64-win64 ^
    octopusremap.lpr
  exit /b %errorlevel%
)

REM ---- Read APP_VERSION from src\version.inc (single source of truth) ----
set "APP_VERSION="
for /f "tokens=2 delims='" %%v in ('findstr /b "APP_VERSION" src\version.inc') do set "APP_VERSION=%%v"
if not defined APP_VERSION (
  echo ERROR: cannot read APP_VERSION from src\version.inc
  exit /b 1
)
for /f "tokens=1-3 delims=." %%a in ("%APP_VERSION%") do (
  set "VER_MAJOR=%%a"
  set "VER_MINOR=%%b"
  set "VER_PATCH=%%c"
)

if not exist bin mkdir bin
if not exist lib\gen mkdir lib\gen
if not exist lib\x86_64-win64 mkdir lib\x86_64-win64

REM ---- VERSIONINFO resource: exe properties show version info.
REM ---- Regenerated in place (res\*.res is committed, so lazbuild works too)
> lib\gen\versioninfo.rc echo 1 VERSIONINFO
>> lib\gen\versioninfo.rc echo FILEVERSION !VER_MAJOR!,!VER_MINOR!,!VER_PATCH!,0
>> lib\gen\versioninfo.rc echo PRODUCTVERSION !VER_MAJOR!,!VER_MINOR!,!VER_PATCH!,0
>> lib\gen\versioninfo.rc echo FILEOS 0x40004L
>> lib\gen\versioninfo.rc echo FILETYPE 0x1L
>> lib\gen\versioninfo.rc echo BEGIN
>> lib\gen\versioninfo.rc echo   BLOCK "StringFileInfo"
>> lib\gen\versioninfo.rc echo   BEGIN
>> lib\gen\versioninfo.rc echo     BLOCK "040904B0"
>> lib\gen\versioninfo.rc echo     BEGIN
>> lib\gen\versioninfo.rc echo       VALUE "CompanyName", "OctopusKeyRemap"
>> lib\gen\versioninfo.rc echo       VALUE "FileDescription", "OctopusKeyRemap - keyboard remapper"
>> lib\gen\versioninfo.rc echo       VALUE "FileVersion", "%APP_VERSION%.0"
>> lib\gen\versioninfo.rc echo       VALUE "InternalName", "octopusremap"
>> lib\gen\versioninfo.rc echo       VALUE "OriginalFilename", "OctopusKeyRemap.exe"
>> lib\gen\versioninfo.rc echo       VALUE "ProductName", "OctopusKeyRemap"
>> lib\gen\versioninfo.rc echo       VALUE "ProductVersion", "%APP_VERSION%"
>> lib\gen\versioninfo.rc echo     END
>> lib\gen\versioninfo.rc echo   END
>> lib\gen\versioninfo.rc echo   BLOCK "VarFileInfo"
>> lib\gen\versioninfo.rc echo   BEGIN
>> lib\gen\versioninfo.rc echo     VALUE "Translation", 0x409, 0x04B0
>> lib\gen\versioninfo.rc echo   END
>> lib\gen\versioninfo.rc echo END
"%WINDRES%" -i lib\gen\versioninfo.rc -o res\versioninfo.res

REM ---- Manifest resource: asInvoker + Common-Controls v6, version injected.
REM ---- Inline RC string block (external-file embedding mangled the XML)
(for /f "usebackq delims=" %%L in ("src\manifest_clean.rc") do (
  set "LINE=%%L"
  echo !LINE:@APPVER@=%APP_VERSION%!
)) > lib\gen\manifest_gen.rc
"%WINDRES%" -i lib\gen\manifest_gen.rc -o res\manifest.res

REM ---- Application icon -> res (ALL resources go through the .res path;
REM ---- mixing {\$R .rc} and {\$R .res} breaks the PE resource directory)
"%WINDRES%" -i src\appicon.rc -o res\appicon.res

"%FPC%" -O2 %DBG% -Sh -WG -Fusrc -FUlib\x86_64-win64 -FEbin -oOctopusKeyRemap.exe ^
  -FuC:\lazarus\lcl\units\x86_64-win64 ^
  -FuC:\lazarus\lcl\units\x86_64-win64\win32 ^
  -FuC:\lazarus\components\lazutils\lib\x86_64-win64 ^
  octopusremap.lpr

if not exist bin\OctopusKeyRemap.exe (
  echo BUILD FAILED
  exit /b 1
)
echo BUILD OK: bin\OctopusKeyRemap.exe  v%APP_VERSION%

REM ---- Package release zip: release\OctopusKeyRemap-v<version>-win64.zip ----
if /i "%~1"=="release" (
  if not exist release mkdir release
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Compress-Archive -Force -Path 'bin\OctopusKeyRemap.exe','README.md' -DestinationPath 'release\OctopusKeyRemap-v%APP_VERSION%-win64.zip'"
  if errorlevel 1 (
    echo PACKAGE FAILED
    exit /b 1
  )
  echo RELEASE: release\OctopusKeyRemap-v%APP_VERSION%-win64.zip
)

if "%~1"=="" pause
