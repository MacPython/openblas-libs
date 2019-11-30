echo "Building objconv..."
set -e -x
unzip source.zip
g++ -O1 -o objconv *.cpp
