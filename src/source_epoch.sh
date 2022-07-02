#!/usr/bin/env bash
DATE_FMT="+%Y-%m-%d"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(date +%s)}"
BUILD_DATE=$(date -u -d "@$SOURCE_DATE_EPOCH" "$DATE_FMT" 2>/dev/null || date -u -r "$SOURCE_DATE_EPOCH" "$DATE_FMT" 2>/dev/null || date -u "$DATE_FMT")
echo $BUILD_DATE
