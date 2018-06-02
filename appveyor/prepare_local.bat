REM Run example build locally
REM For debugging.
REM Careful, this might be out of date.  Check against appveyor.yml
set OPENBLAS_COMMIT=5f998ef
set OPENBLAS_ROOT=c:\opt
set MSYS2_ROOT=C:\msys64
set BUILD_BITS=32
set VC9_ROOT=C:\Users\appveyor\AppData\Local\Programs\Common\Microsoft\Visual C++ for Python\9.0\VC
git submodule update --init --recursive
