# Building OpenBLAS

This is a repository to trigger builds of OpenBLAS on Travis-CI and Appveyor.

The OpenBLAS libraries get uploaded to
https://3f23b170c54c2533c070-1c8a9b3114517dc5fe17b7c3f8c63a43.ssl.cf2.rackcdn.com/

A project using these libraries, for Manylinux or macOS, will need the
``gfortran-install`` submodule used here, from
https://github.com/MacPython/gfortran-install

There are some post-processing steps for the macOS builds, which are:

* Wait for the 32-bit and 64-bit builds to finish;
* Edit the `tools/fuse_openblas.py` script to set the relevant OpenBLAS
  commit, and macOS deployment version.
* Run that script, to download the 32-bit and 64-bit libraries, fuse them into
  dual-arch libraries, `intel` in the archive name.
* Upload this archive by hand, maybe using the web UI, to the Rackspace
  container.
