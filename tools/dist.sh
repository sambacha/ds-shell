#!/bin/bash
dir="$@"; find "$dir" -type f -exec sha256sum {} \; | gsed "s~$dir~~g" | LC_ALL=C sort -d | sha256sum
