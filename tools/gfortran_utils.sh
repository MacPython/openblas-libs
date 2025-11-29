#!bash
# this file come from https://github.com/MacPython/gfortran-install
# Follow the license below


# gfortran-install license
# Copyright 2016-2021 Matthew Brett, Isuru Fernando, Matti Picus

# Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

# 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

# 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


# Bash utilities for use with gfortran

if [ "$(uname)" == "Darwin" ]; then
    # Set SDKROOT env variable if not set
    export SDKROOT=${SDKROOT:-$(xcrun --show-sdk-path)}

    function download_and_unpack_gfortran {
        local arch=$1
        local type=$2
        case ${arch}-${type} in
            arm64-native)
                export GFORTRAN_SHA=0d5c118e5966d0fb9e7ddb49321f63cac1397ce8
            ;;
            arm64-cross)
                export GFORTRAN_SHA=527232845abc5af21f21ceacc46fb19c190fe804
            ;;
            x86_64-native)
                export GFORTRAN_SHA=c469a420d2d003112749dcdcbe3c684eef42127e
            ;;
            x86_64-cross)
                export GFORTRAN_SHA=107604e57db97a0ae3e7ca7f5dd722959752f0b3
            ;;
            *)
                echo unknown ${arch}-${type}
                exit 1
            ;;
        esac
        if [[ ! -e gfortran-darwin-${arch}-${type}.tar.gz ]]; then
            curl -L -O https://github.com/isuruf/gcc/releases/download/gcc-11.3.0-2/gfortran-darwin-${arch}-${type}.tar.gz
        fi
        if [[ "$(shasum gfortran-darwin-${arch}-${type}.tar.gz)" != "${GFORTRAN_SHA}  gfortran-darwin-${arch}-${type}.tar.gz" ]]; then
            echo "shasum mismatch for gfortran-darwin-${arch}-${type}"
            exit 1
        fi
        if [[ ! -d /opt/gfortran ]]; then
            sudo mkdir -p /opt/gfortran
            sudo chmod 777 /opt/gfortran
        fi
        cp "gfortran-darwin-${arch}-${type}.tar.gz" /opt/gfortran/gfortran-darwin-${arch}-${type}.tar.gz
        pushd /opt/gfortran
        tar -xvf gfortran-darwin-${arch}-${type}.tar.gz
        rm gfortran-darwin-${arch}-${type}.tar.gz
        popd
    }

    function install_arm64_cross_gfortran {
	    download_and_unpack_gfortran arm64 cross
        export FC_ARM64="$(find /opt/gfortran-darwin-arm64-cross/bin -name "*-gfortran")"
        local libgfortran="$(find /opt/gfortran-darwin-arm64-cross/lib -name libgfortran.dylib)"
        local libdir=$(dirname $libgfortran)

        export FC_ARM64_LDFLAGS="-L$libdir -Wl,-rpath,$libdir"
        if [[ "${PLAT:-}" == "arm64" ]]; then
            export FC=$FC_ARM64
        fi
    }

    function install_gfortran {
        download_and_unpack_gfortran $(uname -m) native
        if [[ "${PLAT:-}" == "universal2" ]]; then
            install_arm64_cross_gfortran
        fi
    }

else
    function install_gfortran {
        # No-op - already installed on manylinux image
        :
    }
fi
