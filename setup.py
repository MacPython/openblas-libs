import os
import sys
from setuptools import setup, Extension
from wheel.bdist_wheel import bdist_wheel


mydir = os.path.abspath(os.path.dirname(__file__))


class bdist_wheel_abi3(bdist_wheel):
    def get_tag(self):
        python, abi, plat = bdist_wheel.get_tag(self)
        return python, "abi3", plat


# TODO: determine if we are building 64- or 32- bit interfaces
use_64=True
if use_64:
    macros = [("SUFFIX", "64_")]
else:
    macros = []

if sys.implementation.name == "cpython":
    cmdclass = {"bdist_wheel": bdist_wheel_abi3}
    py_limited_api = {"py_limited_api": True}
    macros.append(('Py_LIMITED_API', '0x03070000'))
else:
    cmdclass = {}
    py_limited_api = {}

library_dir=os.path.join(mydir, 'local', 'openblas', 'lib')
if sys.platform == "win32":
    libnames = [x for x in os.listdir(library_dir) if x.endswith(".lib")]
else:
    libnames = [x for x in os.listdir(library_dir) if x.startswith("libopenblas")]
setup(
    cmdclass=cmdclass,
    ext_modules=[Extension(
        "openblas._init_openblas", ["src/_init_openblas.c"],
        libraries=["openblas_python"],
        library_dirs=[library_dir],
        extra_link_args=["-Wl,-rpath,$ORIGIN/lib"],
        define_macros=macros,
        **py_limited_api
    )],
)
