#!bash
#
# Build a small archive that satisfies the handful of libgfortran runtime
# entry points OpenBLAS's Fortran LAPACK references, so that the resulting
# libscipy_openblas has no runtime dependency on libgfortran. Historically,
# some versions of libgfortran linked with libquadmath, but we do not need
# it here.
#
# Why this is worth doing:
#   * libquadmath is LGPL-2.1-or-later and, unlike libgfortran, carries no GCC
#     Runtime Library Exception, so shipping it in these wheels brings an
#     LGPL obligation along with it.
#   * it drops roughly 1MB (compressed) from every wheel that bundled both
#     libraries.
#   * it retired the libgfortran RPATH fixup in ci-repair-wheel.sh, which only
#     existed so a bundled libgfortran could find the bundled libquadmath
#     (auditwheel issue #451).
#
# The library needs exactly these symbols (verified with
# `nm -D --undefined-only` on the shipped wheels, on every Linux arch, and
# with `nm -u` on the shipped macOS dylibs, where the set is the same):
#
#   _gfortran_concat_string   always
#   _gfortran_etime           always
#   _gfortran_pow_r4_i8       INTERFACE64 builds only
#   _gfortran_pow_r8_i8       INTERFACE64 builds only
#
# The two pow entry points are taken verbatim as compiled objects out of a
# libgfortran.a from the same gcc release as the compiler (the toolchain's own
# on Linux, see the macOS note below).  They are fully self-contained -- zero
# undefined symbols -- so nothing else gets dragged in, and because they are
# the real implementation the results stay bit-for-bit identical to a build
# that links libgfortran dynamically.  That matters: the obvious-looking
# alternative of forcing the exponent to INTEGER(4) so gcc emits libgcc's
# __powidf2 instead is NOT equivalent, because __powidf2 evaluates
# 1/(x**|n|) and flushes subnormal results to zero where gfortran evaluates
# (1/x)**|n|.  In dgeequb that turns a tiny scale factor into a zero divisor.
#
# _gfortran_etime disappears entirely when LAPACK is built with TIMER=NONE,
# which selects the in-tree second_NONE.f / dsecnd_NONE.f.  The only
# behavioural consequence is that LAPACK's SECOND/DSECND return 0.0, which is
# already what OpenBLAS's own C_LAPACK build does.
#
# The libgfortran notice in tools/LICENSE_posix.txt has to
# stay: the objects taken out of libgfortran.a are now statically part of the
# library.
#
# Where the archive comes from -- every Linux/macOS target must have one:
#   * manylinux_2_28 (x86_64, i686, aarch64, ppc64le, s390x): the gcc-toolset
#     under /opt/rh bundles libgfortran.a -- ask the compiler, not /usr.
#   * musllinux_1_2: Alpine's gfortran package bundles it.
#   * manylinux_2_39 (riscv64): Rocky Linux builds on the system gcc, and the
#     Red Hat family keeps static libraries in separate *-static subpackages,
#     so the image has libgfortran.so but no libgfortran.a.  before_build
#     installs libgfortran-static (CRB repo, already enabled there).
#   * macOS: see the macOS note below.
#
# _gfortran_concat_string is the one entry point that is not self-contained in
# libgfortran.a (it lives in string_intrinsics.o, which pulls in
# _gfortrani_runtime_error and from there error.o and async.o -- neither of
# which is position-independent, so they cannot go into a shared library).  It
# is reimplemented in tools/gfortran_compat.c; see that file for provenance.

# The macOS story:
#
#   * The gfortran tarball in tools/gfortran_utils.sh ships libgfortran as a
#     dylib only, so there is no libgfortran.a to take the objects from.
#     The matching static archive is however published by the conda-forge
#     package that tarball was repackaged from, so
#     download_macos_libgfortran_a fetches that one archive, for the same gcc
#     11.3.0, and before_build points LIBGFORTRAN_A at it.  The pow objects in
#     it are self-contained and carry the same minimum macOS version the
#     wheels target (11.0 on arm64, 10.9 on x86_64), so nothing else about the
#     build changes.
#
#   * Keeping the compat symbols out of the dylib's export table needs no
#     -Wl,--exclude-libs equivalent: the dylib link already passes
#     -Wl,-exported_symbols_list,osx.def, an allow-list holding only the BLAS
#     and LAPACK names, so anything the compat archive brings in is unexported
#     already.  What macOS does need instead is -Wl,-dead_strip_dylibs,
#     because the dylib is linked by the gfortran driver, which appends
#     -lgfortran itself whatever FEXTRALIB says.  See the NO_LIBGFORTRAN block
#     in patches/0001-allow-building-without-libgfortran.patch.
#
# The conda-forge package matches the gfortran in tools/gfortran_utils.sh.
# Pinned by sha256, and to be bumped together with the tarball there -- the
# objects have to come from the same gcc release
function macos_libgfortran_pkg {
    # macos_libgfortran_pkg <plat>   echoes "<conda subdir>/<file> <sha256>"
    case "$1" in
        arm64)
            echo "osx-arm64/gfortran_impl_osx-arm64-11.3.0-h2a9d086_26.tar.bz2" \
                 "6fb7857fea4766466c5d3f22e15f78a006b9fdfb64da0556c659abe56deb714c"
            ;;
        x86_64)
            echo "osx-64/gfortran_impl_osx-64-11.3.0-h1f927f5_26.tar.bz2" \
                 "da0c80d2f0a088c91861a454b499c1f6486fd56a894b43aa8dc9ddd3954c606d"
            ;;
        *) return 1 ;;
    esac
}

