#!/bin/bash
set -ex

# Note that the anaconda-client package on PyPI is too old. Install from github
# tag instead:
echo $(python -c "import sys; print(sys.version)")
sudo chmod -R a+w /home/travis/.cache
pip install -q git+https://github.com/Anaconda-Platform/anaconda-client@1.8.0
upload_to_anaconda

