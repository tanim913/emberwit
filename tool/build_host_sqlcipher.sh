#!/usr/bin/env bash
# Builds SQLCipher as a shared library for running database tests on a Linux
# development machine whose glibc is older than the prebuilt binaries need
# (for example Ubuntu 20.04).
#
# Usage: tool/build_host_sqlcipher.sh [install-dir]   (default ~/.local/sqlcipher)
# Then:  export LD_LIBRARY_PATH=<install-dir>/lib:$LD_LIBRARY_PATH
#
# Newer distributions (and CI) can simply `apt install libsqlcipher-dev`.
# Needs: git, a C compiler, make, tclsh, OpenSSL headers (libssl-dev).
# SQLCipher 4.6.x supports OpenSSL 1.1 and 3; its file format (4.x) is the
# same as the SQLCipher shipped in the Android and iOS apps.
set -euo pipefail
prefix="${1:-$HOME/.local/sqlcipher}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git -c advice.detachedHead=false clone -q --depth 1 --branch v4.6.1 \
  https://github.com/sqlcipher/sqlcipher.git "$work/sqlcipher"
cd "$work/sqlcipher"
./configure --enable-tempstore=yes \
  CFLAGS="-DSQLITE_HAS_CODEC -DSQLITE_TEMP_STORE=2 -O2" LDFLAGS="-lcrypto" >/dev/null
make -j"$(getconf _NPROCESSORS_ONLN)" >/dev/null
mkdir -p "$prefix/lib"
cp -P .libs/libsqlcipher.so* "$prefix/lib/"
echo "Installed to $prefix/lib. Run: export LD_LIBRARY_PATH=$prefix/lib:\$LD_LIBRARY_PATH"
