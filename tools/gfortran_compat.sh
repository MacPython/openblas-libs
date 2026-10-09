#!bash
#
# Build a small archive that satisfies the handful of libgfortran runtime
# entry points OpenBLAS's Fortran LAPACK references, so that the resulting
# libscipy_openblas has no runtime dependency on libgfortran -- and therefore
# none on libquadmath either, which is only ever pulled in as a dependency of
# libgfortran itself.
#
# Why this is worth doing:
#   * libquadmath is LGPL-2.1-or-later and, unlike libgfortran, carries no GCC
#     Runtime Library Exception, so shipping it in these wheels brings an
#     LGPL obligation along with it.
#   * it drops roughly 1MB (compressed) from every wheel that currently
#     bundles both libraries.
#   * it removes the need for the libgfortran RPATH fixup in
#     ci-repair-wheel.sh, which only exists so the bundled libgfortran can
#     find the bundled libquadmath (auditwheel issue #451).
#
# The library needs exactly these symbols (verified with
# `nm -D --undefined-only` on the shipped wheels, on every Linux arch):
#
#   _gfortran_concat_string   always
#   _gfortran_etime           always
#   _gfortran_pow_r4_i8       INTERFACE64 builds only
#   _gfortran_pow_r8_i8       INTERFACE64 builds only
#
# The two pow entry points are taken verbatim as compiled objects out of the
# toolchain's own libgfortran.a.  They are fully self-contained -- zero
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
# Note on the license notices: tools/build_prepare_wheel.sh appends a single
# tools/LICENSE_linux.txt to every Linux wheel, and the platforms not yet
# converted still bundle libgfortran and libquadmath.  The notices for both
# therefore have to stay until every platform is converted -- listing a
# library that is no longer shipped is harmless, dropping one that still is
# would not be.
#
# _gfortran_concat_string is the one entry point that is not self-contained in
# libgfortran.a (it lives in string_intrinsics.o, which pulls in
# _gfortrani_runtime_error and from there error.o and async.o -- neither of
# which is position-independent, so they cannot go into a shared library).  It
# is reimplemented in tools/gfortran_compat.c; see that file for provenance.

# Linux only for now.  The blocker on macOS is the link, not this script:
# keeping the compat symbols out of the dylib's export table needs
# -Wl,--exclude-libs, and ld64 has no equivalent (the nearest is -load_hidden
# / -hidden-l).  Without it the two _gfortran_pow_* symbols would be exported
# from libscipy_openblas.dylib and could interpose on a real libgfortran in
# the same process.  Enabling macOS also means checking that the gfortran
# tarball before_build downloads ships a static libgfortran.a at all, and
# using llvm-nm/-dynamiclib spellings below.  Refused explicitly rather than
# left to fail confusingly at link time.
#
# Locate the toolchain's static libgfortran.  Note that on the manylinux
# images the compiler is a gcc-toolset under /opt/rh, so searching /usr will
# not find it -- always ask the compiler.
function find_libgfortran_a {
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
# Returns non-zero if this toolchain cannot support the approach, so the
# caller can fall back to linking libgfortran normally.
function build_gfortran_compat {
    local workdir=$1
    local interface64=${2:-0}
    local repo_root
    repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

    if [ "$(uname -s)" != "Linux" ]; then
        echo "gfortran_compat: only supported on Linux so far (see above)" >&2
        return 1
    fi

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
        # `set -e` that would abort the build instead of returning non-zero
        # here and letting the caller fall back to linking libgfortran.
        member=$(nm -A --defined-only "$archive" 2>/dev/null \
                 | grep " $sym\$" | head -1 | cut -d: -f2 || true)
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
    if ! ${CC:-gcc} -shared -o pictest.so ./*.o 2>pictest.err; then
        echo "gfortran_compat: objects are not usable in a shared library:" >&2
        sed 's/^/  /' pictest.err >&2
        cd "$here"; return 1
    fi
    rm -f pictest.so pictest.err

    rm -f libgfortran_compat.a
    ar crs libgfortran_compat.a ./*.o || { cd "$here"; return 1; }
    cd "$here"
    echo "$workdir/libgfortran_compat.a"
}

# fortran_runtime_deps <library>
#
# Echo the libgfortran/libquadmath entries in a library's dependency list, or
# nothing if there are none.  Used both by the assertion below and by
# ci-test.sh, which needs to know what the build actually produced rather than
# what it intended: on a toolchain that cannot support the compat archive
# build_gfortran_compat falls back, and the wheel then legitimately still
# bundles the runtime.
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
