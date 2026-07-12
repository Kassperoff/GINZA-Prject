#!/usr/bin/env bash
set -e
ARCH="$1"
OUT="$2"

git clone https://github.com/curl/curl.git curl_src
cd curl_src

./buildconf
./configure --host="$ARCH-linux-android" --with-ssl --disable-shared --enable-static
make -j4

mkdir -p "$OUT"
cp src/curl "$OUT/"
