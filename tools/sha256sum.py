#!/usr/bin/env python3

import hashlib
import sys
 
filename = sys.argv[1]
sha256_hash = hashlib.sha256()
with open(filename,"rb") as f:
    # Read and update hash string value in blocks
    for byte_block in iter(lambda: f.read(32768),b""):
        sha256_hash.update(byte_block)
    print(sha256_hash.hexdigest())

