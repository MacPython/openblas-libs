/*
 * Replacement for the one libgfortran runtime entry point that OpenBLAS's
 * Fortran LAPACK references and that cannot be lifted straight out of
 * libgfortran.a as a self-contained object.
 *
 * The other entry points LAPACK needs are handled without any hand-written
 * code at all (see tools/gfortran_compat.sh):
 *
 *   _gfortran_pow_r4_i8, _gfortran_pow_r8_i8
 *       taken verbatim as compiled objects out of the toolchain's
 *       libgfortran.a; both are fully self-contained.
 *   _gfortran_etime
 *       not referenced at all once LAPACK is built with TIMER=NONE, which
 *       selects the in-tree second_NONE.f / dsecnd_NONE.f.
 *
 * Provenance of the code below: the semantics follow the `s_cat` helper of
 * the f2c prologue already vendored in the OpenBLAS tree -- see the top of
 * OpenBLAS/lapack-netlib/INSTALL/dsecnd_NONE.c -- distributed under LAPACK's
 * BSD-3 terms, and what OpenBLAS's own C_LAPACK build already uses to
 * evaluate Fortran CHARACTER concatenation.  No GCC or libgfortran source
 * was consulted.
 *
 * In OpenBLAS's LAPACK the only call shape is the two-character OPTS
 * argument of ILAENV, e.g.
 *
 *     NB = ILAENV( 1, 'DORMQR', SIDE // TRANS, M, N, K, -1 )
 *
 * where the destination length is exactly len1 + len2, so neither the
 * truncation nor the blank-padding branch is reachable from LAPACK.  Both
 * are implemented anyway so the function matches Fortran CHARACTER
 * assignment semantics for any caller.
 */

#include <stddef.h>
#include <string.h>

/*
 * gfortran passes CHARACTER lengths as a signed integer the width of a
 * pointer (gcc >= 8; the GFORTRAN_8 ABI version node).
 *
 * Hidden visibility keeps the symbol out of the shared library's export
 * table: it is an implementation detail of this build, not part of
 * OpenBLAS's ABI, and must not interpose on a real libgfortran that happens
 * to be loaded into the same process.  A hidden definition still satisfies
 * the references from the LAPACK objects linked alongside it.
 */
__attribute__((visibility("hidden")))
void _gfortran_concat_string(ptrdiff_t destlen, char *dest,
                             ptrdiff_t len1, const char *s1,
                             ptrdiff_t len2, const char *s2);

void _gfortran_concat_string(ptrdiff_t destlen, char *dest,
                             ptrdiff_t len1, const char *s1,
                             ptrdiff_t len2, const char *s2)
{
    ptrdiff_t nc;

    nc = (len1 < destlen) ? len1 : destlen;
    memcpy(dest, s1, (size_t) nc);
    dest += nc;
    destlen -= nc;

    nc = (len2 < destlen) ? len2 : destlen;
    memcpy(dest, s2, (size_t) nc);
    dest += nc;
    destlen -= nc;

    if (destlen > 0) {
        memset(dest, ' ', (size_t) destlen);
    }
}
