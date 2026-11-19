REM Build script for scipy_openblas wheels on Windows, x86_64 and ARM64 alike.

REM Usage: build_steps_win.bat [build_bits] [if_bits]
REM e.g build_steps_win.bat 64 64

REM build_bits  (default binary architecture, 32 or 64, unspec -> 64).
REM if_bits (default interface size, 32 or 64, unspec -> 32)
REM If INTERFACE64 environment variable is 1, then if_bits defaults to 64
REM PLAT  (target architecture, x86_64 or arm64; unspec -> derived from
REM        PROCESSOR_ARCHITECTURE)
REM WHEEL_PLAT  (wheel platform tag, win_amd64 or win_arm64; unspec ->
REM        derived from PLAT)
REM Expects these binaries on the PATH:
REM   clang-cl, flang, cmake, perl

@echo off
setlocal enabledelayedexpansion

if "%1"=="" (
    set build_bits=64
) else (
    set build_bits=%1
)
if "%INTERFACE64%"=="1" (
    set "if_default=64"
) else (
    set "if_default=32"
)
if "%2"=="" (
    set "if_bits=%if_default%"
) else (
    set "if_bits=%2"
)
REM Resolve the target architecture.  The workflow passes PLAT and WHEEL_PLAT,
REM but derive them when running locally so the script is usable by hand.
if "%PLAT%"=="" (
    if /I "%PROCESSOR_ARCHITECTURE%"=="ARM64" (
        set "PLAT=arm64"
    ) else (
        set "PLAT=x86_64"
    )
)
if "%WHEEL_PLAT%"=="" (
    if "%PLAT%"=="arm64" (
        set "WHEEL_PLAT=win_arm64"
    ) else (
        set "WHEEL_PLAT=win_amd64"
    )
)
if "%PLAT%"=="arm64" (
    set "vcvars_arch=arm64"
) else (
    set "vcvars_arch=x64"
)
echo Building %PLAT% for %build_bits%-bit binary, %if_bits%-bit interface, wheel tag %WHEEL_PLAT%...

REM Define destination directory
pushd "%~dp0\.."
set "ob_out_root=%CD%\local\scipy_openblas"
set "ob_64=%ob_out_root%64"
set "ob_32=%ob_out_root%32"
set "local_dir=%CD%\local"
for /d %%D in ("%local_dir%\*") do (
    if /I not "%%~nxD"=="scipy_openblas64" (
        rmdir /S /Q "%%D"
    )
)
if "%if_bits%"=="64" (
    set "DEST_DIR=%ob_64%"
) else (
    if exist "%ob_64%" (
    xcopy /Y /H "%ob_64%\*.py" "%CD%\ob64_backup\"
    move "%ob_64%" "%ob_32%"
    set "DEST_DIR=%ob_32%"
    )
)

REM Clone OpenBLAS
echo Cloning OpenBLAS repository with submodules...
git submodule update --init --recursive OpenBLAS
if errorlevel 1 exit /b 1
set /p OPENBLAS_COMMIT=<openblas_commit.txt
 
REM Enter OpenBLAS directory and checkout buildable commit
cd OpenBLAS
if "%NIGHTLY%"=="true" (
    REM Build the latest HEAD of develop
    git fetch origin
    git checkout -B develop origin/develop
) else (
    git checkout %OPENBLAS_COMMIT%
)
if errorlevel 1 exit /b 1

REM Patch
set patch_rc=0
for %%f in (..\patches-common\*.patch ..\patches\*.patch ..\patches-windows\*.patch) do (
    git apply --ignore-whitespace %%f
    if errorlevel 1 set patch_rc=1
)
if not "%patch_rc%"=="0" exit /b 1

REM Patch VERSION
REM version=$(grep "^version =" ../pyproject.toml | sed 's/version = "//;s/"//')
REM sed -e "s/^VERSION = .*/VERSION = ${version}/" -i.bak Makefile.rule

if "%NIGHTLY%"=="true" (
    REM v0.3.24-30-g138ed79f -> 0.3.24.30.0 in pyproject.toml
    powershell -Command "$v = ((git describe --tags --abbrev=8) -replace '^v(.*)-g.*', '$1') -replace '-', '.'; (Get-Content ..\pyproject.toml) -replace '^version = .*', ('version = \"' + $v + '.0\"') | Set-Content ..\pyproject.toml"
    if errorlevel 1 exit /b 1
)