# Fetch the static libgfortran and echo the path to it.  Only the
# one archive is extracted; the compiler in the package is not used, the
# toolchain from gfortran_utils.sh is.  Returns non-zero on any failure, which
# the caller treats as fatal.
function download_macos_libgfortran_a {
    local plat=$1
    local workdir=${2:-$PWD/build/libgfortran-$plat}
    local pkg sha
    if ! read -r pkg sha < <(macos_libgfortran_pkg "$plat"); then
        echo "gfortran_compat: no static libgfortran pinned for plat $plat" >&2
        return 1
    fi

    local archive="$workdir/lib/libgfortran.a"
    # Re-running before_build should not download it again.
    [ -f "$archive" ] && { echo "$archive"; return 0; }

    local base="$workdir/$(basename "$pkg")"
    mkdir -p "$workdir" || return 1
    if [ ! -e "$base" ]; then
        curl -L --fail -o "$base" \
            "https://conda.anaconda.org/conda-forge/$pkg" >&2 || return 1
    fi
    if [ "$(shasum -a 256 "$base" | cut -d' ' -f1)" != "$sha" ]; then
        echo "gfortran_compat: sha256 mismatch for $(basename "$pkg")" >&2
        return 1
    fi
    tar xjf "$base" -C "$workdir" lib/libgfortran.a >&2 || return 1
    [ -f "$archive" ] || return 1
    echo "$archive"
}

