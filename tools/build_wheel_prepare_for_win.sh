set -xeo pipefail
python -m pip install wheel
# This will fail if there is more than one file in libs
unzip -d local/scipy_openblas64 builds/openblas*.zip
if [[ -d local/scipy_openblas64/64 ]]; then
    mv local/scipy_openblas64/64/* local/scipy_openblas64
else
    mv local/scipy_openblas64/32/* local/scipy_openblas64
fi
mv local/scipy_openblas64/bin/*.dll local/scipy_openblas64/lib
rm local/scipy_openblas64/lib/*.a
rm -f local/scipy_openblas64/lib/*.exp  # may not exist?
rm local/scipy_openblas64/lib/*.def
rm -rf local/scipy_openblas64/lib/pkgconfig
if [[ -d local/scipy_openblas64/64 ]]; then
    rm -rf local/scipy_openblas64/64
else
    rm -rf local/scipy_openblas64/32
fi
sed -e "s/bin/lib/" -i local/scipy_openblas64/lib/cmake/openblas/OpenBLASConfig.cmake
sed -e "s/dll/lib/" -i local/scipy_openblas64/lib/cmake/openblas/OpenBLASConfig.cmake
if [[ "${INTERFACE64}" != "1" ]]; then
    mv local/scipy_openblas64 local/scipy_openblas32
    # rewrite the name of the project to scipy-openblas32
    # this is a hack, but apparently there is no other way to change the name
    # of a pyproject.toml project
    sed -e "s/openblas64/openblas32/" -i pyproject.toml
    sed -e "s/openblas_get_config64_/openblas_get_config/" -i local/scipy_openblas32/__init__.py
    sed -e "s/cflags =.*/cflags = '-DBLAS_SYMBOL_PREFIX=scipy_'/" -i local/scipy_openblas32/__init__.py
    sed -e "s/openblas64/openblas32/" -i local/scipy_openblas32/__init__.py
    sed -e "s/openblas64/openblas32/" -i local/scipy_openblas32/__main__.py
fi
echo "" >> LICENSE.txt
echo "----" >> LICENSE.txt
echo "" >> LICENSE.txt
cat tools/LICENSE_win32.txt >> LICENSE.txt