#!/bin/bash
# dir="$@"
BUILD_SHASUM=$(dir='build/'; find "$dir" -type f -exec sha256sum {} \; | sed "s~$dir~~g" | LC_ALL=C sort -d | sha256sum)
tar --mtime='2015-10-21 00:00Z' --clamp-mtime -cf product.tar build/

export $BUILD_SHASUM
echo "$BUILD_SHASUM product.tar" | sha256sum --check --strict -;
