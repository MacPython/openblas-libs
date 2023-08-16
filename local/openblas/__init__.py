import os
from pathlib import Path
import sys
from textwrap import dedent


if sys.platform == "win32":
    os.add_dll_directory(get_lib_dir())


from . import _init_openblas


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
    return os.path.join(_HERE, "include")


def get_lib_dir():
    return os.path.join(_HERE, "lib")


def get_library():
    if sys.platform == "win32":
        libs = [x for x in os.listdir(get_lib_dir()) if x.endswith(".lib")]
        return os.path.splitext(libs[0])[0]
    else:
        return "openblas_python"

def get_pkg_config():
    if sys.platform == "win32":
        extralib = "-defaultlib:advapi32 -lgfortran -defaultlib:advapi32 -lgfortran"
    else:
        extralib = "-lm -lpthread -lgfortran -lm -lpthread -lgfortran"
    return f"""\
        libdir={get_lib_dir()}
        includedir={get_include_dir()}
        openblas_config= {openblas_config}
        version={openblas_config.split(" ")[1]}
        extralib={extralib}
        Name: openblas
        Description: OpenBLAS is an optimized BLAS library based on GotoBLAS2 1.13 BSD version
        Version: ${{version}}
        URL: https://github.com/xianyi/OpenBLAS
        Libs: -L${libdir} -l{get_library()}
        Libs.private: ${extralib}
        Cflags: -I${includedir}
        """
