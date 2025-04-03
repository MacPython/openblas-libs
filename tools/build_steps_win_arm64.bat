:: Build script for scipy_openblas wheel on Windows on ARM64

:: Usage: build_steps_win_arm64.bat [build_bits]
:: e.g build_steps_win_arm64.bat 64

:: BUILD_BITS  (default binary architecture, 32 or 64, unspec -> 64).
:: Expects these binaries on the PATH:
:: clang-cl, flang-new, cmake, perl

@echo off
setlocal enabledelayedexpansion

if "%1"=="" (
    set BUILD_BIT=64
) else (
    set BUILD_BIT=%1
)
echo Building for %BUILD_BIT%-bit configuration...
 
:: Define destination directory
move "..\local\scipy_openblas64" "..\local\scipy_openblas32"
set "DEST_DIR=%CD%\..\local\scipy_openblas32"
cd ..
 
:: Check if 'openblas' folder exists and is empty
if exist "openblas" (
    dir /b "openblas" | findstr . >nul
    if errorlevel 1 (
        echo OpenBLAS folder exists but is empty. Deleting and recloning...
        rmdir /s /q "openblas"
    )
)
 
:: Clone OpenBLAS if not present
if not exist "openblas" (
    echo Cloning OpenBLAS repository with submodules...
    git clone --recursive https://github.com/OpenMathLib/OpenBLAS.git OpenBLAS
    if errorlevel 1 exit /b 1
)
 
:: Enter OpenBLAS directory and checkout develop branch
cd openblas
git checkout develop
 
echo Checked out to the latest branch of OpenBLAS.
 
:: Create build directory and navigate to it
if not exist build mkdir build
cd build
 
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
powershell -Command "(Get-Content 'pyproject.toml') -replace 'openblas64', 'openblas32' | Set-Content 'pyproject.toml'"
powershell -Command "(Get-Content 'local\scipy_openblas32\__main__.py') -replace 'openblas64', 'openblas32' | Out-File 'local\scipy_openblas32\__main__.py' -Encoding utf8"
powershell -Command "(Get-Content 'local\scipy_openblas32\__init__.py') -replace 'openblas64', 'openblas32' | Out-File 'local\scipy_openblas32\__init__.py' -Encoding utf8"
powershell -Command "(Get-Content 'local\scipy_openblas32\__init__.py') -replace 'openblas_get_config64_', 'openblas_get_config' | Out-File 'local\scipy_openblas32\__init__.py' -Encoding utf8"
powershell -Command "(Get-Content 'local\scipy_openblas32\__init__.py') -replace 'cflags =.*', 'cflags = \"-DBLAS_SYMBOL_PREFIX=scipy_\"' | Out-File 'local\scipy_openblas32\__init__.py' -Encoding utf8"

:: Prepare destination directory
cd OpenBLAS/build
echo Preparing destination directory at %DEST_DIR%...
if not exist "%DEST_DIR%\lib\cmake\openblas" mkdir "%DEST_DIR%\lib\cmake\openblas"
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
if exist lapacke_mangling copy /Y lapacke_mangling "%DEST_DIR%\include\"
if exist openblas_config.h copy /Y openblas_config.h "%DEST_DIR%\include\"

 
:: Copy LAPACKE header files
echo Copying LAPACKE header files...
xcopy /Y "..\lapack-netlib\lapacke\include\*.h" "%DEST_DIR%\include\"
if errorlevel 1 exit /b 1
 
:: Move back to the root directory
cd ../..
 
:: Build the Wheel & Install It
echo Running 'python -m build' to build the wheel...
python -m build
if errorlevel 1 exit /b 1
 
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