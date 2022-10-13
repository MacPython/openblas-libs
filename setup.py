import os
from setuptools import setup, Extension

mydir = os.path.abspath(os.path.dirname(__file__))

# TODO: determine if we are building 64- or 32- bit interfaces
use_64=True
if use_64:
    libraries = ["openblas64_",]
    macros = [("SUFFIX", "64_")]
else:
    libraries = ["openblas",]
    macros = []

setup(
    ext_modules=[Extension(
            "openblas._init_openblas", ["src/_init_openblas.c"],
            libraries=libraries,
            library_dirs=[os.path.join(mydir, 'local', 'openblas', 'lib'),],
            extra_link_args=["-Wl,-rpath,$ORIGIN/lib"],
            define_macros=macros,
    )],
)
