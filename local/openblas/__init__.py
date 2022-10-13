import os
from . import _init_openblas

# Use importlib.metadata to single-source the version

try:
    # importlib.metadata is present in Python 3.8 and later
    import importlib.metadata as importlib_metadata
except ImportError:
    # use the shim package importlib-metadata pre-3.8
    import importlib_metadata as importlib_metadata

try:
    # __package__ allows for the case where __name__ is "__main__"
    __version__ = importlib_metadata.version(__package__ or __name__)
except importlib_metadata.PackageNotFoundError:
    __version__ = "0.0.0"

openblas_config = _init_openblas.get_config()

path_to_so = os.path.join(os.path.dirname(__file__), 'lib', 'libopenblas64_.so')


def open_so():
    _init_openblas.open_so(path_to_so)