for /f "tokens=3 delims= " %%v in ('findstr /b "version = " ..\pyproject.toml') do set version=%%v
set version=%version:"=%
REM The cmake build ignores Makefile.rule and takes the version from
REM CMakeLists.txt, which bakes it into scipy-openblas.pc,
REM OpenBLASConfigVersion.cmake and the OPENBLAS_VERSION in openblas_config.h
REM that openblas_get_config() reports.  Without this it stays at 0.3.34.dev.
powershell -Command "(Get-Content CMakeLists.txt) -replace '^set\(OpenBLAS_VERSION .*', 'set(OpenBLAS_VERSION \"%version%\")' | Set-Content CMakeLists.txt"
if errorlevel 1 exit /b 1
findstr /b /c:"set(OpenBLAS_VERSION" CMakeLists.txt
findstr /b /c:"set(OpenBLAS_VERSION" CMakeLists.txt | findstr /c:"%version%" >NUL
if errorlevel 1 (
    echo Error: could not set OpenBLAS_VERSION to %version% in CMakeLists.txt.
    exit /b 1
)

REM Set suffixed-ILP64 flags
if "%if_bits%"=="64" (
    set "interface_flags=-DINTERFACE64=1 -DSYMBOLSUFFIX=64_"
) else (
    set "interface_flags="
)

REM Create build directory and navigate to it
if exist build (rmdir /S /Q build || exit /b 1)
mkdir build || exit /b 1 & cd build || exit /b 1
 
echo Setting up %vcvars_arch% Developer Command Prompt and running CMake...

