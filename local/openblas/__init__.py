from pathlib import Path

from . import _init_openblas


_HERE = Path(__file__).resolve().parent


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


def get_include_dir():
    return str(_HERE / "include")


def get_lib_dir():
    return str(_HERE / "lib")


def get_library():
    return "openblas_python"
