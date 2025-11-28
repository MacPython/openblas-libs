# this file come from https://github.com/MacPython/gfortran-install
# Follow the license below


# gfortran-install license
# Copyright 2016-2021 Matthew Brett, Isuru Fernando, Matti Picus

# Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

# 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

# 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


# Bash utilities for use with gfortran

ARCHIVE_SDIR="${ARCHIVE_SDIR:-archives}"

GF_UTIL_DIR=$(dirname "${BASH_SOURCE[0]}")

function get_distutils_platform {
    # Report platform as in form of distutils get_platform.
    # This is like the platform tag that pip will use.
    # Modify fat architecture tags on macOS to reflect compiled architecture

    # Deprecate this function once get_distutils_platform_ex is used in all
    # downstream projects
    local plat=$1
    case $plat in
        i686|x86_64|arm64|universal2|intel|aarch64|s390x|ppc64le) ;;
        *) echo Did not recognize plat $plat; return 1 ;;
    esac
    local uname=${2:-$(uname)}
    if [ "$uname" != "Darwin" ]; then
        if [ "$plat" == "intel" ]; then
            echo plat=intel not allowed for Manylinux
            return 1
        fi
        echo "manylinux1_$plat"
        return
    fi
    # macOS 32-bit arch is i386
    [ "$plat" == "i686" ] && plat="i386"
    local target=$(echo $MACOSX_DEPLOYMENT_TARGET | tr .- _)
    echo "macosx_${target}_${plat}"
}

function get_distutils_platform_ex {
    # Report platform as in form of distutils get_platform.
    # This is like the platform tag that pip will use.
    # Modify fat architecture tags on macOS to reflect compiled architecture
    # For non-darwin, report manylinux version
    local plat=$1
    local mb_ml_ver=${MB_ML_VER:-1}
    case $plat in
        i686|x86_64|arm64|universal2|intel|aarch64|s390x|ppc64le) ;;
        *) echo Did not recognize plat $plat; return 1 ;;
    esac
    local uname=${2:-$(uname)}
    if [ "$uname" != "Darwin" ]; then
        if [ "$plat" == "intel" ]; then
            echo plat=intel not allowed for Manylinux
            return 1
        fi
        echo "manylinux${mb_ml_ver}_${plat}"
        return
    fi
    # macOS 32-bit arch is i386
    [ "$plat" == "i686" ] && plat="i386"
    local target=$(echo $MACOSX_DEPLOYMENT_TARGET | tr .- _)
    echo "macosx_${target}_${plat}"
}

function get_macosx_target {
    # Report MACOSX_DEPLOYMENT_TARGET as given by distutils get_platform.
    python3 -c "import sysconfig as s; print(s.get_config_vars()['MACOSX_DEPLOYMENT_TARGET'])"
}

function check_gfortran {
    # Check that gfortran exists on the path
    if [ -z "$(which gfortran)" ]; then
        echo Missing gfortran
        exit 1
    fi
}

function get_gf_lib_for_suf {
    local suffix=$1
    local prefix=$2
    local plat=${3:-$PLAT}
    local uname=${4:-$(uname)}
    if [ -z "$prefix" ]; then echo Prefix not defined; exit 1; fi
    local plat_tag=$(get_distutils_platform_ex $plat $uname)
    if [ -n "$suffix" ]; then suffix="-$suffix"; fi
    local fname="$prefix-${plat_tag}${suffix}.tar.gz"
    local out_fname="${ARCHIVE_SDIR}/$fname"
    [ -s $out_fname ] || (echo "$out_fname is empty"; exit 24)
    echo "$out_fname"
}

if [ "$(uname)" == "Darwin" ]; then
    mac_target=${MACOSX_DEPLOYMENT_TARGET:-$(get_macosx_target)}
    export MACOSX_DEPLOYMENT_TARGET=$mac_target
    # Keep this for now as some builds might depend on this being
    # available before install_gfortran is called
    export GFORTRAN_SHA=c469a420d2d003112749dcdcbe3c684eef42127e
    # Set SDKROOT env variable if not set
    export SDKROOT=${SDKROOT:-$(xcrun --show-sdk-path)}

    function download_and_unpack_gfortran {
	local arch=$1
	local type=$2
        curl -L -O https://github.com/isuruf/gcc/releases/download/gcc-11.3.0-2/gfortran-darwin-${arch}-${type}.tar.gz
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
	esac
        if [[ "$(shasum gfortran-darwin-${arch}-${type}.tar.gz)" != "${GFORTRAN_SHA}  gfortran-darwin-${arch}-${type}.tar.gz" ]]; then
            echo "shasum mismatch for gfortran-darwin-${arch}-${type}"
            exit 1
        fi
        if [! -d /opt/gfortran ]; then
            sudo mkdir -p /opt/gfortran
            sudo chmod 777 /opt/gfortran
        cp "gfortran-darwin-${arch}-${type}.tar.gz" /opt/goftran/gfortran-darwin-${arch}-${type}.tar.gz
        pushd /opt/gfortran
            tar -xvf gfortran-darwin-${arch}-${type}.tar.gz
            rm gfortran-darwin-${arch}-${type}.tar.gz
        popd
	fi
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
        check_gfortran
        if [[ "${PLAT:-}" == "universal2"]]; then
            install_arm64_cross_gfortran
        fi
    }

    function get_gf_lib {
        # Get lib with gfortran suffix
        get_gf_lib_for_suf "gf_${GFORTRAN_SHA:0:7}" $@
    }
else
    function install_gfortran {
        # No-op - already installed on manylinux image
        check_gfortran
    }

    function get_gf_lib {
        # Get library with no suffix
        get_gf_lib_for_suf "" $@
    }
fi