REM Initialize the VS environment for the target architecture.
REM
REM Ask vswhere where Visual Studio is rather than hardcoding the version and
REM edition: the windows-11-arm image migrated from VS 2022 to VS 2026 in
REM September 2026 (actions/runner-images#14602), which broke the old
REM hardcoded 2022\Enterprise path.  That failed silently -- CALL on a missing
REM batch file sets no errorlevel worth checking here -- so the vcvars
REM environment was simply never applied and the first visible symptom was
REM CMake reporting "CMAKE_MT-NOTFOUND" and "Detecting C compiler ABI info -
REM failed", because mt.exe and the MSVC/SDK paths were missing.  Fail loudly
REM instead, so the next image change is obvious from the log.
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" set "VSWHERE=%ProgramFiles%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo Error: cannot find vswhere.exe, so cannot locate Visual Studio.
    exit /b 1
)
set "VSINSTALL="
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -prerelease -products * -property installationPath`) do set "VSINSTALL=%%i"
if not defined VSINSTALL (
    echo Error: vswhere.exe reported no Visual Studio installation.
    exit /b 1
)
set "VCVARSALL=%VSINSTALL%\VC\Auxiliary\Build\vcvarsall.bat"
if not exist "%VCVARSALL%" (
    echo Error: no VC\Auxiliary\Build\vcvarsall.bat under "%VSINSTALL%".
    exit /b 1
)
echo Using Visual Studio at "%VSINSTALL%"
CALL "%VCVARSALL%" %vcvars_arch%
if errorlevel 1 (
    echo Error: "%VCVARSALL%" %vcvars_arch% failed.
    exit /b 1
)
where mt.exe >NUL 2>&1
if errorlevel 1 (
    echo Error: mt.exe is not on PATH after vcvarsall; CMake will fail with
    echo CMAKE_MT-NOTFOUND. The Windows SDK component may be missing.
    exit /b 1
)
 
REM Prefer LLVM flang
PATH=C:\Program Files\LLVM\bin;%PATH%

REM Visual Studio ships its own LLVM with an incomplete flang, so confirm
REM which compilers we actually resolved to.
where clang-cl
if errorlevel 1 (
    echo Error: clang-cl is not on PATH.
    exit /b 1
)
where flang
if errorlevel 1 (
    echo Error: flang is not on PATH.
    exit /b 1
)
clang-cl --version
flang --version

REM flang's objects carry a /DEFAULTLIB:flang_rt.runtime.dynamic directive, but
REM OpenBLAS links the DLL with a hand-written lld-link call (no flang driver,
REM no /LIBPATH), so the runtime archive must be findable through LIB.  It
REM lives in LLVM's per-target resource directory, whose version component
REM tracks the LLVM release, so look it up rather than hardcoding it.
if "%PLAT%"=="arm64" (
    set "flang_rt_triple=aarch64-pc-windows-msvc"
) else (
    set "flang_rt_triple=x86_64-pc-windows-msvc"
)
REM "for /d" over a quoted wildcard matches nothing, and the path has a space
REM in it, so list the version directories with dir instead.
set "clang_res_root=C:\Program Files\LLVM\lib\clang"
set "FLANG_RT_DIR="
for /f "delims=" %%v in ('dir /b /ad "%clang_res_root%" 2^>NUL') do (
    if exist "%clang_res_root%\%%v\lib\%flang_rt_triple%\flang_rt.runtime.dynamic.lib" set "FLANG_RT_DIR=%clang_res_root%\%%v\lib\%flang_rt_triple%"
)
if not defined FLANG_RT_DIR (
    echo Error: no flang_rt.runtime.dynamic.lib for %flang_rt_triple% under
    echo "%clang_res_root%" - the DLL link would fail with
    echo "lld-link: error: could not open flang_rt.runtime.dynamic.lib".
    exit /b 1
)
echo Using flang runtime from "%FLANG_RT_DIR%"
set "LIB=%FLANG_RT_DIR%;%LIB%"

REM Run CMake and Ninja build

REM CONSISTENT_FPCSR is x86-only: it makes blas_server_win32.c save and restore
REM the FPU/SSE control words with ldmxcsr/fldcw/fnstcw/stmxcsr inline asm,
REM which clang-cl rejects on arm64 ("unrecognized instruction mnemonic").
if "%PLAT%"=="arm64" (
    set "arch_flags=-DTARGET=ARMV8 -DCMAKE_SYSTEM_PROCESSOR=arm64 -DCMAKE_SYSTEM_NAME=Windows"
) else (
    set "arch_flags=-DTARGET=PRESCOTT -DDYNAMIC_ARCH=ON -DDYNAMIC_LIST=NEHALEM;SANDYBRIDGE;HASWELL;SKYLAKEX -DCONSISTENT_FPCSR=1"
)

REM OpenBLAS's cmake/cc.cmake appends -Wall for any Clang, but clang-cl parses
REM -Wall as MSVC /Wall, i.e. -Weverything: that produced 63k warnings and a
REM 30MB log.  It is appended to CMAKE_C_FLAGS after anything we put in CFLAGS,
REM so the only slot that lands later is CMAKE_C_FLAGS_RELEASE.
set CFLAGS=
set "release_flags=/MD /O2 /Ob2 /DNDEBUG -Wno-everything"
cmake .. -G Ninja ^
 -DCMAKE_BUILD_TYPE=Release ^
 -DCMAKE_C_FLAGS_RELEASE="%release_flags%" ^
 -DBINARY=%build_bits% ^
 -DCMAKE_C_COMPILER=clang-cl ^
 -DCMAKE_Fortran_COMPILER=flang ^
 -DBUILD_SHARED_LIBS=ON ^
 -DSYMBOLPREFIX="scipy_" ^
 -DLIBNAMEPREFIX="scipy_" ^
 -DUSE_THREAD=1 ^
 -DUSE_OPENMP=0 ^
 -DNUM_THREADS=24 ^
 -DNO_WARMUP=1 ^
 -DBUILD_LAPACK_DEPRECATED=ON ^
 -DFIXED_LIBNAME=1 ^
 -DBUFFERSIZE=20 ^
 %arch_flags% ^
 %interface_flags%

if errorlevel 1 exit /b 1

ninja -j 16
if errorlevel 1 exit /b 1
 
echo Build complete. Returning to Batch.

cd ../..
if "%if_bits%"=="32" (
    echo Rewrite to scipy_openblas32
    set out_pyproject=pyproject_64_32.toml
    powershell -Command "(Get-Content 'pyproject.toml') -replace 'openblas64', 'openblas32' | Set-Content !out_pyproject!"
    cd local
    move scipy_openblas64 scipy_openblas32
    powershell -Command "(Get-Content 'scipy_openblas32\__main__.py') -replace 'openblas64', 'openblas32' | Out-File 'scipy_openblas32\__main__.py' -Encoding utf8"
    powershell -Command "(Get-Content 'scipy_openblas32\__init__.py') -replace 'openblas64', 'openblas32' | Out-File 'scipy_openblas32\__init__.py' -Encoding utf8"
    powershell -Command "(Get-Content 'scipy_openblas32\__init__.py') -replace 'openblas_get_config64_', 'openblas_get_config' | Out-File 'scipy_openblas32\__init__.py' -Encoding utf8"
    powershell -Command "(Get-Content 'scipy_openblas32\__init__.py') -replace 'cflags =.*', 'cflags = \"-DBLAS_SYMBOL_PREFIX=scipy_\"' | Out-File 'scipy_openblas32\__init__.py' -Encoding utf8"
    cd ..
)

REM Prepare destination directory
cd OpenBLAS/build
echo Preparing destination directory at %DEST_DIR%
if not exist "%DEST_DIR%\lib\cmake\openblas" mkdir "%DEST_DIR%\lib\cmake\openblas"
if not exist "%DEST_DIR%\include" mkdir "%DEST_DIR%\include"
 
REM Move library files
echo Moving library files...
if exist lib\release (
    move /Y lib\release\*.dll "%DEST_DIR%\lib\"
    if errorlevel 1 exit /b 1
    for %%f in (lib\release\*.dll.a) do (
        set "orig_name=%%~nxf"
        call set "base_name=%%orig_name:.dll.a=%%"
        move /Y "%%f" "%DEST_DIR%\lib\!base_name!.lib"
    )
    if errorlevel 1 exit /b 1
) else (
    echo Error: lib/release directory not found!
    exit /b 1
)
 
REM Write the CMake package configuration.  OpenBLAS generates
REM OpenBLAS<SUFFIX64>Config.cmake, which include()s an OpenBLASTargets.cmake
REM describing the "make install" layout; neither suits the wheel, so write
REM our own from the template and keep OpenBLAS's version file.
echo Writing CMake configuration files...
if "%if_bits%"=="64" (
    set "cm_libname=scipy_openblas_64"
) else (
    set "cm_libname=scipy_openblas"
)
powershell -Command "(Get-Content '%~dp0OpenBLASConfig.cmake.in') -replace '@VERSION@', '%version%' -replace '@LIBNAME@', '%cm_libname%' | Set-Content '%DEST_DIR%\lib\cmake\openblas\OpenBLASConfig.cmake'"
if errorlevel 1 exit /b 1
if not exist "%DEST_DIR%\lib\cmake\openblas\OpenBLASConfig.cmake" (
    echo Error: failed to write OpenBLASConfig.cmake.
    exit /b 1
)
if exist openblasconfigversion.cmake copy /Y openblasconfigversion.cmake "%DEST_DIR%\lib\cmake\openblas\"
 
REM Copy header files
echo Copying generated header files...
if exist generated xcopy /E /Y generated "%DEST_DIR%\include\"
if exist lapacke_mangling.h copy /Y lapacke_mangling.h "%DEST_DIR%\include\"
if exist openblas_config.h copy /Y openblas_config.h "%DEST_DIR%\include\"

 
REM Copy LAPACKE header files
echo Copying LAPACKE header files...
xcopy /Y "..\lapack-netlib\lapacke\include\*.h" "%DEST_DIR%\include\"
if errorlevel 1 exit /b 1

echo Create pkgconfig scipy-openblas.pc
if not exist "%DEST_DIR%\lib\pkgconfig" mkdir "%DEST_DIR%\lib\pkgconfig"
copy /Y openblas*.pc "%DEST_DIR%\lib\pkgconfig\scipy-openblas.pc"
if errorlevel 1 exit /b 1
cd ../..
bash -e tools\get_pkg_config.sh
if errorlevel 1 (
    echo could not construct scipy-openblas.pc
    exit /b 1
)

(echo.)>> LICENSE.txt
(echo ----)>> LICENSE.txt
(echo.)>> LICENSE.txt
type tools\LICENSE_win_flang.txt >> LICENSE.txt
if errorlevel 1 exit /b 1

REM Build the Wheel & Install It
echo Running 'python -m build' to build the wheel in %CD%
python -c "import build" 2>NUL || pip install build
if "%if_bits%"=="64" (
    python -m build
    if errorlevel 1 exit /b 1
) else (
    move /Y pyproject.toml pyproject.toml.bak
    move /Y %out_pyproject% pyproject.toml
    python -m build
    if errorlevel 1 exit /b 1
    move /Y pyproject.toml.bak pyproject.toml
)
if "%if_bits%"=="32" (
    move /Y "%CD%\ob64_backup" "%ob_64%"
)

REM Rename the wheel
for %%f in (dist\*any.whl) do (
    set WHEEL_FILE=dist\%%f
    set "filename=%%~nxf"
    set "newname=!filename:any.whl=%WHEEL_PLAT%.whl!"
    ren "dist\!filename!" "!newname!"
)

REM Locate the built wheel
for /f %%f in ('dir /b dist\scipy_openblas*.whl 2^>nul') do set WHEEL_FILE=dist\%%f

if not defined WHEEL_FILE (
    echo Error: No wheel file found in dist folder.
    exit /b 1
)
 
echo Installing wheel: %WHEEL_FILE%
pip install "%WHEEL_FILE%"
if errorlevel 1 exit /b 1
 
echo Testing
python -m pip install pkgconf
python -m pkgconf scipy-openblas --cflags
if errorlevel 1 exit /b 1

echo Done.
exit /b 0
