echo "Building objconv..."
set -e -x
unzip source.zip
g++ -O1 -Wno-deprecated-declarations -o objconv *.cpp
