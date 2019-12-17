#!/usr/bin/env python
"""
sort-zipfile.py FILENAME

Convert .zip file in-place to zero compression and sorted file names,
suitable for storing in Git.
"""
import zipfile
import os
import sys
import argparse
import tempfile
import shutil

def main():
    p = argparse.ArgumentParser(usage=__doc__)
    p.add_argument("filename", action="store", type=str)
    options = p.parse_args()

    mode = zipfile.ZIP_STORED

    fd, target_name = tempfile.mkstemp()
    try:
        os.close(fd)

        with zipfile.ZipFile(options.filename) as source:
            with zipfile.ZipFile(target_name, "w", mode) as target:
                copy_zip_contents(source, target, mode)

        shutil.move(target_name, options.filename)
        target_name = None
    finally:
        if target_name is not None:
            os.unlink(target_name)

def copy_zip_contents(source, target, mode):
    infolist = sorted(source.infolist(), key=lambda info: info.filename)
    for info in infolist:
        target.writestr(info, source.read(info.filename), mode)

if __name__ == "__main__":
    main()
