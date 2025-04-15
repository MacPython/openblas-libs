:: Build script for scipy_openblas wheel on Windows on ARM64

:: Usage: build_steps_win_arm64.bat [build_bits]
:: e.g build_steps_win_arm64.bat 64

:: BUILD_BITS  (default binary architecture, 32 or 64, unspec -> 64).
:: Expects these binaries on the PATH:
:: clang-cl, flang-new, cmake, perl

:: First commit containing WoA build fixes.
:: Minimum OpenBLAS commit to build; we'll update to this if commit not
:: present.
set first_woa_buildable_commit="de2380e5a6149706a633322a16a0f66faa5591fc"

@echo off
setlocal enabledelayedexpansion

if "%1"=="" (
    set BUILD_BIT=64
) else (
    set BUILD_BIT=%1
)
echo Building for %BUILD_BIT%-bit configuration...
 
:: Define destination directory
pushd "%~dp0\.."
set "ob_out_root=%CD%\local\scipy_openblas"
set "ob_64=%ob_out_root%64"
set "ob_32=%ob_out_root%32"
if exist "%ob_64%" xcopy "%ob_64%" "%ob_32%" /I /Y
set "DEST_DIR=%ob_32%"

:: Clone OpenBLAS
echo Cloning OpenBLAS repository with submodules...
git submodule update --init --recursive OpenBLAS
if errorlevel 1 exit /b 1
 
:: Enter OpenBLAS directory and checkout buildable commit
cd OpenBLAS
git merge-base --is-ancestor %first_woa_buildable_commit% HEAD 2>NUL
if errorlevel 1 (
    echo Updating to WoA buildable commit for OpenBLAS
    git checkout %first_woa_buildable_commit%
)
 
:: Create build directory and navigate to it
if exist build (rmdir /S /Q build || exit /b 1)
mkdir build || exit /b 1 & cd build || exit /b 1
 
echo Setting up ARM64 Developer Command Prompt and running CMake...
 
:: Initialize VS ARM64 environment
for /f "usebackq tokens=*" %%i in (`"C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -latest -property installationPath`) do call "%%i\VC\Auxiliary\Build\vcvarsall.bat" arm64
 
:: Run CMake and Ninja build
cmake .. -G Ninja -DCMAKE_BUILD_TYPE=Release -DTARGET=ARMV8 -DBUILD_SHARED_LIBS=ON -DARCH=arm64 ^
-DBINARY=%BUILD_BIT% -DCMAKE_SYSTEM_PROCESSOR=ARM64 -DCMAKE_C_COMPILER=clang-cl ^
-DCMAKE_Fortran_COMPILER=flang-new -DSYMBOLPREFIX="scipy_" -DLIBNAMEPREFIX="scipy_"
if errorlevel 1 exit /b 1
 
ninja
if errorlevel 1 exit /b 1
 
echo Build complete. Returning to Batch.

:: Rewrite the name of the project to scipy-openblas32
echo Rewrite to scipy_openblas32
cd ../..
set out_pyproject=pyproject_64_32.toml
powershell -Command "(Get-Content 'pyproject.toml') -replace 'openblas64', 'openblas32' | Set-Content %out_pyproject%
powershell -Command "(Get-Content 'local\scipy_openblas32\__main__.py') -replace 'openblas64', 'openblas32' | Out-File 'local\scipy_openblas32\__main__.py' -Encoding utf8"
powershell -Command "(Get-Content 'local\scipy_openblas32\__init__.py') -replace 'openblas64', 'openblas32' | Out-File 'local\scipy_openblas32\__init__.py' -Encoding utf8"
powershell -Command "(Get-Content 'local\scipy_openblas32\__init__.py') -replace 'openblas_get_config64_', 'openblas_get_config' | Out-File 'local\scipy_openblas32\__init__.py' -Encoding utf8"
powershell -Command "(Get-Content 'local\scipy_openblas32\__init__.py') -replace 'cflags =.*', 'cflags = \"-DBLAS_SYMBOL_PREFIX=scipy_\"' | Out-File 'local\scipy_openblas32\__init__.py' -Encoding utf8"

:: Prepare destination directory
cd OpenBLAS/build
echo Preparing destination directory at %DEST_DIR%...
if not exist "%DEST_DIR%\lib\cmake\OpenBLAS" mkdir "%DEST_DIR%\lib\cmake\OpenBLAS"
if not exist "%DEST_DIR%\include" mkdir "%DEST_DIR%\include"
 
:: Move library files
echo Moving library files...
if exist lib\release (
    move /Y lib\release\*.dll "%DEST_DIR%\lib\"
    if errorlevel 1 exit /b 1
    move /Y lib\release\*.dll.a "%DEST_DIR%\lib\scipy_openblas.lib"
    if errorlevel 1 exit /b 1
) else (
    echo Error: lib/release directory not found!
    exit /b 1
)
 
:: Copy CMake configuration files
echo Copying CMake configuration files...
if exist openblasconfig.cmake copy /Y openblasconfig.cmake "%DEST_DIR%\lib\cmake\openblas\"
if exist openblasconfigversion.cmake copy /Y openblasconfigversion.cmake "%DEST_DIR%\lib\cmake\openblas\"
 
:: Copy header files
echo Copying generated header files...
if exist generated xcopy /E /Y generated "%DEST_DIR%\include\"
if exist lapacke_mangling.h copy /Y lapacke_mangling.h "%DEST_DIR%\include\"
if exist openblas_config.h copy /Y openblas_config.h "%DEST_DIR%\include\"

 
:: Copy LAPACKE header files
echo Copying LAPACKE header files...
xcopy /Y "..\lapack-netlib\lapacke\include\*.h" "%DEST_DIR%\include\"
if errorlevel 1 exit /b 1
 
:: Move back to the root directory
cd ../..
 
:: Build the Wheel & Install It
echo Running 'python -m build' to build the wheel...
python -c "import build" 2>NUL || pip install build
move /Y  pyproject.toml pyproject.toml.bak
move /Y  %out_pyproject% pyproject.toml
python -m build
if errorlevel 1 exit /b 1
move /Y pyproject.toml.bak pyproject.toml

:: Locate the built wheel
for /f %%f in ('dir /b dist\scipy_openblas*.whl 2^>nul') do set WHEEL_FILE=dist\%%f
 
if not defined WHEEL_FILE (
    echo Error: No wheel file found in dist folder.
    exit /b 1
)
 
echo Installing wheel: %WHEEL_FILE%
pip install "%WHEEL_FILE%"
if errorlevel 1 exit /b 1
 
echo Done.
exit /b 0