# Locate the static libgfortran to take the objects from.  Note that on the
# manylinux images the compiler is a gcc-toolset under /opt/rh, so searching
# /usr will not find it -- always ask the compiler.
function find_libgfortran_a {
    # An explicit LIBGFORTRAN_A wins; that is how before_build hands over the
    # archive it downloaded on macOS, where the compiler has none to offer.
    if [ -n "$LIBGFORTRAN_A" ]; then
        [ -f "$LIBGFORTRAN_A" ] && echo "$LIBGFORTRAN_A" && return 0
        echo "gfortran_compat: LIBGFORTRAN_A=$LIBGFORTRAN_A does not exist" >&2
        return 1
    fi
    local fc="${FC:-gfortran}"
    local path
    path=$("$fc" -print-file-name=libgfortran.a 2>/dev/null)
    # -print-file-name echoes the bare name back when the file is not found
    case "$path" in
        /*) [ -f "$path" ] && echo "$path" && return 0 ;;
    esac
    return 1
}

# build_gfortran_compat <workdir> <interface64>
#
# On success, creates <workdir>/libgfortran_compat.a and echoes its path.
# Returns non-zero if this toolchain cannot support the approach, which fails
# the build -- every message below says which check refused it.
function build_gfortran_compat {
    local workdir=$1
    local interface64=${2:-0}
    local repo_root
    repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

    # Spellings that differ between ELF and Mach-O.  BU is the symbol prefix
    # the object format adds to C names -- none on ELF, an underscore on
    # Mach-O, where the archive therefore spells the entry point
    # __gfortran_pow_r8_i8.
    local bu="" shared_flag="-shared" shared_ext="so"
    case "$(uname -s)" in
        Linux) ;;
        Darwin) bu="_"; shared_flag="-dynamiclib"; shared_ext="dylib" ;;
        *) echo "gfortran_compat: unsupported on $(uname -s)" >&2; return 1 ;;
    esac

    local archive
    if ! archive=$(find_libgfortran_a); then
        echo "gfortran_compat: no static libgfortran.a for ${FC:-gfortran}" >&2
        return 1
    fi
    echo "gfortran_compat: using $archive" >&2

    rm -rf "$workdir"
    mkdir -p "$workdir"
    local here=$PWD
    cd "$workdir" || return 1

    # Only the INTERFACE64 build needs the pow entry points: they come from
    # x**n where -fdefault-integer-8 has made n an INTEGER(8).  With the
    # default 4-byte integer gcc expands x**n inline instead.
    local wanted=""
    if [ "$interface64" = "1" ]; then
        wanted="_gfortran_pow_r4_i8 _gfortran_pow_r8_i8"
    fi

    local sym member
    for sym in $wanted; do
        # `|| true`: grep exits 1 when the member is absent, and under
        # `set -e` that would abort here with no explanation instead of
        # reaching the message below.
        member=$(nm -A --defined-only "$archive" 2>/dev/null \
                 | grep " ${bu}${sym}\$" | head -1 | cut -d: -f2 || true)
        if [ -z "$member" ]; then
            echo "gfortran_compat: $sym not found in $archive" >&2
            cd "$here"; return 1
        fi
        if ! ar x "$archive" "$member" 2>/dev/null; then
            echo "gfortran_compat: cannot extract $member" >&2
            cd "$here"; return 1
        fi
        # Refuse anything that is not self-contained: a member with undefined
        # symbols would drag in libgfortran internals (and possibly non-PIC
        # objects), which is exactly what this approach avoids.
        #
        # Linker-synthesized symbols do not count.  On ppc64le every object
        # that touches the TOC references .TOC., which ld provides itself --
        # treating that as a dependency rejected a member that is in fact
        # perfectly self-contained.  The shared-link check below remains the
        # real gate: anything genuinely unresolvable fails there instead.
        local undef
        undef=$(nm --undefined-only "$member" | awk '{print $2}' \
                | grep -vxF -e '.TOC.' -e '_GLOBAL_OFFSET_TABLE_' \
                | tr '\n' ' ' || true)
        if [ -n "$undef" ]; then
            echo "gfortran_compat: $member is not self-contained: $undef" >&2
            cd "$here"; return 1
        fi
        echo "gfortran_compat: took $member for $sym" >&2
    done

    # The hand-written part.
    if ! ${CC:-gcc} ${CFLAGS} -O2 -fPIC -fvisibility=hidden \
            -c "$repo_root/tools/gfortran_compat.c" -o gfortran_compat.o; then
        echo "gfortran_compat: failed to compile gfortran_compat.c" >&2
        cd "$here"; return 1
    fi

    # Prove the objects can actually go into a shared library before the
    # OpenBLAS link tries it.  This is the check that rules out cherry-picking
    # libgfortran's error.o/async.o, which carry TLS initial-exec relocations.
    # CFLAGS carries the -arch of a cross build, without which this would
    # reject perfectly good objects of the other architecture.
    if ! ${CC:-gcc} ${CFLAGS} $shared_flag -o pictest.$shared_ext ./*.o 2>pictest.err; then
        echo "gfortran_compat: objects are not usable in a shared library:" >&2
        sed 's/^/  /' pictest.err >&2
        cd "$here"; return 1
    fi
    rm -f pictest.$shared_ext pictest.err

    rm -f libgfortran_compat.a
    ar crs libgfortran_compat.a ./*.o || { cd "$here"; return 1; }
    cd "$here"
    echo "$workdir/libgfortran_compat.a"
}

# fortran_runtime_deps <library>
#
# Echo the libgfortran/libquadmath entries in a library's dependency list, or
# nothing if there are none.
function fortran_runtime_deps {
    local lib=$1
    if [ "$(uname -s)" == "Darwin" ]; then
        otool -L "$lib" | tail -n +2 | awk '{print $1}' \
            | grep -i 'gfortran\|quadmath' || true
    else
        readelf -d "$lib" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' \
            | grep -i 'gfortran\|quadmath' || true
    fi
}

# assert_no_fortran_runtime <library> ...
#
# Fail the build if a built library still depends on the Fortran runtime.
# This is the tripwire for the whole approach: if a future OpenBLAS or LAPACK
# release starts referencing a libgfortran entry point we do not provide, the
# link fails outright; if something re-adds -lgfortran to the link line, this
# catches it.
function assert_no_fortran_runtime {
    local lib status=0 checked=0
    for lib in "$@"; do
        # Callers pass globs covering both .so and .dylib; an unmatched glob
        # arrives here as a literal string, so skip anything that is not a
        # file rather than treating it as a failure.
        [ -f "$lib" ] || continue
        checked=$((checked + 1))
        local undef bad
        if [ "$(uname -s)" == "Darwin" ]; then
            undef=$(nm -u "$lib" 2>/dev/null | grep -o '_gfortran_[A-Za-z0-9_]*' | sort -u || true)
        else
            undef=$(nm -D --undefined-only "$lib" 2>/dev/null \
                    | grep -o '_gfortran_[A-Za-z0-9_]*' | sort -u || true)
        fi
        bad=$(fortran_runtime_deps "$lib")
        if [ -n "$bad" ]; then
            echo "FAIL: $(basename "$lib") still links the Fortran runtime:" >&2
            echo "$bad" | sed 's/^/  /' >&2
            status=1
        fi
        if [ -n "$undef" ]; then
            echo "FAIL: $(basename "$lib") has unresolved libgfortran symbols:" >&2
            echo "$undef" | sed 's/^/  /' >&2
            status=1
            continue
        fi
        [ -z "$bad" ] && echo "OK: $(basename "$lib") has no Fortran runtime dependency"
    done
    # Refuse to pass silently when the globs matched nothing at all -- that
    # would make this tripwire useless the day a path or name changes.
    if [ "$checked" = "0" ]; then
        echo "FAIL: assert_no_fortran_runtime found no library to check in: $*" >&2
        return 1
    fi
    return $status
}
