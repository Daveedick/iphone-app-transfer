#!/bin/bash
# Source from build/test tooling; never use an existing account/session namespace.
app_transfer_go_root="${APP_TRANSFER_GO_ROOT:-$app_transfer_root/.build/go}"
export GOPATH="$app_transfer_go_root"
export GOMODCACHE="$app_transfer_go_root/pkg/mod"
export GOCACHE="$app_transfer_go_root/cache"
export GOTOOLCHAIN=local
export CLANG_MODULE_CACHE_PATH="$app_transfer_go_root/clang-cache"
mkdir -p "$GOMODCACHE" "$GOCACHE" "$CLANG_MODULE_CACHE_PATH"
