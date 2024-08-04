rem Build x86_64 OpenBLAS locally with 64-bit interfaces
rem Requires c:\rtools40
set BASH_PATH=c:\rtools40\usr\bin\bash.exe
set BUILD_BITS=64
set CHERE_INVOKING=yes
set INTERFACE64=1
set LDFLAGS=-lucrt -static -static-libgcc -Wl,--defsym,quadmath_snprintf=snprintf
set MSYSTEM=UCRT64
set PLAT=x86_64
set START_DIR=d:\pypy_stuff\openblas-libs
set OPENBLAS_ROOT=c:\\opt
rmdir /q /s c:\opt\64
rem %BASH_PATH% -lc tools/build_openblas.sh
rem %BASH_PATH% -lc tools/build_gfortran.sh
