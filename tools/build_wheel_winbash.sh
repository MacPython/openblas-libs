# This will fail if there is more than one file in libs
unzip -d local/openblas libs/openblas*.zip
if [ -d local/openblas/64 ]; then
    mv local/openblas/64/* local/openblas
    rm -rf local/openblas/64
else
    mv local/openblas/32/* local/openblas
    rm -rf local/openblas/32
fi

rm local/openblas/lib/*.a
rm local/openblas/lib/*.exp
rm local/openblas/lib/*.def
mv local/openblas/bin/* local/openblas/lib

python3.7 -m pip install wheel auditwheel
python3.7 -m pip wheel -w /tmp/wheelhouse -vv .
auditwheel repair -w dist/ /tmp/wheelhouse/openblas-*.whl
