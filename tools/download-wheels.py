#!/usr/bin/env python3
"""
Script to download NumPy wheels from the Anaconda staging area.

Usage::

    $ ./tools/download-wheels.py <version> -w <optional-wheelhouse>

The default wheelhouse is ``release/installers``.

Dependencies
------------

- beautifulsoup4
- urllib3

Examples
--------

While in the repository root::

    $ python tools/download-wheels.py 1.19.0
    $ python tools/download-wheels.py 1.19.0 -w ~/wheelhouse

"""
import os
import re
import shutil
import argparse

import urllib3
from bs4 import BeautifulSoup

__version__ = "0.1"

# Edit these for other projects.
SIMPLE_INDEX = "https://pypi.anaconda.org/scientific-python-nightly-wheels/simple"
BASE = "https://pypi.anaconda.org"


def get_wheel_names(package, version):
    """ Get wheel names from Anaconda HTML directory.

    This looks in the Anaconda multibuild-wheels-staging page and
    parses the HTML to get all the wheel names for a release version.

    Parameters
    ----------
    version : str
        The release version. For instance, "1.18.3".

    """
    http = urllib3.PoolManager(cert_reqs="CERT_REQUIRED")
    index_url = f"{SIMPLE_INDEX}/{package}"
    print(f"looking in {index_url}")
    index_html = http.request("GET", index_url)
    soup = BeautifulSoup(index_html.data, "html.parser")
    breakpoint()
    return [xxx['href'] for xxx in soup.find_all('a', href=True) if version in str(xxx)]


def download_wheels(package, version, wheelhouse, test=False):
    """Download release wheels.

    The release wheels for the given package version are downloaded
    into the given directory.

    Parameters
    ----------
    package : str
        The package to download, scipy-openblas32 or scipy-openblas64
    version : str
        The release version. For instance, "1.18.3".
    wheelhouse : str
        Directory in which to download the wheels.

    """
    http = urllib3.PoolManager(cert_reqs="CERT_REQUIRED")
    wheel_names = get_wheel_names(package, version)

    for i, wheel_name in enumerate(wheel_names):
        wheel_url = f"{BASE}/{wheel_name}"
        wheel_file = wheel_name.split('/')[-1]
        wheel_path = os.path.join(wheelhouse, wheel_file)
        with open(wheel_path, "wb") as f:
            with http.request("GET", wheel_url, preload_content=False,) as r:
                info = r.info()
                length = int(info.get('Content-Length', '0'))
                if length == 0:
                    length = 'unknown size'
                else:
                    length = f"{(length / 1024 / 1024):.2f}MB"
                print(f"{i + 1:<4}{wheel_file} {length}")
                if not test:
                    shutil.copyfileobj(r, f)
    print(f"\nTotal files downloaded: {len(wheel_names)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--package",
        required=True,
        help="package to download.")
    parser.add_argument(
        "--version",
        required=True,
        help="package version to download.")
    parser.add_argument(
        "-w", "--wheelhouse",
        default=os.path.join(os.getcwd(), "release", "installers"),
        help="Directory in which to store downloaded wheels\n"
             "[defaults to <cwd>/release/installers]")
    parser.add_argument(
        "-t", "--test",
        action = 'store_true',
        help="only list available wheels, do not download")

    args = parser.parse_args()

    wheelhouse = os.path.expanduser(args.wheelhouse)
    if not os.path.isdir(wheelhouse):
        raise RuntimeError(
            f"{wheelhouse} wheelhouse directory is not present."
            " Perhaps you need to use the '-w' flag to specify one.")

    download_wheels(args.package, args.version, wheelhouse, test=args.test)
