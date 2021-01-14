#!/bin/sh

set -ex

echo abc
if grep BUFFERSIZE OpenBLAS/Makefile.system; then
    echo Patched!
else
    (cd OpenBLAS; patch -u << "EOF"
diff --git a/Makefile.system b/Makefile.system
index 5adde36d..79e93ec0 100644
--- a/Makefile.system
+++ b/Makefile.system
@@ -1256,6 +1256,10 @@ CCOMMON_OPT	 += -DUSE_PAPI
 EXTRALIB	 += -lpapi -lperfctr
 endif
 
+ifdef BUFFERSIZE
+CCOMMON_OPT  += -DBUFFERSIZE=$(BUFFERSIZE)
+endif
+
 ifdef DYNAMIC_THREADS
 CCOMMON_OPT	 += -DDYNAMIC_THREADS
 endif
EOF
)
fi

