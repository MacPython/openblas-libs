# Needs:
# $INTERFACE64 ("1" or "0")
# $PLAT (x86_64, i686, arm64, aarch64, s390x, ppc64le)

$PYTHON -m pip wheel -w dist -v .

