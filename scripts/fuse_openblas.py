""" Fuse libraries in OpenBLAS macOS wheels

Rewrites with _intel platform suffix replacing i386 / x86_64
"""

import os
from os.path import exists, abspath
from urllib.request import urlretrieve
from contextlib import contextmanager
from tempfile import TemporaryDirectory
import tarfile

from delocate.fuse import fuse_trees

CDN_URL="https://3f23b170c54c2533c070-1c8a9b3114517dc5fe17b7c3f8c63a43.ssl.cf2.rackcdn.com"
VERSION="v0.3.0"
SUFFIX="gf_1becaaa"
DEPLOYMENT_TARGET="10_6"

FNAME_TEMPLATE = ("openblas-{VERSION}-macosx_{DEPLOYMENT_TARGET}_{plat}"
                  "-{SUFFIX}.tar.gz")
URL_TEMPLATE = "{CDN_URL}/{fname}"

GLOBALS = globals().copy()


def extract_tar(fname, out_path):
    fname = abspath(fname)
    with working_directory(out_path):
        tar = tarfile.open(fname, "r:gz")
        tar.extractall()
        tar.close()


@contextmanager
def working_directory(path):
    """A context manager which changes the working directory to the given
    path, and then changes it back to its previous value on exit.

    """
    prev_cwd = os.getcwd()
    if not exists(path):
        os.makedirs(path)
    os.chdir(path)
    try:
        yield
    finally:
        os.chdir(prev_cwd)


PLATS = ('x86_64', 'i386')

out_fname = abspath(FNAME_TEMPLATE.format(plat='intel', **GLOBALS))

with TemporaryDirectory() as tmpdir, \
      working_directory(tmpdir):
    for plat in PLATS:
        fname = FNAME_TEMPLATE.format(plat=plat, **GLOBALS)
        urlretrieve(URL_TEMPLATE.format(fname=fname, **GLOBALS), fname)
        extract_tar(fname, plat)
    to_dir, from_dir = PLATS
    fuse_trees(to_dir, from_dir)
    with working_directory(to_dir):
        with tarfile.open(out_fname, "w:gz") as tar:
            tar.add('usr', arcname=os.path.basename('usr'))
