from pathlib import Path

from . import _init_openblas
from textwrap import dedent


_HERE = Path(__file__).resolve().parent

__all__ = ["get_include_dir", "get_lib_dir", "get_library", "get_pkg_config"]

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

def get_pkg_config():
    return f"""\
        libdir={_HERE}/lib
        includedir={_HERE}/include
        openblas_config= USE_64BITINT= DYNAMIC_ARCH=1 DYNAMIC_OLDER= NO_CBLAS= NO_LAPACK= NO_LAPACKE= NO_AFFINITY=1 USE_OPENMP= PRESCOTT MAX_THREADS=24
        version=0.3.23
        extralib=-lm -lpthread -lgfortran -lm -lpthread -lgfortran
        Name: openblas
        Description: OpenBLAS is an optimized BLAS library based on GotoBLAS2 1.13 BSD version
        Version: ${version}
        URL: https://github.com/xianyi/OpenBLAS
        Libs: -L${libdir} -lopenblas
        Libs.private: ${extralib}
        Cflags: -I${includedir}
        """

