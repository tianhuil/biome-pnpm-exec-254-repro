#!/usr/bin/env bash
# Detects the intermittent biome exit-254 failure window.
#
# Each iteration compares the SAME binary invoked two ways:
#   1. direct:  ./node_modules/.bin/biome --version   (sh shim -> JS wrapper -> native)
#   2. pnpm:    pnpm exec biome --version             (same, but spawned from pnpm)
#
# On an affected machine during a "wedged window", the pnpm-spawned form
# exits 254 with:
#   [warn] Linter process terminated abnormally (possibly out of memory)
# while the direct form passes. Windows come and go over minutes.
#
# Usage: ./repro.sh [iterations]   (default 30)
set -u
N=${1:-30}
direct_pass=0; direct_fail=0; pnpm_pass=0; pnpm_fail=0
echo "biome $(NO_COLOR=1 ./node_modules/.bin/biome --version 2>/dev/null | grep -o '[0-9][0-9.]*' | head -1), pnpm $(pnpm --version), node $(node --version), $N iterations"
for i in $(seq 1 "$N"); do
  if ./node_modules/.bin/biome --version >/dev/null 2>&1; then direct_pass=$((direct_pass+1)); else direct_fail=$((direct_fail+1)); fi
  if pnpm exec biome --version >/dev/null 2>&1; then pnpm_pass=$((pnpm_pass+1)); else pnpm_fail=$((pnpm_fail+1)); fi
done
echo "direct ./node_modules/.bin/biome : $direct_pass pass / $direct_fail fail"
echo "pnpm exec biome                  : $pnpm_pass pass / $pnpm_fail fail"
if [ "$pnpm_fail" -gt 0 ] && [ "$direct_fail" -eq 0 ]; then
  echo "REPRODUCED: pnpm-spawned biome failing while the identical direct invocation passes"
elif [ "$pnpm_fail" -gt 0 ]; then
  echo "PARTIAL: both forms failed at least once; see issue for why direct-vs-pnpm is the key signal"
else
  echo "NOT REPRODUCED in this run: window was healthy. Failures arrive in multi-minute windows;"
  echo "re-run this script periodically (e.g. every few minutes) on the same machine."
fi
