#!/bin/bash
set -ex

# Note that the anaconda-client package on PyPI is too old. Install from github
# tag instead:
echo $(python -c "import sys; print(sys.version)")
pip install -q git+https://github.com/Anaconda-Platform/anaconda-client@1.7.2
upload_to_anaconda

